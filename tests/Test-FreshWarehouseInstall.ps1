[CmdletBinding()]
param(
    [string]$Server='localhost',
    [string]$MSBuildPath='C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe',
    [string]$SqlPackagePath='C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe',
    [string]$EvidenceDirectory=(Join-Path $PSScriptRoot '..\docs\evidencias\instalacion-nueva')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1') -Force

$repo=Split-Path $PSScriptRoot -Parent
$id=[Guid]::NewGuid().ToString('N')
$database="Northwind_DW_Fresh_${id}_Test"
$created=$false
$olapTouched=$false
$olapPassed=$false
$testError=$null
$cleanupError=$null
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'

function New-Connection([string]$InitialCatalog) {
    $builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server
    $builder['Initial Catalog']=$InitialCatalog
    $builder['Integrated Security']=$true
    $builder['Encrypt']=$true
    $builder['TrustServerCertificate']=$true
    $builder['Pooling']=$false
    return [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Invoke-AdminSql([string]$InitialCatalog,[string]$Sql) {
    $connection=New-Connection $InitialCatalog
    try {
        $connection.Open()
        $command=$connection.CreateCommand()
        $command.CommandTimeout=300
        $command.CommandText=$Sql
        $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($command)
        $data=[System.Data.DataSet]::new()
        try { [void]$adapter.Fill($data); return ,$data }
        finally { $adapter.Dispose(); $command.Dispose() }
    }
    finally { $connection.Dispose() }
}

function Save-Output([string]$Name,[scriptblock]$Action) {
    $output=@(& $Action 2>&1 | ForEach-Object { [string]$_ })
    $output | Set-Content -LiteralPath (Join-Path $EvidenceDirectory $Name) -Encoding utf8
    if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw "Falló $Name; consulte la evidencia."}
    return $output
}

try {
    foreach($path in @($MSBuildPath,$SqlPackagePath)){
        if(-not(Test-Path -LiteralPath $path)){throw "No se encontró la herramienta requerida: $path"}
    }

    $existence=Invoke-AdminSql 'master' "SELECT DB_ID(N'$database') AS DatabaseId;"
    if($existence.Tables[0].Rows[0].DatabaseId -isnot [DBNull]){
        throw 'El nombre temporal generado ya existe; no se modifica una base previa.'
    }
    [void](Invoke-AdminSql 'master' "CREATE DATABASE [$database]; ALTER DATABASE [$database] SET TRUSTWORTHY OFF; ALTER DATABASE [$database] SET DB_CHAINING OFF;")
    $created=$true
    [void](Invoke-AdminSql $database @"
IF DB_NAME()<>N'$database' OR DB_ID(N'NorthWind') IS NULL
    THROW 52601,'Destino u origen no esperado para instalación limpia.',1;
EXEC sys.sp_addextendedproperty @name=N'NorthwindPracticeTestDatabase',@value=N'Northwind_DW';
EXEC sys.sp_addextendedproperty @name=N'NorthwindFreshInstallTest',@value=N'$id';
CREATE USER [NorthwindFixture] WITHOUT LOGIN;
GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE TO [NorthwindFixture];
"@)

    $buildLog=Join-Path $EvidenceDirectory "build-$stamp.txt"
    & $MSBuildPath (Join-Path $repo 'Northwind.DW\Northwind.DW.sqlproj') /t:Build /p:VisualStudioVersion=18.0 /nologo /v:minimal *> $buildLog
    if($LASTEXITCODE -ne 0){throw "Falló la compilación del DW. Evidencia: $buildLog"}

    $dacpac=Join-Path $repo 'Northwind.DW\bin\Debug\Northwind.DW.dacpac'
    $builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server
    $builder['Initial Catalog']=$database
    $builder['Integrated Security']=$true
    $builder['Encrypt']=$true
    $builder['TrustServerCertificate']=$true
    $options=@("/SourceFile:$dacpac","/TargetConnectionString:$($builder.ConnectionString)",
        '/p:DropObjectsNotInSource=False','/p:DropExtendedPropertiesNotInSource=False',
        '/p:ScriptDatabaseOptions=False','/p:BlockOnPossibleDataLoss=True','/p:GenerateSmartDefaults=False')
    $publishLog=Join-Path $EvidenceDirectory "publish-$stamp.txt"
    & $SqlPackagePath /Action:Publish @options *> $publishLog
    if($LASTEXITCODE -ne 0){throw "Falló la publicación en la copia recién creada. Evidencia: $publishLog"}

    $migration=Get-Content -LiteralPath (Join-Path $repo 'Northwind.DW\Deployment\Migrate-NorthwindStar.sql') -Raw
    [void](Invoke-AdminSql $database $migration)
    $stage=Invoke-AdminSql $database @'
SELECT Stage FROM dbo.WarehouseMigrationState WHERE MigrationName=N'ReplaceNorthwindStarModel';
IF (SELECT COUNT(*) FROM dbo.FactSales)<>0 THROW 52602,'El DW nuevo debía quedar vacío antes de la carga.',1;
'@
    if($stage.Tables[0].Rows[0].Stage -ne 'SkippedEmpty'){
        throw "La migración de instalación vacía quedó en una etapa inesperada: $($stage.Tables[0].Rows[0].Stage)."
    }

    $load=Join-Path $repo 'scripts\Load-NorthwindWarehouse.ps1'
    $loadLog=Join-Path $EvidenceDirectory "load-$stamp.txt"
    & $load -Server $Server -WarehouseDatabase $database *> $loadLog
    if($LASTEXITCODE -ne 0){throw "Falló la primera carga. Evidencia: $loadLog"}
    $first=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseDatabase $database)
    if(@($first | Where-Object {-not $_.Coincide}).Count -gt 0){throw 'La carga inicial no concilia con Northwind_Test.'}

    $repeatLog=Join-Path $EvidenceDirectory "repeat-$stamp.txt"
    & $load -Server $Server -WarehouseDatabase $database *> $repeatLog
    if($LASTEXITCODE -ne 0){throw "Falló la repetición de carga. Evidencia: $repeatLog"}
    $second=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseDatabase $database)
    if(@($second | Where-Object {-not $_.Coincide}).Count -gt 0){throw 'La carga repetida no concilia con Northwind_Test.'}

    $result=Invoke-AdminSql $database @'
SELECT COUNT_BIG(*) AS Lines,COUNT(DISTINCT OrderID) AS Orders,
       SUM(CONVERT(bigint,Quantity)) AS Units,
       SUM(GrossAmount) AS GrossAmount,SUM(DiscountAmount) AS DiscountAmount,
       SUM(NetAmount) AS NetAmount
FROM dbo.FactSales;
SELECT PackageName,CONVERT(bigint,LastRowVersion) AS LastRowVersion
FROM dbo.PackageConfig ORDER BY PackageName;
SELECT Stage FROM dbo.WarehouseMigrationState WHERE MigrationName=N'ReplaceNorthwindStarModel';
'@
    $metrics=$result.Tables[0].Rows[0]
    if([long]$metrics.Lines -ne 2155 -or [long]$metrics.Orders -ne 830 -or [long]$metrics.Units -ne 51317){
        throw "Conteos distintos a la referencia: $($metrics.Lines) líneas, $($metrics.Orders) pedidos, $($metrics.Units) unidades."
    }
    if($result.Tables[1].Rows.Count -ne 6 -or $result.Tables[2].Rows[0].Stage -ne 'SkippedEmpty'){
        throw 'Faltan controles de proceso o la etapa de instalación limpia cambió.'
    }

    $olapTouched=$true
    $olapLog=Join-Path $EvidenceDirectory "olap-$stamp.txt"
    & (Join-Path $PSScriptRoot 'Test-NorthwindOLAP.ps1') -Server $Server -AnalysisServer 'localhost' -WarehouseDatabase $database -EvidenceDirectory (Join-Path $EvidenceDirectory 'olap') *> $olapLog
    $olapPassed=$true

    $report=[ordered]@{
        Result='PASS'; Database=$database; MigrationStage='SkippedEmpty'
        Lines=[long]$metrics.Lines; Orders=[long]$metrics.Orders; Units=[long]$metrics.Units
        GrossAmount=[decimal]$metrics.GrossAmount; DiscountAmount=[decimal]$metrics.DiscountAmount; NetAmount=[decimal]$metrics.NetAmount
        Checks=$second; OLAPIntegration='PASS'; SourceDatabase='Northwind_Test'; Cleanup='Dropped temporary database'
    }
}
catch {
    $testError=$_.Exception.Message
    $report=[ordered]@{Result='FAILED';Database=$database;TestError=$testError;CleanupError=$null}
}
finally {
    if($olapTouched){
        try {
            & (Join-Path $PSScriptRoot '../scripts/Process-NorthwindOLAP.ps1') -AnalysisServer 'localhost' -ModelDatabase 'NorthwindOLAP_Test' -WarehouseServer $Server -WarehouseDatabase 'Northwind_DW_Test' *> (Join-Path $EvidenceDirectory "restore-olap-$stamp.txt")
        }
        catch {$cleanupError="No se pudo devolver NorthwindOLAP_Test a Northwind_DW_Test: $($_.Exception.Message)"}
    }
    if($created -and -not $cleanupError){
        try {
            [void](Invoke-AdminSql 'master' @"
IF DB_NAME()<>N'master' OR NOT EXISTS(SELECT 1 FROM [$database].sys.extended_properties
 WHERE class=0 AND name=N'NorthwindFreshInstallTest' AND CONVERT(nvarchar(128),value)=N'$id')
    THROW 52603,'La limpieza no reconoce la base temporal creada por esta ejecución.',1;
ALTER DATABASE [$database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$database];
"@)
        }
        catch {$cleanupError=$_.Exception.Message}
    }
}

$report.CleanupError=$cleanupError
$reportPath=Join-Path $EvidenceDirectory "fresh-install-$stamp.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
if($testError -or $cleanupError){throw "Instalación limpia: $testError. Limpieza: $cleanupError. Evidencia: $reportPath"}
Write-Output "PASS: instalación vacía, carga inicial, repetición, conciliación e integración OLAP. Evidencia: $reportPath"
