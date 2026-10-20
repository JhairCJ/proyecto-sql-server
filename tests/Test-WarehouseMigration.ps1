[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1') -Force

$target='Northwind_DW_Migration_Test'
$backupPath=$null
$created=$false
$token=[guid]::NewGuid().ToString('N')
$sqlPackage='C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe'
$connectionStringBuilder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionStringBuilder['Data Source']=$Server
$connectionStringBuilder['Integrated Security']=$true
$connectionStringBuilder['Encrypt']=$true
$connectionStringBuilder['TrustServerCertificate']=$true
$connectionStringBuilder['Pooling']=$false

function New-AdminConnection([string]$Database='master'){
    $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new($connectionStringBuilder.ConnectionString)
    $builder['Initial Catalog']=$Database
    $connection=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.Open()
    return $connection
}

function Invoke-Sql([string]$Database,[string]$Sql){
    $connection=New-AdminConnection $Database
    try{
        $command=$connection.CreateCommand()
        $command.CommandTimeout=300
        $command.CommandText=$Sql
        try{[void]$command.ExecuteNonQuery()}finally{$command.Dispose()}
    }finally{$connection.Dispose()}
}

function Read-Data([string]$Database,[string]$Sql){
    $connection=New-AdminConnection $Database
    try{
        $command=$connection.CreateCommand()
        $command.CommandTimeout=300
        $command.CommandText=$Sql
        $adapter=[Data.SqlClient.SqlDataAdapter]::new($command)
        $data=[Data.DataSet]::new()
        try{[void]$adapter.Fill($data);return ,$data}
        finally{$adapter.Dispose();$command.Dispose()}
    }finally{$connection.Dispose()}
}

function Get-SqlError($ErrorRecord){
    $exception=$ErrorRecord.Exception
    while($null -ne $exception -and $exception -isnot [Data.SqlClient.SqlException]){
        $exception=$exception.InnerException
    }
    return $exception
}

function Get-MigrationState {
    return (Read-Data $target @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.DimDate WHERE DateKey<>0) Dates,
       (SELECT COUNT_BIG(*) FROM dbo.DimCustomer WHERE CustomerKey<>0) Customers,
       (SELECT COUNT_BIG(*) FROM dbo.DimEmployee WHERE EmployeeKey<>0) Employees,
       (SELECT COUNT_BIG(*) FROM dbo.DimProduct) Products,
       (SELECT COUNT_BIG(*) FROM dbo.DimShipper WHERE ShipperKey<>0) Shippers,
       (SELECT COUNT_BIG(*) FROM dbo.DimSupplier WHERE SupplierKey<>0) Suppliers,
       (SELECT COUNT_BIG(*) FROM dbo.DimGeography WHERE GeographyKey<>0) Destinations,
       (SELECT COUNT_BIG(*) FROM dbo.FactSales) Sales,
       (SELECT COUNT_BIG(*) FROM dbo.Fact_Ventas) LegacySales,
       (SELECT COUNT_BIG(*) FROM dbo.WarehouseMigrationState) MigrationRows;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad FROM dbo.PackageConfig ORDER BY PackageName;
'@).GetXml()
}

try{
    if(-not(Test-Path -LiteralPath $sqlPackage)){throw 'No se encontró SqlPackage para preparar la copia temporal.'}
    $preflight=Read-Data 'master' @"
SELECT DB_ID(N'$target') AS ExistingTarget,
       CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath')) AS BackupPath,
       CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')) AS DataPath,
       CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultLogPath')) AS LogPath;
"@
    if($preflight.Tables[0].Rows[0].ExistingTarget -isnot [DBNull]){
        throw "La base temporal $target ya existe; no se reemplaza ni se modifica."
    }
    $sourceCheck=Read-Data 'Northwind_DW_Test' @'
IF DB_NAME()<>N'Northwind_DW_Test' OR NOT EXISTS
 (SELECT 1 FROM sys.extended_properties WHERE class=0
  AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
    THROW 52620,'La copia cargada no está marcada.',1;
SELECT COUNT_BIG(*) LegacySales FROM dbo.Fact_Ventas;
'@
    if([long]$sourceCheck.Tables[0].Rows[0].LegacySales -ne 2155){
        throw 'La copia fuente no contiene las 2.155 líneas anteriores requeridas.'
    }

    $backupDirectory=[string]$preflight.Tables[0].Rows[0].BackupPath
    $backupName=$target+'_'+$token+'.bak'
    $backupPath=Join-Path $backupDirectory $backupName
    $backupLiteral="N'"+$backupPath.Replace("'","''")+"'"
    Invoke-Sql 'master' "BACKUP DATABASE [Northwind_DW_Test] TO DISK=$backupLiteral WITH COPY_ONLY,CHECKSUM,COMPRESSION;"
    $files=Read-Data 'master' "RESTORE FILELISTONLY FROM DISK=$backupLiteral;"
    $moves=@()
    $index=0
    foreach($file in $files.Tables[0].Rows){
        $index++
        if($file.Type -notin @('D','L')){throw "Tipo de archivo inesperado: $($file.Type)"}
        $directory=if($file.Type -eq 'L'){[string]$preflight.Tables[0].Rows[0].LogPath}else{[string]$preflight.Tables[0].Rows[0].DataPath}
        $extension=if($file.Type -eq 'L'){'ldf'}else{'mdf'}
        $newFile=Join-Path $directory ($target+'_'+$token+'_'+$index+'.'+$extension)
        $logical=([string]$file.LogicalName).Replace("'","''")
        $pathLiteral=$newFile.Replace("'","''")
        $moves+= "MOVE N'$logical' TO N'$pathLiteral'"
    }
    $moveSql=$moves -join ','
    Invoke-Sql 'master' "RESTORE VERIFYONLY FROM DISK=$backupLiteral WITH CHECKSUM;"
    Invoke-Sql 'master' "IF DB_ID(N'$target') IS NOT NULL THROW 52621,'El destino temporal apareció antes de restaurar.',1; RESTORE DATABASE [$target] FROM DISK=$backupLiteral WITH CHECKSUM,RECOVERY,$moveSql;"
    $created=$true

    Invoke-Sql $target @"
ALTER DATABASE [$target] SET TRUSTWORTHY OFF;
ALTER DATABASE [$target] SET DB_CHAINING OFF;
EXEC sys.sp_updateextendedproperty @name=N'NorthwindPracticeTestDatabase',@value=N'Northwind_DW';
EXEC sys.sp_addextendedproperty @name=N'NorthwindMigrationRollbackTest',@value=N'$token';
IF USER_ID(N'NorthwindFixture') IS NULL CREATE USER [NorthwindFixture] WITHOUT LOGIN;
GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE TO [NorthwindFixture];
BEGIN TRANSACTION;
DELETE dbo.FactSales;
DELETE dbo.DimCustomer WHERE CustomerKey<>0;
DELETE dbo.DimEmployee WHERE EmployeeKey<>0;
DELETE dbo.DimProduct;
DELETE dbo.DimShipper WHERE ShipperKey<>0;
DELETE dbo.DimSupplier WHERE SupplierKey<>0;
DELETE dbo.DimGeography WHERE GeographyKey<>0;
DELETE dbo.DimDate WHERE DateKey<>0;
DELETE dbo.WarehouseMigrationState;
COMMIT TRANSACTION;
"@

    $row=Read-Data $target 'SELECT TOP(1) Venta_SK,ProductID FROM dbo.Fact_Ventas ORDER BY Venta_SK;'
    $legacyKey=[long]$row.Tables[0].Rows[0].Venta_SK
    $legacyProduct=[int]$row.Tables[0].Rows[0].ProductID
    Invoke-Sql $target "UPDATE dbo.Fact_Ventas SET ProductID=ProductID+1000000 WHERE Venta_SK=$legacyKey;"
    $migration=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Northwind.DW/Deployment/Migrate-NorthwindStar.sql') -Raw
    $rejected=$false
    $connection=New-AdminConnection $target
    try{
        $command=$connection.CreateCommand();$command.CommandTimeout=300;$command.CommandText=$migration
        try{[void]$command.ExecuteNonQuery()}
        catch{
            $sqlError=Get-SqlError $_
            if($null -eq $sqlError -or $sqlError.Number -ne 52132){throw}
            $rejected=$true
        }finally{$command.Dispose()}
    }finally{$connection.Dispose()}
    Invoke-Sql $target "UPDATE dbo.Fact_Ventas SET ProductID=$legacyProduct WHERE Venta_SK=$legacyKey;"
    if(-not $rejected){throw 'La migración aceptó un ProductID ambiguo en el legado.'}
    $empty=Read-Data $target @'
SELECT COUNT_BIG(*) NewSales FROM dbo.FactSales;
SELECT COUNT_BIG(*) MigrationRows FROM dbo.WarehouseMigrationState;
'@
    if([long]$empty.Tables[0].Rows[0].NewSales -ne 0 -or [long]$empty.Tables[1].Rows[0].MigrationRows -ne 0){
        throw 'El rechazo por referencia ambigua dejó datos nuevos o una marca parcial.'
    }
    'PASS: una identidad ProductID ambigua detiene la migración antes de copiar.'

    Invoke-Sql $target @"
CREATE TRIGGER dbo.NorthwindTestMigrationFail ON dbo.WarehouseMigrationState AFTER INSERT AS
BEGIN
    THROW 52622,'Fallo inyectado al registrar la etapa.',1;
END;
"@
    $triggerCreated=$true
    $beforeFailure=Get-MigrationState
    $rejected=$false
    $connection=New-AdminConnection $target
    try{
        $command=$connection.CreateCommand();$command.CommandTimeout=300;$command.CommandText=$migration
        try{[void]$command.ExecuteNonQuery()}
        catch{
            $sqlError=Get-SqlError $_
            if($null -eq $sqlError -or $sqlError.Number -ne 52622){throw}
            $rejected=$true
        }finally{$command.Dispose()}
    }finally{$connection.Dispose()}
    if(-not $rejected){throw 'La migración no llegó a la inyección de fallo esperada.'}
    if((Get-MigrationState) -cne $beforeFailure){
        throw 'El fallo de migración confirmó filas, corte o estado parcial.'
    }
    Invoke-Sql $target 'DROP TRIGGER dbo.NorthwindTestMigrationFail;'
    $triggerCreated=$false
    'PASS: el fallo al registrar etapa revierte dimensiones, hechos, proveedor y estado.'

    $connection=New-AdminConnection $target
    try{
        $command=$connection.CreateCommand();$command.CommandTimeout=300;$command.CommandText=$migration
        [void]$command.ExecuteNonQuery();$command.Dispose()
    }finally{$connection.Dispose()}
    $afterMigration=Read-Data $target @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.FactSales) Sales,
       (SELECT COUNT_BIG(DISTINCT OrderID) FROM dbo.FactSales) Orders,
       (SELECT SUM(CONVERT(BIGINT,Quantity)) FROM dbo.FactSales) Units,
       (SELECT COUNT_BIG(*) FROM dbo.DimSupplier WHERE SupplierKey<>0) Suppliers,
       (SELECT COUNT_BIG(*) FROM dbo.DimGeography WHERE GeographyKey<>0) Destinations,
       (SELECT Stage FROM dbo.WarehouseMigrationState WHERE MigrationName=N'ReplaceNorthwindStarModel') Stage;
'@
    $migrated=$afterMigration.Tables[0].Rows[0]
    $migrationValid=([long]$migrated.Sales -eq 2155) -and
        ([long]$migrated.Orders -eq 830) -and
        ([long]$migrated.Units -eq 51317) -and
        ([int]$migrated.Suppliers -eq 29) -and
        ([int]$migrated.Destinations -eq 89) -and
        ([string]$migrated.Stage -eq 'Validated')
    if(-not $migrationValid){
        throw 'La reanudación no migró dimensiones, hechos, proveedores y destinos completos.'
    }
    $migratedState=Get-MigrationState
    $connection=New-AdminConnection $target
    try{
        $command=$connection.CreateCommand();$command.CommandTimeout=300;$command.CommandText=$migration
        [void]$command.ExecuteNonQuery();$command.Dispose()
    }finally{$connection.Dispose()}
    if((Get-MigrationState) -cne $migratedState){
        throw 'La repetición duplicó datos o modificó marcas tras una migración completada.'
    }
    'PASS: reanudación completa 2.155 líneas y 89 destinos; otra ejecución es idempotente.'

    $loader=Join-Path $PSScriptRoot '../scripts/Load-NorthwindWarehouse.ps1'
    & $loader -Server $Server -WarehouseDatabase $target | Out-Null
    $comparison=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseDatabase $target)
    if(@($comparison|Where-Object{-not $_.Coincide}).Count -gt 0){
        throw 'La carga nueva no concilió después de migrar y antes de retirar el legado.'
    }
    [void](Invoke-Sql $target @'
IF (SELECT COUNT(*) FROM dbo.PackageConfig)<>6
 OR EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE LastSuccessfulLoad IS NULL)
    THROW 52624,'La carga de corte no confirmó los seis procesos.',1;
'@)

    $retire=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Northwind.DW/Deployment/Retire-LegacyWarehouse.sql') -Raw
    $retire=$retire.Replace('DECLARE @ConfirmCutover BIT=0;','DECLARE @ConfirmCutover BIT=1;')
    Invoke-Sql $target $retire
    $cutover=Read-Data $target @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.FactSales) Sales,
       (SELECT COUNT_BIG(DISTINCT OrderID) FROM dbo.FactSales) Orders,
       (SELECT SUM(CONVERT(bigint,Quantity)) FROM dbo.FactSales) Units,
       (SELECT COUNT(*) FROM dbo.PackageConfig) Controls,
       (SELECT Stage FROM dbo.WarehouseMigrationState WHERE MigrationName=N'ReplaceNorthwindStarModel') Stage,
       OBJECT_ID(N'dbo.Fact_Ventas',N'U') LegacyFact,
       OBJECT_ID(N'dbo.Dim_Cliente',N'U') LegacyCustomer,
       COL_LENGTH(N'std.Producto',N'SupplierName') LegacySupplierName,
       COL_LENGTH(N'std.Producto',N'SupplierCountry') LegacySupplierCountry,
       COL_LENGTH(N'std.Producto',N'SupplierRowVersion') LegacySupplierMark;
'@
    $cut=$cutover.Tables[0].Rows[0]
    if([long]$cut.Sales -ne 2155 -or [long]$cut.Orders -ne 830 -or [long]$cut.Units -ne 51317 -or
       [int]$cut.Controls -ne 6 -or [string]$cut.Stage -ne 'Cutover' -or
       $cut.LegacyFact -isnot [DBNull] -or $cut.LegacyCustomer -isnot [DBNull] -or
       $cut.LegacySupplierName -isnot [DBNull] -or $cut.LegacySupplierCountry -isnot [DBNull] -or $cut.LegacySupplierMark -isnot [DBNull]){
        throw 'La retirada alteró los datos finales o dejó objetos heredados administrados.'
    }
    'PASS: retirada explícita conserva las ventas y controles, y elimina objetos y columnas heredados.'

    $evidence=Join-Path (Split-Path $PSScriptRoot -Parent) "docs/evidencias/migracion/$token"
    [void](New-Item -ItemType Directory -Path $evidence -Force)
    $publishConnection=[Data.SqlClient.SqlConnectionStringBuilder]::new($connectionStringBuilder.ConnectionString)
    $publishConnection['Initial Catalog']=$target
    $dacpac=Join-Path (Split-Path $PSScriptRoot -Parent) 'Northwind.DW/bin/Debug/Northwind.DW.dacpac'
    $publishLog=Join-Path $evidence 'publicacion-tras-cutover.txt'
    & $sqlPackage /Action:Publish "/SourceFile:$dacpac" "/TargetConnectionString:$($publishConnection.ConnectionString)" '/p:DropObjectsNotInSource=False' '/p:DropExtendedPropertiesNotInSource=False' '/p:ScriptDatabaseOptions=False' '/p:BlockOnPossibleDataLoss=True' *> $publishLog
    if($LASTEXITCODE -ne 0){throw "Falló la publicación repetida posterior al corte. Evidencia: $publishLog"}
    $afterPublish=Read-Data $target @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.FactSales) Sales,
       (SELECT Stage FROM dbo.WarehouseMigrationState WHERE MigrationName=N'ReplaceNorthwindStarModel') Stage,
       OBJECT_ID(N'dbo.Fact_Ventas',N'U') LegacyFact,
       COL_LENGTH(N'std.Producto',N'SupplierName') LegacySupplierName;
'@
    if([long]$afterPublish.Tables[0].Rows[0].Sales -ne 2155 -or
       [string]$afterPublish.Tables[0].Rows[0].Stage -ne 'Cutover' -or
       $afterPublish.Tables[0].Rows[0].LegacyFact -isnot [DBNull] -or
       $afterPublish.Tables[0].Rows[0].LegacySupplierName -isnot [DBNull]){
        throw 'La publicación posterior recreó el legado o cambió el estado de corte.'
    }
    $beforeCutoverRepeat=Read-Data $target @'
SELECT * FROM dbo.PackageConfig ORDER BY PackageName;
SELECT * FROM dbo.FactSales ORDER BY SalesKey;
'@
    $connection=New-AdminConnection $target
    try{$command=$connection.CreateCommand();$command.CommandTimeout=300;$command.CommandText=$migration;[void]$command.ExecuteNonQuery();$command.Dispose()}finally{$connection.Dispose()}
    if((Read-Data $target @'
SELECT * FROM dbo.PackageConfig ORDER BY PackageName;
SELECT * FROM dbo.FactSales ORDER BY SalesKey;
'@).GetXml() -cne $beforeCutoverRepeat.GetXml()){
        throw 'La repetición de migración tras Cutover cambió ventas o controles.'
    }
    & $loader -Server $Server -WarehouseDatabase $target | Out-Null
    $afterLoad=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseDatabase $target)
    if(@($afterLoad|Where-Object{-not $_.Coincide}).Count -gt 0){
        throw 'La carga incremental posterior a Cutover no concilió con el origen.'
    }
    'PASS: publicación repetida y nueva carga funcionan tras Cutover sin recrear tablas anteriores.'
}finally{
    if($created){
        try{
            $cleanup=New-AdminConnection 'master'
            try{
                $command=$cleanup.CreateCommand();$command.CommandTimeout=60
                $command.CommandText=@"
IF DB_ID(N'$target') IS NOT NULL
BEGIN
    IF DB_NAME()<>N'master' OR NOT EXISTS
      (SELECT 1 FROM [$target].sys.extended_properties
       WHERE class=0 AND name=N'NorthwindMigrationRollbackTest' AND CONVERT(nvarchar(128),value)=N'$token')
        THROW 52623,'La limpieza rechazó un destino temporal cuya identidad no coincide.',1;
    ALTER DATABASE [$target] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$target];
END;
"@
                [void]$command.ExecuteNonQuery()
            }finally{$cleanup.Dispose()}
        }catch{Write-Warning "No se pudo retirar la base temporal protegida $target. $($_.Exception.Message)"}
    }
    if($null -ne $backupPath){
        try{
            $backupCleanup=New-AdminConnection 'master'
            try{
                $command=$backupCleanup.CreateCommand();$command.CommandTimeout=60
                $command.CommandText=@'
DECLARE @exists TABLE(FileExists INT,IsDirectory INT,ParentExists INT);
INSERT @exists EXEC master.dbo.xp_fileexist @path;
IF (SELECT FileExists FROM @exists)=1
    EXEC master.dbo.xp_delete_file 0,@path;
'@
                [void]$command.Parameters.Add('@path',[Data.SqlDbType]::NVarChar,4000)
                $command.Parameters['@path'].Value=$backupPath
                [void]$command.ExecuteNonQuery()
            }finally{$backupCleanup.Dispose()}
        }catch{Write-Warning "No se pudo retirar el respaldo temporal exacto $backupPath. $($_.Exception.Message)"}
    }
}
