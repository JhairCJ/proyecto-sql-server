[CmdletBinding()]
param(
    [string]$Server='localhost',
    [ValidateSet('Northwind_DW','Northwind_DW_Test')]
    [string]$WarehouseDatabase='Northwind_DW_Test',
    [string]$SqlPackagePath='C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe',
    [string]$EvidenceDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$EvidenceDirectory = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $PSScriptRoot '..\docs\evidencias\seccion-dw'
} else {
    $EvidenceDirectory
}
$repo=Split-Path $PSScriptRoot -Parent
if(-not(Test-Path -LiteralPath $SqlPackagePath)){throw 'Falta SqlPackage: indique -SqlPackagePath de su instalación SSDT.'}
$msbuild='C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe'
if(-not(Test-Path -LiteralPath $msbuild)){throw 'Falta MSBuild de Visual Studio 2026.'}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$Server;$builder['Initial Catalog']=$WarehouseDatabase
$builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
$connection=[System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try {
    $connection.Open();$command=$connection.CreateCommand();$command.CommandTimeout=300
    $command.CommandText=@'
IF DB_NAME()<>@targetDatabase
 THROW 52010,'Publicación rechazada: base inesperada.',1;
IF DB_NAME()=N'Northwind_DW_Test' AND NOT EXISTS
 (SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
  AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 52010,'Publicación rechazada: no es la copia marcada del DW.',1;
IF DB_NAME()=N'Northwind_DW' AND EXISTS
 (SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase')
 THROW 52010,'Publicación rechazada: la base principal está marcada como copia.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE name=DB_NAME() AND (is_trustworthy_on=1 OR is_db_chaining_on=1))
 THROW 52017,'Publicación rechazada: aislamiento de copia desactivado.',1;
IF OBJECT_ID(N'dbo.WarehouseMigrationState',N'U') IS NOT NULL
    EXEC sys.sp_executesql N'IF EXISTS(SELECT 1 FROM dbo.WarehouseMigrationState WHERE MigrationName=N''ReplaceNorthwindStarModel'' AND Stage=N''Cutover'')
       AND OBJECT_ID(N''dbo.Fact_Ventas'',N''U'') IS NOT NULL
        THROW 52018,''Publicación detenida: Cutover está registrado pero el hecho heredado sigue presente.'',1;';
'@
    [void]$command.Parameters.AddWithValue('@targetDatabase',$WarehouseDatabase)
    [void]$command.ExecuteNonQuery()
    $command.Parameters.Clear()

    & (Join-Path $PSScriptRoot 'Build-NorthwindWarehouse.ps1') -MSBuildPath $msbuild *> (Join-Path $EvidenceDirectory 'compilacion-publicacion.txt')

    if($WarehouseDatabase -eq 'Northwind_DW'){
        $command.CommandText=@'
DECLARE @directory nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
IF @directory IS NULL THROW 52019,'No se pudo resolver la carpeta de respaldo del servidor.',1;
DECLARE @path nvarchar(4000)=@directory+CASE WHEN RIGHT(@directory,1) IN(N'\',N'/') THEN N'' ELSE N'\' END
    +N'Northwind_DW_before_star_'+CONVERT(nvarchar(36),NEWID())+N'.bak';
BACKUP DATABASE [Northwind_DW] TO DISK=@path WITH COPY_ONLY,CHECKSUM,COMPRESSION;
RESTORE VERIFYONLY FROM DISK=@path WITH CHECKSUM;
SELECT @path;
'@
        $backupPath=[string]$command.ExecuteScalar()
        $backupPath | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'respaldo-dw.txt') -Encoding utf8
    }

    $command.CommandText="SELECT CASE WHEN OBJECT_ID(N'dbo.Fact_Ventas',N'U') IS NULL THEN 0 ELSE 1 END;"
    $hasLegacyFact=[int]$command.ExecuteScalar() -eq 1
    if($hasLegacyFact){
        $prepare=Join-Path $repo 'Northwind.DW\Deployment\Prepare-LegacyWarehouse.sql'
        Copy-Item -LiteralPath $prepare -Destination (Join-Path $EvidenceDirectory 'preparacion-legado-revisable.sql') -Force
        $command.CommandText=Get-Content -LiteralPath $prepare -Raw
        [void]$command.ExecuteNonQuery()
    }

    $dacpac=Join-Path $repo 'Northwind.DW\bin\Debug\Northwind.DW.dacpac'
    $options=@("/SourceFile:$dacpac","/TargetConnectionString:$($builder.ConnectionString)",
       '/p:DropObjectsNotInSource=False','/p:DropExtendedPropertiesNotInSource=False',
       '/p:ScriptDatabaseOptions=False','/p:BlockOnPossibleDataLoss=True','/p:GenerateSmartDefaults=False')
    & $SqlPackagePath /Action:Script @options "/OutputPath:$(Join-Path $EvidenceDirectory 'publicacion-revisable.sql')" *> (Join-Path $EvidenceDirectory 'plan-publicacion.txt')
    if($LASTEXITCODE -ne 0){throw 'Falló generación del script DW; consulte plan-publicacion.txt.'}
    & $SqlPackagePath /Action:Publish @options *> (Join-Path $EvidenceDirectory 'publicacion.txt')
    if($LASTEXITCODE -ne 0){throw 'Falló publicación DW; consulte publicacion.txt. Los objetos y marcas anteriores se conservan.'}

    $migration=Join-Path $repo 'Northwind.DW\Deployment\Migrate-NorthwindStar.sql'
    Copy-Item -LiteralPath $migration -Destination (Join-Path $EvidenceDirectory 'migracion-revisable.sql') -Force
    $command.CommandText=Get-Content -LiteralPath $migration -Raw
    [void]$command.ExecuteNonQuery()

    $command.CommandText=@'
SELECT MigrationName,SchemaVersion,Stage,SourceDatabase,CONVERT(bigint,SourceCut) AS SourceCut,UpdatedAt
FROM dbo.WarehouseMigrationState WHERE MigrationName=N'ReplaceNorthwindStarModel';
SELECT (SELECT COUNT_BIG(*) FROM dbo.DimDate) AS DimDateRows,
       (SELECT COUNT_BIG(*) FROM dbo.DimProduct) AS DimProductRows,
       (SELECT COUNT_BIG(*) FROM dbo.DimCustomer) AS DimCustomerRows,
       (SELECT COUNT_BIG(*) FROM dbo.DimEmployee) AS DimEmployeeRows,
       (SELECT COUNT_BIG(*) FROM dbo.DimShipper) AS DimShipperRows,
       (SELECT COUNT_BIG(*) FROM dbo.DimSupplier) AS DimSupplierRows,
       (SELECT COUNT_BIG(*) FROM dbo.DimGeography) AS DimGeographyRows,
       (SELECT COUNT_BIG(*) FROM dbo.FactSales) AS FactSalesRows,
       (SELECT COUNT_BIG(*) FROM dbo.PackageConfig) AS PackageControls;
'@
    $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($command);$result=[System.Data.DataSet]::new()
    try{[void]$adapter.Fill($result);$result.WriteXml((Join-Path $EvidenceDirectory 'resultado-publicacion.xml'))}
    finally{$adapter.Dispose();$result.Dispose()}
    $command.Dispose()
    if($hasLegacyFact){
        Write-Output "DW actualizado en $WarehouseDatabase; las tablas anteriores se conservaron para la migración o recuperación."
    }else{
        Write-Output "DW actualizado en $WarehouseDatabase; no hay hecho heredado que preparar."
    }
    Write-Output "Scripts y registros: $EvidenceDirectory"
} finally {$connection.Dispose()}
