[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force

$publish=Join-Path $PSScriptRoot '../scripts/Publish-NorthwindWarehouse.ps1'
$load=Join-Path $PSScriptRoot '../scripts/Load-NorthwindWarehouse.ps1'
function Read-PublishedState {
    $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
SELECT MigrationName,SchemaVersion,Stage,SourceDatabase,SourceCut,UpdatedAt
FROM dbo.WarehouseMigrationState ORDER BY MigrationName;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad FROM dbo.PackageConfig ORDER BY PackageName;
SELECT (SELECT COUNT_BIG(*) FROM dbo.FactSales) FactSales,
       (SELECT COUNT_BIG(*) FROM dbo.DimCustomer) DimCustomer,
       (SELECT COUNT_BIG(*) FROM dbo.DimEmployee) DimEmployee,
       (SELECT COUNT_BIG(*) FROM dbo.DimProduct) DimProduct,
       (SELECT COUNT_BIG(*) FROM dbo.DimShipper) DimShipper,
       (SELECT COUNT_BIG(*) FROM dbo.DimSupplier) DimSupplier,
       (SELECT COUNT_BIG(*) FROM dbo.DimGeography) DimGeography,
       (SELECT COUNT_BIG(*) FROM dbo.DimDate) DimDate;
'@
    return $state.GetXml()
}
& $publish -Server $Server | Out-Null
& $load -Server $Server | Out-Null

$seed=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Northwind.DW/Deployment/Seed.sql') -Raw
Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql $seed -Commit | Out-Null
Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql $seed -Commit | Out-Null

$metadata=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
DECLARE @tables int=(SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID(N'dbo')
 AND name IN(N'DimDate',N'DimProduct',N'DimCustomer',N'DimEmployee',N'DimShipper',N'DimSupplier',N'DimGeography',N'FactSales'));
DECLARE @foreignKeys int=(SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.FactSales'));
DECLARE @factIndexes int=(SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.FactSales')
 AND name LIKE N'IX_FactSales[_]%');
IF DB_NAME()<>N'Northwind_DW_Test' OR @tables<>8 OR @foreignKeys<>9 OR @factIndexes<>9
 THROW 52310,'El esquema DW no tiene ocho tablas, nueve FK o sus índices.',1;
IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.FactSales')
 AND name=N'FreightAmount')
 THROW 52311,'FactSales no debe contener FreightAmount.',1;
IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.FactSales')
 AND name IN(N'GrossAmount',N'DiscountAmount',N'NetAmount')
 AND (system_type_id<>106 OR precision<>19 OR scale<>2))
 THROW 52312,'Los importes deben ser DECIMAL(19,2).',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimDate WHERE DateKey=0 AND IsUnknown=1 AND FullDate='19000101')
 OR NOT EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerKey=0 AND CustomerID=N'~UNK~')
 OR NOT EXISTS(SELECT 1 FROM dbo.DimEmployee WHERE EmployeeKey=0 AND EmployeeID=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.DimShipper WHERE ShipperKey=0 AND ShipperID=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.DimSupplier WHERE SupplierKey=0 AND SupplierID=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey=0
    AND ShipAddress IS NULL AND ShipCity IS NULL AND ShipRegion IS NULL
    AND ShipPostalCode IS NULL AND ShipCountry IS NULL)
 OR EXISTS(SELECT 1 FROM dbo.DimProduct WHERE ProductID=0)
 THROW 52313,'Miembros técnicos ausentes o producto ficticio presente.',1;
IF (SELECT COUNT(*) FROM dbo.PackageConfig WHERE PackageName IN
 (N'Cliente',N'Empleado',N'Producto',N'Transportista',N'Proveedor',N'Ventas'))<>6
 THROW 52314,'Deben existir seis controles de proceso.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID=10248
 GROUP BY OrderID HAVING COUNT(*)=3 AND SUM(CONVERT(int,Quantity))=27
 AND SUM(NetAmount)=440.00)
 THROW 52315,'La migración no conservó el pedido de referencia.',1;
SELECT @tables Tables,@foreignKeys ForeignKeys,@factIndexes FactIndexes,
 (SELECT COUNT_BIG(*) FROM dbo.DimGeography) GeographyRows,
 (SELECT COUNT_BIG(*) FROM dbo.DimSupplier WHERE SupplierKey<>0) Suppliers,
 (SELECT COUNT_BIG(*) FROM dbo.FactSales) SalesRows;
'@
$metadata.Tables | Format-Table -AutoSize
'PASS: ocho tablas finales, nueve relaciones, nueve índices del hecho, seis controles y semillas repetibles'

 $beforeRepublish=Read-PublishedState
 & $publish -Server $Server | Out-Null
 if((Read-PublishedState) -cne $beforeRepublish){
    throw 'La publicación repetida reinició controles, etapas o datos del DW.'
 }
'PASS: republicar conserva filas, cortes, fechas de éxito y etapa de migración'

$rounding=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
IF NOT EXISTS(SELECT 1 FROM dbo.DW_CalculateAmounts(10,20,0.1)
    WHERE GrossAmount=200 AND DiscountAmount=20 AND NetAmount=180)
 OR NOT EXISTS(SELECT 1 FROM dbo.DW_CalculateAmounts(1,0.0050,0)
    WHERE GrossAmount=0.01 AND DiscountAmount=0 AND NetAmount=0.01)
 OR NOT EXISTS(SELECT 1 FROM dbo.DW_CalculateAmounts(1,1,0.005000)
    WHERE GrossAmount=1 AND DiscountAmount=0.01 AND NetAmount=0.99)
    THROW 52320,'La función de importes cambió el redondeo por línea.',1;
'@
'PASS: GrossAmount, DiscountAmount y NetAmount conservan redondeos y totales de referencia'

$calendar=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
SET LANGUAGE us_english;
SET DATEFIRST 7;
DECLARE @before int=(SELECT COUNT(*) FROM dbo.DimDate WHERE IsUnknown=0),
        @maxDate date=(SELECT MAX(FullDate) FROM dbo.DimDate WHERE IsUnknown=0),
        @endDate date;
SET @endDate=DATEADD(DAY,4,@maxDate);
EXEC dbo.DW_LoadDimDate @StartDate=@maxDate,@EndDate=@endDate;
DECLARE @afterFirst int=(SELECT COUNT(*) FROM dbo.DimDate WHERE IsUnknown=0);
EXEC dbo.DW_LoadDimDate @StartDate=@maxDate,@EndDate=@endDate;
DECLARE @afterSecond int=(SELECT COUNT(*) FROM dbo.DimDate WHERE IsUnknown=0);
IF @afterFirst<>@before+4 OR @afterSecond<>@afterFirst
 THROW 52316,'La extensión del calendario no es continua e idempotente.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimDate WHERE FullDate='19960704' AND DayName=N'Jueves'
 AND MonthName=N'Julio' AND IsWeekend=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.DimDate WHERE FullDate='19960706' AND IsWeekend=1)
 OR NOT EXISTS(SELECT 1 FROM dbo.DimDate WHERE FullDate='19960707' AND IsWeekend=1)
 OR NOT EXISTS(SELECT 1 FROM dbo.DimDate WHERE FullDate='19960708' AND IsWeekend=0)
 THROW 52317,'Calendario depende del idioma o del primer día de semana.',1;
IF @afterSecond<>(SELECT DATEDIFF(DAY,MIN(FullDate),MAX(FullDate))+1 FROM dbo.DimDate WHERE IsUnknown=0)
 THROW 52318,'El calendario tiene huecos.',1;
SET LANGUAGE Spanish;
SET DATEFIRST 1;
EXEC dbo.DW_LoadDimDate @StartDate=@maxDate,@EndDate=@endDate;
IF @afterSecond<>(SELECT COUNT(*) FROM dbo.DimDate WHERE IsUnknown=0)
 THROW 52319,'El calendario duplicó fechas al cambiar DATEFIRST/idioma.',1;
'@
$calendar.Tables | Format-Table -AutoSize
'PASS: fechas de pedido, requerida y envío cubiertas; semana desde lunes, nombres estables, fin de semana correcto y extensión repetible'

$comparison=@(Get-NorthwindWarehouseComparison -Server $Server)
$comparison | Format-Table -AutoSize
if($comparison.Where({-not $_.Coincide}).Count){throw 'La conciliación de DW no coincide con origen, proveedores, destinos o fletes.'}
'PASS: conteos, importes, proveedores, destinos y fletes comparados con Northwind_Test'

$warehouse=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
$transaction=$null
try{
    $transaction=$warehouse.BeginTransaction()
    $command=$warehouse.CreateCommand();$command.Transaction=$transaction
    $command.CommandText='UPDATE dbo.FactSales SET Freight=NULL WHERE OrderID=10248 AND ProductKey=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11);'
    [void]$command.ExecuteNonQuery();$command.Dispose()
    $inconsistent=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseConnection $warehouse -WarehouseTransaction $transaction)
    $check=$inconsistent.Where({$_.Comprobacion -eq 'InconsistentFreight'})
    if($check.Count -ne 1 -or [long]$check[0].DW -ne 1){
        throw 'El comparador no detectó mezcla de Freight NULL y valor en el mismo pedido.'
    }
    'PASS: el comparador detecta Freight inconsistente antes de sumarlo por pedido'
}finally{
    if($null -ne $transaction){try{$transaction.Rollback()}catch{};$transaction.Dispose()}
    $warehouse.Dispose()
}
