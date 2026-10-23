[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Create','Remove')][string]$Action)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force
$database='Northwind_DW_Test'
if($Action -eq 'Create'){
$sql=@'
IF EXISTS(SELECT 1 FROM dbo.DimCustomer WHERE CustomerID=N'PBIT1')
 OR EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID BETWEEN 2140000101 AND 2140000105)
 THROW 52901,'El espacio del fixture Power BI ya está ocupado; no se sobrescribe.',1;
DECLARE @p1 int=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=1),
 @p2 int=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=2),
 @p3 int=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=4),
 @s1 int,@s2 int,@e int,@sh int,@g int,@c int;
SELECT TOP(1) @s1=SupplierKey FROM dbo.FactSales WHERE ProductKey=@p1 ORDER BY SalesKey;
SELECT TOP(1) @s2=SupplierKey FROM dbo.FactSales WHERE ProductKey=@p3 ORDER BY SalesKey;
SELECT TOP(1) @e=EmployeeKey,@sh=ShipperKey,@g=GeographyKey FROM dbo.FactSales WHERE OrderID=10248 ORDER BY SalesKey;
IF @p1 IS NULL OR @p2 IS NULL OR @p3 IS NULL OR @s1 IS NULL OR @s2 IS NULL OR @s1=@s2 OR @e IS NULL OR @g IS NULL
 THROW 52902,'No se encontraron productos, proveedores o claves para el fixture.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DimProduct WHERE ProductKey=@p1 AND CategoryName=N'Beverages')
 OR NOT EXISTS(SELECT 1 FROM dbo.DimProduct WHERE ProductKey=@p2 AND CategoryName=N'Beverages')
 OR NOT EXISTS(SELECT 1 FROM dbo.DimProduct WHERE ProductKey=@p3 AND CategoryName=N'Condiments')
 THROW 52903,'Las categorías de referencia cambiaron.',1;
INSERT dbo.DimCustomer(CustomerID,CompanyName) VALUES(N'PBIT1',N'! Power BI pruebas');
SET @c=SCOPE_IDENTITY();
INSERT dbo.FactSales(OrderID,OrderDateKey,RequiredDateKey,ShippedDateKey,ProductKey,CustomerKey,EmployeeKey,ShipperKey,SupplierKey,GeographyKey,Quantity,UnitPrice,Discount,Freight,GrossAmount,DiscountAmount,NetAmount)
VALUES
(2140000101,19960901,19960904,19960904,@p1,@c,@e,@sh,@s1,@g,1,10,0,30.1234,10,0,10),
(2140000101,19960901,19960904,19960904,@p2,@c,@e,@sh,@s1,@g,1,10,0,30.1234,10,0,10),
(2140000101,19960901,19960904,19960904,@p3,@c,@e,@sh,@s2,@g,1,10,0,30.1234,10,0,10),
(2140000102,19960901,19960904,NULL,@p1,@c,@e,@sh,@s1,@g,1,10,0,NULL,10,0,10),
(2140000103,19960901,19960904,19960904,@p2,@c,@e,@sh,@s1,@g,1,10,0,0,10,0,10),
(2140000104,19960901,19960904,19960904,@p1,@c,@e,@sh,@s1,@g,1,100,0,0,100,0,100),
(2140000105,19960901,19960904,19960904,@p3,@c,@e,@sh,@s2,@g,1,130,0,0,130,0,130);
SELECT 'Created' Result,COUNT_BIG(*) FixtureLines FROM dbo.FactSales WHERE CustomerKey=@c;
'@
}else{
$sql=@'
DECLARE @c int=(SELECT CustomerKey FROM dbo.DimCustomer WHERE CustomerID=N'PBIT1' AND CompanyName=N'! Power BI pruebas');
IF EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID BETWEEN 2140000101 AND 2140000105 AND (@c IS NULL OR CustomerKey<>@c))
 THROW 52904,'Las filas reservadas no pertenecen al fixture Power BI.',1;
IF EXISTS(SELECT 1 FROM dbo.FactSales WHERE CustomerKey=@c AND OrderID NOT BETWEEN 2140000101 AND 2140000105)
 THROW 52905,'El cliente de pruebas tiene pedidos ajenos al fixture.',1;
DELETE dbo.FactSales WHERE CustomerKey=@c AND OrderID BETWEEN 2140000101 AND 2140000105;
DELETE dbo.DimCustomer WHERE CustomerKey=@c;
SELECT 'Removed' Result;
'@
}
$result=Invoke-NorthwindTestSql -Database $database -Sql $sql -Commit
$result.Tables[0] | Format-Table -AutoSize
& (Join-Path $PSScriptRoot '../scripts/Process-NorthwindOLAP.ps1') -ModelDatabase NorthwindOLAP_Test -WarehouseDatabase $database -LogDirectory (Join-Path $PSScriptRoot '../docs/evidencias/power-bi/procesamientos-fixture')
