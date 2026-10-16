[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$MSBuildPath = 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe',
    [string]$SqlPackagePath = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe',
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '../docs/evidencias/ssis')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $repo 'scripts/Run-NorthwindETL.ps1'
$id = [guid]::NewGuid().ToString('N').Substring(0,8)
$source = "Northwind_SSIS_OLTP_$id"
$warehouse = "Northwind_DW_SSIS_${id}_Test"
$backupPath = $null
$backupFolder = $null
$sourceCreated = $false
$warehouseCreated = $false
$triggerCreated = $false
$testError = $null
$cleanupError = $null
$report = [ordered]@{ Result = 'FAILED'; RunId = $id; Source = $source; Warehouse = $warehouse }
$runEvidence = Join-Path $EvidenceDirectory $id
[void](New-Item -ItemType Directory -Path $runEvidence -Force)

function New-Connection([string]$Database) {
    $builder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Pooling'] = $false
    return [Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Invoke-Sql([string]$Database, [string]$Sql) {
    $connection = New-Connection $Database
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 600
        $command.CommandText = $Sql
        $adapter = [Data.SqlClient.SqlDataAdapter]::new($command)
        $data = [Data.DataSet]::new()
        try { [void]$adapter.Fill($data); return ,$data }
        finally { $adapter.Dispose(); $command.Dispose() }
    }
    finally { $connection.Dispose() }
}

function Invoke-Load([string]$Package = 'CargarNorthwind') {
    $log = Join-Path $runEvidence "$Package-$([guid]::NewGuid().ToString('N')).txt"
    & $runner -Server $Server -SourceDatabase $source -WarehouseDatabase $warehouse -Package $Package -LogDirectory $runEvidence *> $log
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Falló SSIS ($Package); revise $log." }
    if (-not (Test-Path -LiteralPath $log)) { throw "SSIS no generó el registro esperado para $Package." }
}

function Get-State([switch]$IncludeStaging, [switch]$IncludeLoadTimes) {
    $staging = if ($IncludeStaging) {
@'
SELECT * FROM std.Cliente ORDER BY CustomerID;
SELECT * FROM std.Empleado ORDER BY EmployeeID;
SELECT * FROM std.Proveedor ORDER BY SupplierID;
SELECT * FROM std.Producto ORDER BY ProductID;
SELECT * FROM std.Transportista ORDER BY ShipperID;
SELECT * FROM std.Ventas ORDER BY OrderID,ProductID;
'@
    } else { '' }
    $loadTime = if ($IncludeLoadTimes) { ',LastSuccessfulLoad' } else { '' }
    $state = Invoke-Sql $warehouse @"
SELECT * FROM dbo.DimDate ORDER BY DateKey;
SELECT * FROM dbo.DimProduct ORDER BY ProductKey;
SELECT * FROM dbo.DimCustomer ORDER BY CustomerKey;
SELECT * FROM dbo.DimEmployee ORDER BY EmployeeKey;
SELECT * FROM dbo.DimShipper ORDER BY ShipperKey;
SELECT * FROM dbo.DimSupplier ORDER BY SupplierKey;
SELECT * FROM dbo.DimGeography ORDER BY GeographyKey;
SELECT * FROM dbo.FactSales ORDER BY SalesKey;
SELECT PackageName,LastRowVersion$loadTime FROM dbo.PackageConfig ORDER BY PackageName;
$staging
"@
    return $state.GetXml()
}

function Get-Reconciliation {
    $sourceMetrics = Invoke-Sql $source @'
WITH Gross AS
(
    SELECT CONVERT(decimal(19,2),ROUND(CONVERT(decimal(5,0),Quantity)*CONVERT(decimal(19,4),UnitPrice),2)) AS GrossAmount,
           CONVERT(decimal(9,6),Discount) AS Discount
    FROM dbo.OrderDetails
), Amounts AS
(
    SELECT GrossAmount,CONVERT(decimal(19,2),ROUND(GrossAmount*Discount,2)) AS DiscountAmount
    FROM Gross
)
SELECT (SELECT COUNT(*) FROM dbo.Customers) Customers,
       (SELECT COUNT(*) FROM dbo.Employees) Employees,
       (SELECT COUNT(*) FROM dbo.Products) Products,
       (SELECT COUNT(*) FROM dbo.Shippers) Shippers,
       (SELECT COUNT(*) FROM dbo.Suppliers) Suppliers,
       (SELECT COUNT(*) FROM dbo.OrderDetails) Lines,
       (SELECT COUNT(DISTINCT OrderID) FROM dbo.OrderDetails) Orders,
       (SELECT SUM(CONVERT(bigint,Quantity)) FROM dbo.OrderDetails) Units,
       (SELECT SUM(GrossAmount) FROM Amounts) GrossAmount,
       (SELECT SUM(DiscountAmount) FROM Amounts) DiscountAmount,
       (SELECT SUM(GrossAmount-DiscountAmount) FROM Amounts) NetAmount,
       (SELECT SUM(CONVERT(decimal(19,4),Freight)) FROM dbo.Orders) Freight;
'@
    $warehouseMetrics = Invoke-Sql $warehouse @'
SELECT (SELECT COUNT(*) FROM dbo.DimCustomer WHERE CustomerKey<>0) Customers,
       (SELECT COUNT(*) FROM dbo.DimEmployee WHERE EmployeeKey<>0) Employees,
       (SELECT COUNT(*) FROM dbo.DimProduct) Products,
       (SELECT COUNT(*) FROM dbo.DimShipper WHERE ShipperKey<>0) Shippers,
       (SELECT COUNT(*) FROM dbo.DimSupplier WHERE SupplierKey<>0) Suppliers,
       COUNT(*) Lines,
       COUNT(DISTINCT OrderID) Orders,
       SUM(CONVERT(bigint,Quantity)) Units,
       SUM(GrossAmount) GrossAmount,
       SUM(DiscountAmount) DiscountAmount,
       SUM(NetAmount) NetAmount,
       (SELECT SUM(Freight) FROM
           (SELECT OrderID,MAX(Freight) AS Freight FROM dbo.FactSales GROUP BY OrderID) AS Orders) Freight
FROM dbo.FactSales;
IF EXISTS(SELECT 1 FROM dbo.FactSales GROUP BY OrderID
          HAVING COUNT(DISTINCT Freight)>1 OR (COUNT(Freight)>0 AND COUNT(Freight)<COUNT(*)))
    THROW 52550,'El flete no coincide entre las líneas del mismo pedido.',1;
IF COL_LENGTH(N'dbo.FactSales',N'FreightAmount') IS NOT NULL
    THROW 52551,'FactSales conserva la medida retirada FreightAmount.',1;
'@
    $left = $sourceMetrics.Tables[0].Rows[0]
    $right = $warehouseMetrics.Tables[0].Rows[0]
    foreach ($name in @('Customers','Employees','Products','Shippers','Suppliers','Lines','Orders','Units','GrossAmount','DiscountAmount','NetAmount','Freight')) {
        if ($left[$name] -ne $right[$name]) { throw "No coincide ${name}: OLTP='$($left[$name])', DW='$($right[$name])'." }
    }
    return [pscustomobject]@{ Source = $left; Warehouse = $right }
}

try {
    foreach ($path in @($MSBuildPath,$SqlPackagePath)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Falta la herramienta requerida: $path" }
    }
    & (Join-Path $repo 'scripts/Build-NorthwindETL.ps1') | Out-Null

    $paths = Invoke-Sql 'master' @'
SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')) DataPath,
       CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultLogPath')) LogPath,
       (SELECT TOP(1) service_account FROM sys.dm_server_services
        WHERE servicename LIKE N'SQL Server (%') EngineServiceAccount;
'@
    $backupFolder = Join-Path $env:ProgramData "NorthwindBI\Logs\SSIS-Test-$id"
    [void](New-Item -ItemType Directory -Path $backupFolder -Force)
    $serviceAccount = [string]$paths.Tables[0].Rows[0].EngineServiceAccount
    if ([string]::IsNullOrWhiteSpace($serviceAccount)) { throw 'SQL Server no informó la cuenta del servicio Database Engine.' }
    $folderAcl = Get-Acl -LiteralPath $backupFolder
    $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $serviceRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $serviceAccount,
        [System.Security.AccessControl.FileSystemRights]::Modify,
        $inheritance,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $folderAcl.SetAccessRule($serviceRule)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $userRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $currentUser,
        [System.Security.AccessControl.FileSystemRights]::Modify,
        $inheritance,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $folderAcl.SetAccessRule($userRule)
    Set-Acl -LiteralPath $backupFolder -AclObject $folderAcl
    $backupPath = Join-Path $backupFolder "Northwind-SSIS-$id.bak"
    # SQL Server creates backups under its service identity; pre-create the file so
    # the test runner retains its own delete permission for deterministic cleanup.
    [System.IO.File]::WriteAllBytes($backupPath,[byte[]]@())
    $backupLiteral = $backupPath.Replace("'","''")
    [void](Invoke-Sql 'Northwind_Test' @"
IF DB_NAME()<>N'Northwind_Test' OR NOT EXISTS(SELECT 1 FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'NorthWind')
    THROW 52552,'El origen no es la copia de prueba marcada.',1;
BACKUP DATABASE [Northwind_Test] TO DISK=N'$backupLiteral' WITH COPY_ONLY,CHECKSUM,COMPRESSION,INIT;
"@)

    $fileList = Invoke-Sql 'master' "RESTORE FILELISTONLY FROM DISK=N'$backupLiteral';"
    $moves = @()
    $fileNumber = 0
    foreach ($file in $fileList.Tables[0].Rows) {
        $fileNumber++
        $folder = if ($file.Type -eq 'L') { [string]$paths.Tables[0].Rows[0].LogPath } else { [string]$paths.Tables[0].Rows[0].DataPath }
        $extension = if ($file.Type -eq 'L') { 'ldf' } else { 'mdf' }
        $targetFile = Join-Path $folder "${source}_$fileNumber.$extension"
        $logical = ([string]$file.LogicalName).Replace("'","''")
        $target = $targetFile.Replace("'","''")
        $moves += "MOVE N'$logical' TO N'$target'"
    }
    [void](Invoke-Sql 'master' "IF DB_ID(N'$source') IS NOT NULL OR DB_ID(N'$warehouse') IS NOT NULL THROW 52553,'Nombre de copia ya existe.',1; RESTORE DATABASE [$source] FROM DISK=N'$backupLiteral' WITH CHECKSUM,RECOVERY,$($moves -join ','); ALTER DATABASE [$source] SET TRUSTWORTHY OFF; ALTER DATABASE [$source] SET DB_CHAINING OFF;")
    $sourceCreated = $true
    [void](Invoke-Sql $source "EXEC sys.sp_addextendedproperty @name=N'NorthwindSsisTestRun',@value=N'$id';")

    [void](Invoke-Sql 'master' "CREATE DATABASE [$warehouse]; ALTER DATABASE [$warehouse] SET TRUSTWORTHY OFF; ALTER DATABASE [$warehouse] SET DB_CHAINING OFF;")
    $warehouseCreated = $true
    [void](Invoke-Sql $warehouse @"
EXEC sys.sp_addextendedproperty @name=N'NorthwindPracticeTestDatabase',@value=N'Northwind_DW';
EXEC sys.sp_addextendedproperty @name=N'NorthwindSsisTestRun',@value=N'$id';
CREATE USER [NorthwindFixture] WITHOUT LOGIN;
GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE TO [NorthwindFixture];
"@)

    $dacpac = Join-Path $repo 'Northwind.DW/bin/Debug/Northwind.DW.dacpac'
    if (-not (Test-Path -LiteralPath $dacpac)) { throw 'No se encontró Northwind.DW.dacpac; compile primero el DW.' }
    $connectionBuilder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
    $connectionBuilder['Data Source'] = $Server
    $connectionBuilder['Initial Catalog'] = $warehouse
    $connectionBuilder['Integrated Security'] = $true
    $connectionBuilder['Encrypt'] = $true
    $connectionBuilder['TrustServerCertificate'] = $true
    $publishLog = Join-Path $runEvidence 'publish-dw.txt'
    & $SqlPackagePath /Action:Publish "/SourceFile:$dacpac" "/TargetConnectionString:$($connectionBuilder.ConnectionString)" '/p:DropObjectsNotInSource=False' '/p:DropExtendedPropertiesNotInSource=False' '/p:ScriptDatabaseOptions=False' '/p:BlockOnPossibleDataLoss=True' *> $publishLog
    if ($LASTEXITCODE -ne 0) { throw "Falló la publicación del DW de prueba; revise $publishLog." }
    $migration = Get-Content -LiteralPath (Join-Path $repo 'Northwind.DW/Deployment/Migrate-NorthwindStar.sql') -Raw
    [void](Invoke-Sql $warehouse $migration)

    Invoke-Load
    $baseline = Get-Reconciliation
    if ([long]$baseline.Warehouse.Lines -ne 2155 -or [long]$baseline.Warehouse.Orders -ne 830 -or [long]$baseline.Warehouse.Units -ne 51317) {
        throw 'La carga inicial no coincide con la referencia de 2.155 líneas, 830 pedidos y 51.317 unidades.'
    }
    [void](Invoke-Sql $warehouse @'
IF (SELECT COUNT(*) FROM dbo.PackageConfig)<>6 OR EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE LastSuccessfulLoad IS NULL)
    THROW 52554,'Faltan los seis controles confirmados.',1;
IF (SELECT COUNT(*) FROM dbo.DimGeography WHERE GeographyKey<>0)<>89
    THROW 52555,'No se cargaron los destinos de envío distintos esperados.',1;
IF (SELECT COUNT(*) FROM dbo.DimSupplier WHERE SupplierKey<>0)<>29
    THROW 52556,'No se cargaron los proveedores esperados.',1;
'@)

    Invoke-Load
    $stable = Get-State -IncludeStaging
    Invoke-Load
    if ((Get-State -IncludeStaging) -cne $stable) { throw 'La repetición de SSIS cambió claves, datos, staging o marcas.' }
    foreach ($package in @('Cliente','Empleado','Proveedor','Producto','Transportista','Ventas')) {
        Invoke-Load $package
        if ((Get-State -IncludeStaging) -cne $stable) { throw "El paquete individual $package cambió una carga sin datos nuevos." }
    }

    $fixture = Invoke-Sql $source @'
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @SupplierID int,@OrderID int,@CategoryID int;
INSERT dbo.Suppliers(CompanyName,ContactName,ContactTitle,[Address],City,Region,PostalCode,Country,Phone,Fax,HomePage)
VALUES(N'Proveedor SSIS',N'Contacto SSIS',N'Compras',N'Calle SSIS',N'La Paz',N'Sur',N'1000',N'Bolivia',N'555-SSIS',NULL,REPLICATE(CONVERT(nvarchar(max),N'H'),6000));
SET @SupplierID=CONVERT(int,SCOPE_IDENTITY());
UPDATE dbo.Products SET SupplierID=@SupplierID WHERE ProductID=11;
SELECT @CategoryID=CategoryID FROM dbo.Products WHERE ProductID=11;
UPDATE dbo.Categories SET [Description]=REPLICATE(CONVERT(nvarchar(max),N'C'),5000) WHERE CategoryID=@CategoryID;
INSERT dbo.Customers(CustomerID,CompanyName,ContactName,ContactTitle,[Address],City,Region,PostalCode,Country,Phone,Fax)
VALUES(N'TSSIS',N'Cliente SSIS',N'Contacto',N'Compras',N'Calle 1',N'La Paz',N'Sur',N'1000',N'Bolivia',N'555-0001',NULL);
INSERT dbo.Orders(CustomerID,EmployeeID,ShipVia,OrderDate,RequiredDate,ShippedDate,Freight,ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry)
VALUES(N'TSSIS',1,1,'20000101','20000102',NULL,30.1234,N'Calle SSIS 123',N'La Paz',N'Sur',N'1000',N'Bolivia');
SET @OrderID=CONVERT(int,SCOPE_IDENTITY());
INSERT dbo.OrderDetails(OrderID,ProductID,UnitPrice,Quantity,Discount)
VALUES(@OrderID,11,14,2,0.15),(@OrderID,42,9.8,3,0.25);
COMMIT TRANSACTION;
SELECT @SupplierID SupplierID,@OrderID OrderID,@CategoryID CategoryID;
'@
    $supplierId = [int]$fixture.Tables[0].Rows[0].SupplierID
    $orderId = [int]$fixture.Tables[0].Rows[0].OrderID
    $categoryId = [int]$fixture.Tables[0].Rows[0].CategoryID
    Invoke-Load
    $first = Invoke-Sql $warehouse @"
SELECT f.SalesKey,f.GeographyKey,f.SupplierKey,f.Freight,f.Quantity,f.Discount,p.ProductID,
       c.CustomerKey,e.EmployeeKey,p.CategoryDescription,s.HomePage
FROM dbo.FactSales f JOIN dbo.DimCustomer c ON c.CustomerKey=f.CustomerKey
JOIN dbo.DimEmployee e ON e.EmployeeKey=f.EmployeeKey
JOIN dbo.DimProduct p ON p.ProductKey=f.ProductKey
JOIN dbo.DimSupplier s ON s.SupplierKey=f.SupplierKey
WHERE f.OrderID=$orderId ORDER BY f.ProductKey;
IF (SELECT COUNT(*) FROM dbo.FactSales WHERE OrderID=$orderId)<>2
 OR (SELECT COUNT(DISTINCT GeographyKey) FROM dbo.FactSales WHERE OrderID=$orderId)<>1
 OR EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID=$orderId AND Freight<>30.1234)
 OR (SELECT COUNT(DISTINCT SupplierKey) FROM dbo.FactSales WHERE OrderID=$orderId)<>2
 OR (SELECT LEN(HomePage) FROM dbo.DimSupplier WHERE SupplierID=$supplierId)<>6000
 OR (SELECT LEN(CategoryDescription) FROM dbo.DimProduct WHERE ProductID=11)<>5000
    THROW 52557,'SSIS perdió flete, destino, proveedor o textos MAX.',1;
"@
    if ($first.Tables[0].Rows.Count -ne 2) { throw 'El pedido de prueba no generó dos líneas.' }
    $line11 = @($first.Tables[0].Rows | Where-Object { [int]$_.ProductID -eq 11 })[0]
    $oldSalesKey = [long]$line11.SalesKey
    $oldCustomerKey = [int]$line11.CustomerKey
    $oldEmployeeKey = [int]$line11.EmployeeKey
    $oldGeographyKey = [int]$line11.GeographyKey

    [void](Invoke-Sql $source @"
SET XACT_ABORT ON;BEGIN TRANSACTION;
UPDATE dbo.Customers SET City=N'Oruro' WHERE CustomerID=N'TSSIS';
UPDATE dbo.Employees SET Title=N'Gerente SSIS' WHERE EmployeeID=1;
UPDATE dbo.Suppliers SET HomePage=REPLICATE(CONVERT(nvarchar(max),N'P'),6500) WHERE SupplierID=$supplierId;
UPDATE dbo.Shippers SET Phone=N'555-SSIS-2' WHERE ShipperID=1;
UPDATE dbo.Products SET SupplierID=1 WHERE ProductID=11;
UPDATE dbo.Categories SET [Description]=REPLICATE(CONVERT(nvarchar(max),N'D'),5200) WHERE CategoryID=$categoryId;
UPDATE dbo.Orders SET Freight=31.4321,ShipAddress=N'Nueva dirección SSIS',ShipCity=N'Tarija',ShipRegion=N'Este',ShipPostalCode=N'2000',ShipCountry=N'Bolivia',ShippedDate='20000105' WHERE OrderID=$orderId;
UPDATE dbo.OrderDetails SET Quantity=5,Discount=0.333333 WHERE OrderID=$orderId AND ProductID=11;
COMMIT TRANSACTION;
"@)
    Invoke-Load
    [void](Invoke-Sql $warehouse @"
IF (SELECT COUNT(*) FROM dbo.FactSales WHERE OrderID=$orderId)<>2
 OR EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID=$orderId AND Freight<>31.4321)
 OR (SELECT COUNT(DISTINCT GeographyKey) FROM dbo.FactSales WHERE OrderID=$orderId)<>1
 OR (SELECT GeographyKey FROM dbo.FactSales WHERE OrderID=$orderId AND ProductKey=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11))=$oldGeographyKey
 OR (SELECT SupplierID FROM dbo.DimSupplier WHERE SupplierKey=(SELECT SupplierKey FROM dbo.FactSales WHERE OrderID=$orderId AND ProductKey=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11)))<>1
 OR (SELECT LEN(HomePage) FROM dbo.DimSupplier WHERE SupplierID=$supplierId)<>6500
 OR (SELECT LEN(CategoryDescription) FROM dbo.DimProduct WHERE ProductID=11)<>5200
 OR (SELECT City FROM dbo.DimCustomer WHERE CustomerID=N'TSSIS')<>N'Oruro'
 OR (SELECT Title FROM dbo.DimEmployee WHERE EmployeeID=1)<>N'Gerente SSIS'
 OR (SELECT Phone FROM dbo.DimShipper WHERE ShipperID=1)<>N'555-SSIS-2'
 OR (SELECT SalesKey FROM dbo.FactSales WHERE OrderID=$orderId AND ProductKey=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11))<>$oldSalesKey
 OR (SELECT CustomerKey FROM dbo.DimCustomer WHERE CustomerID=N'TSSIS')<>$oldCustomerKey
 OR (SELECT EmployeeKey FROM dbo.DimEmployee WHERE EmployeeID=1)<>$oldEmployeeKey
    THROW 52558,'El cambio incremental perdió atributos, claves estables o datos de venta.',1;
"@)
    $reconciliation = Get-Reconciliation
    $beforeFailure = Get-State -IncludeLoadTimes
    [void](Invoke-Sql $source "UPDATE dbo.Customers SET City=N'Fallo SSIS' WHERE CustomerID=N'TSSIS';")
    [void](Invoke-Sql $warehouse @'
IF DB_NAME() NOT LIKE N'Northwind[_]DW[_]SSIS[_]%[_]Test' OR OBJECT_ID(N'dbo.NorthwindSsisFailMark',N'TR') IS NOT NULL
    THROW 52559,'La inyección solo admite este DW temporal y sin trigger previo.',1;
'@)
    [void](Invoke-Sql $warehouse @'
CREATE TRIGGER dbo.NorthwindSsisFailMark ON dbo.PackageConfig AFTER UPDATE AS
BEGIN
    IF EXISTS(SELECT 1 FROM inserted WHERE PackageName=N'Cliente')
        THROW 52560,'Fallo SSIS inyectado al confirmar el control Cliente.',1;
END;
'@)
    $triggerCreated = $true
    $rejected = $false
    try { Invoke-Load }
    catch { $rejected = $true }
    if (-not $rejected -or (Get-State -IncludeLoadTimes) -cne $beforeFailure) {
        throw 'El fallo de control confirmó datos o marcas parciales.'
    }
    [void](Invoke-Sql $warehouse 'DROP TRIGGER dbo.NorthwindSsisFailMark;')
    $triggerCreated = $false
    Invoke-Load
    $finalReconciliation = Get-Reconciliation
    $final = Get-State
    $logs = (Get-ChildItem -LiteralPath $runEvidence -Filter 'Northwind.ETL-*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    foreach ($package in @('CargarNorthwind','Cliente','Empleado','Proveedor','Producto','Transportista','Ventas')) {
        if ($logs -notmatch [regex]::Escape($package)) { throw "No aparece el paquete $package en los registros SSIS." }
    }
    if ($logs -notmatch 'OnError' -or $logs -notmatch 'PackageEnd') { throw 'Los registros SSIS no muestran error y cierre de paquete.' }

    $report = [ordered]@{
        Result = 'PASS'; RunId = $id; Source = $source; Warehouse = $warehouse
        InitialLines = [long]$baseline.Warehouse.Lines; InitialOrders = [long]$baseline.Warehouse.Orders
        InitialUnits = [long]$baseline.Warehouse.Units; FinalLines = [long]$finalReconciliation.Warehouse.Lines
        FinalOrders = [long]$finalReconciliation.Warehouse.Orders; FinalUnits = [long]$finalReconciliation.Warehouse.Units
        Freight = [decimal]$finalReconciliation.Warehouse.Freight; Controls = 6
        Packages = @('CargarNorthwind','Cliente','Empleado','Proveedor','Producto','Transportista','Ventas')
        Checks = @('carga y repetición','seis paquetes individuales','flete y destino','proveedor actual','textos NVARCHAR(MAX)','fallo y reintento transaccional','reconciliación OLTP/DW')
        EvidenceDirectory = $runEvidence
    }
}
catch {
    $testError = $_.Exception.Message
    $report.TestError = $testError
}
finally {
    if ($triggerCreated -and $warehouseCreated) {
        try { [void](Invoke-Sql $warehouse 'DROP TRIGGER IF EXISTS dbo.NorthwindSsisFailMark;') }
        catch { $cleanupError = $_.Exception.Message }
    }
    foreach ($entry in @(@{ Name = $warehouse; Created = $warehouseCreated },@{ Name = $source; Created = $sourceCreated })) {
        if (-not $entry.Created) { continue }
        try {
            [void](Invoke-Sql 'master' @"
IF DB_NAME()<>N'master' OR NOT EXISTS(SELECT 1 FROM [$($entry.Name)].sys.extended_properties
 WHERE class=0 AND name=N'NorthwindSsisTestRun' AND CONVERT(nvarchar(128),value)=N'$id')
    THROW 52561,'La limpieza no reconoce esta copia SSIS.',1;
ALTER DATABASE [$($entry.Name)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$($entry.Name)];
"@)
        }
        catch {
            $message = $_.Exception.Message
            if ($cleanupError) { $cleanupError += " | $message" } else { $cleanupError = $message }
        }
    }
    if ($backupFolder) {
        try {
            if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
                Remove-Item -LiteralPath $backupPath -Force
            }
            if (Test-Path -LiteralPath $backupFolder) {
                Remove-Item -LiteralPath $backupFolder -Force
            }
        }
        catch { $cleanupError = @($cleanupError,$_.Exception.Message) -join ' | ' }
    }
}

$report.CleanupError = $cleanupError
$reportPath = Join-Path $runEvidence 'integration.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
if ($testError -or $cleanupError) { throw "Prueba SSIS: $testError. Limpieza: $cleanupError. Evidencia: $reportPath" }
Write-Output "PASS: SSIS carga seis procesos, conserva el flete y reconcilia dimensiones y ventas. Evidencia: $reportPath"
