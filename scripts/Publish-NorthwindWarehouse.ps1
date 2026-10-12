[CmdletBinding()]
param(
    [string]$Server='localhost',
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
if(-not(Test-Path -LiteralPath $SqlPackagePath)){throw 'Falta SqlPackage: indique -SqlPackagePath de su instalacion SSDT.'}
$msbuild='C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe'
if(-not(Test-Path -LiteralPath $msbuild)){throw 'Falta MSBuild de Visual Studio 2026.'}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$Server;$builder['Initial Catalog']='Northwind_DW_Test'
$builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
$connection=[System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try {
    $connection.Open();$command=$connection.CreateCommand();$command.CommandTimeout=120
    $command.CommandText=@'
IF DB_NAME()<>N'Northwind_DW_Test' OR NOT EXISTS
 (SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
  AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 52010,'Publicacion rechazada: no es la copia marcada del DW.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE name=DB_NAME() AND (is_trustworthy_on=1 OR is_db_chaining_on=1))
 THROW 52017,'Publicacion rechazada: aislamiento de copia desactivado.',1;
'@
    [void]$command.ExecuteNonQuery()
    & $msbuild (Join-Path $repo 'Northwind.DW\Northwind.DW.sqlproj') /t:Build /p:VisualStudioVersion=18.0 /nologo /v:quiet *> (Join-Path $EvidenceDirectory 'compilacion-publicacion.txt')
    if($LASTEXITCODE -ne 0){throw 'Fallo compilacion DW; consulte compilacion-publicacion.txt.'}
    $migration=Join-Path $repo 'Northwind.DW\Deployment\Prepare-LegacyWarehouse.sql'
    Copy-Item -LiteralPath $migration -Destination (Join-Path $EvidenceDirectory 'migracion-revisable.sql') -Force
    $command.CommandText=Get-Content -LiteralPath $migration -Raw
    [void]$command.ExecuteNonQuery()
    $dacpac=Join-Path $repo 'Northwind.DW\bin\Debug\Northwind.DW.dacpac'
    $options=@("/SourceFile:$dacpac","/TargetConnectionString:$($builder.ConnectionString)",
       '/p:DropObjectsNotInSource=False','/p:DropExtendedPropertiesNotInSource=False',
       '/p:ScriptDatabaseOptions=False','/p:BlockOnPossibleDataLoss=True','/p:GenerateSmartDefaults=False')
    & $SqlPackagePath /Action:Script @options "/OutputPath:$(Join-Path $EvidenceDirectory 'publicacion-revisable.sql')" *> (Join-Path $EvidenceDirectory 'plan-publicacion.txt')
    if($LASTEXITCODE -ne 0){throw 'Fallo generacion del script DW; consulte plan-publicacion.txt.'}
    & $SqlPackagePath /Action:Publish @options *> (Join-Path $EvidenceDirectory 'publicacion.txt')
    if($LASTEXITCODE -ne 0){throw 'Fallo publicacion DW; consulte publicacion.txt. No se reinician datos ni marcas.'}
    $sourceBuilder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new($builder.ConnectionString)
    $sourceBuilder['Initial Catalog']='Northwind_Test'
    $source=[System.Data.SqlClient.SqlConnection]::new($sourceBuilder.ConnectionString)
    try {
       $source.Open();$read=$source.CreateCommand()
       $read.CommandText=@'
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'NorthWind')
 THROW 52010,'Origen de calendario no es copia marcada.',1;
SELECT MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta FROM dbo.Orders
CROSS APPLY(VALUES(CONVERT(date,OrderDate)),(CONVERT(date,RequiredDate)),(CONVERT(date,ShippedDate))) d(Fecha);
'@
       $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($read);$range=[System.Data.DataTable]::new()
       try {[void]$adapter.Fill($range)} finally {$adapter.Dispose();$read.Dispose()}
       if($range.Rows[0].Desde -is [DBNull] -or $range.Rows[0].Hasta -is [DBNull]){throw 'Origen sin fechas: no se puede determinar calendario.'}
       $command.CommandText='EXEC dbo.DW_LoadDimTiempo @FechaInicio=@desde,@FechaFin=@hasta;'
       [void]$command.Parameters.Add('@desde',[System.Data.SqlDbType]::Date);$command.Parameters['@desde'].Value=$range.Rows[0].Desde
       [void]$command.Parameters.Add('@hasta',[System.Data.SqlDbType]::Date);$command.Parameters['@hasta'].Value=$range.Rows[0].Hasta
       [void]$command.ExecuteNonQuery()
    } finally {$source.Dispose()}
    $command.Dispose()
    Write-Output 'DW publicado en Northwind_DW_Test; controles conservados, desconocidos preparados y calendario poblado.'
    Write-Output "Scripts y logs: $EvidenceDirectory"
} finally {$connection.Dispose()}
