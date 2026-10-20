SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'Northwind_DW_Test'
    THROW 52500,'Los escenarios requieren la copia DW.',1;

DECLARE @customerKey INT=(SELECT CustomerKey FROM dbo.DimCustomer WHERE CustomerID=N'VINET'),
        @employeeKey INT=(SELECT EmployeeKey FROM dbo.DimEmployee WHERE EmployeeID=1),
        @productKey INT=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11),
        @supplierKey INT=(SELECT SupplierKey FROM dbo.DimSupplier WHERE SupplierID=1),
        @shipperKey INT=(SELECT ShipperKey FROM dbo.DimShipper WHERE ShipperID=1),
        @salesKey BIGINT=(SELECT SalesKey FROM dbo.FactSales WHERE OrderID=10248 AND ProductKey=
            (SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11)),
        @netBefore DECIMAL(19,2),
        @sharedGeography INT;
SELECT @netBefore=SUM(NetAmount) FROM dbo.FactSales WHERE OrderID=10248;

UPDATE std.Cliente SET City=N'Ciudad prueba',Fax=N'Fax prueba' WHERE CustomerID=N'VINET';
EXEC dbo.DW_ApplyPackage N'Cliente',@cut,@cut;
UPDATE std.Empleado SET FullName=N'Empleado actualizado',SupervisorName=N'Supervisor actualizado'
WHERE EmployeeID=1;
EXEC dbo.DW_ApplyPackage N'Empleado',@cut,@cut;
UPDATE std.Proveedor SET CompanyName=N'Proveedor actualizado' WHERE SupplierID=1;
EXEC dbo.DW_ApplyPackage N'Proveedor',@cut,@cut;
UPDATE std.Producto SET CategoryDescription=REPLICATE(N'C',1200),UnitsInStock=UnitsInStock+1
WHERE ProductID=11;
EXEC dbo.DW_ApplyPackage N'Producto',@cut,@cut;
UPDATE std.Transportista SET Phone=N'555-TEST' WHERE ShipperID=1;
EXEC dbo.DW_ApplyPackage N'Transportista',@cut,@cut;
IF (SELECT CustomerKey FROM dbo.DimCustomer WHERE CustomerID=N'VINET')<>@customerKey
 OR (SELECT City FROM dbo.DimCustomer WHERE CustomerID=N'VINET')<>N'Ciudad prueba'
 OR (SELECT EmployeeKey FROM dbo.DimEmployee WHERE EmployeeID=1)<>@employeeKey
 OR (SELECT FullName FROM dbo.DimEmployee WHERE EmployeeID=1)<>N'Empleado actualizado'
 OR (SELECT SupplierKey FROM dbo.DimSupplier WHERE SupplierID=1)<>@supplierKey
 OR (SELECT CompanyName FROM dbo.DimSupplier WHERE SupplierID=1)<>N'Proveedor actualizado'
 OR (SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11)<>@productKey
 OR (SELECT LEN(CategoryDescription) FROM dbo.DimProduct WHERE ProductID=11)<>1200
 OR (SELECT ShipperKey FROM dbo.DimShipper WHERE ShipperID=1)<>@shipperKey
 OR (SELECT Phone FROM dbo.DimShipper WHERE ShipperID=1)<>N'555-TEST'
    THROW 52508,'Un cambio tipo 1 no conservó la clave o los nuevos atributos.',1;
IF COL_LENGTH(N'dbo.DimProduct',N'SupplierID') IS NOT NULL
    THROW 52509,'SupplierID no debe duplicarse dentro de DimProduct.',1;

UPDATE std.Ventas
SET Freight=CONVERT(DECIMAL(19,4),30.1234),
    ShipAddress=NULL,ShipCity=N'Ciudad test',ShipRegion=NULL,
    ShipPostalCode=N'54321',ShipCountry=NULL
WHERE OrderID IN(10248,10249);
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
SELECT @sharedGeography=MAX(GeographyKey) FROM dbo.FactSales WHERE OrderID=10249;
IF (SELECT COUNT(*) FROM dbo.FactSales WHERE OrderID=10248)<>3
 OR EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID=10248 AND Freight<>30.1234)
 OR (SELECT COUNT(DISTINCT GeographyKey) FROM dbo.FactSales WHERE OrderID IN(10248,10249))<>1
 OR (SELECT SUM(NetAmount) FROM dbo.FactSales WHERE OrderID=10248)<>@netBefore
 OR NOT EXISTS(SELECT 1 FROM dbo.DimGeography WHERE GeographyKey=@sharedGeography
    AND ShipAddress IS NULL AND ShipCity=N'Ciudad test'
    AND ShipRegion IS NULL AND ShipPostalCode=N'54321' AND ShipCountry IS NULL)
    THROW 52510,'El flete debe conservar cuatro decimales y el destino parcial debe reutilizarse.',1;

UPDATE std.Ventas SET ShipCity=N'Pedido 10248' WHERE OrderID=10248;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
IF (SELECT COUNT(DISTINCT GeographyKey) FROM dbo.FactSales WHERE OrderID=10248)<>1
 OR (SELECT MAX(GeographyKey) FROM dbo.FactSales WHERE OrderID=10249)<>@sharedGeography
 OR (SELECT ShipCity FROM dbo.DimGeography WHERE GeographyKey=@sharedGeography)<>N'Ciudad test'
 OR (SELECT SUM(NetAmount) FROM dbo.FactSales WHERE OrderID=10248)<>@netBefore
 OR (SELECT SalesKey FROM dbo.FactSales WHERE OrderID=10248 AND ProductKey=@productKey)<>@salesKey
    THROW 52511,'Cambiar un destino alteró otro pedido, su clave o los importes vendidos.',1;

UPDATE std.Ventas SET Freight=NULL WHERE OrderID=10249;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
IF EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID=10249 AND Freight IS NOT NULL)
    THROW 52512,'NULL de flete no se conservó en todas las líneas.',1;
UPDATE std.Ventas SET Freight=CONVERT(DECIMAL(19,4),0) WHERE OrderID=10249;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
IF EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID=10249 AND Freight<>0)
    THROW 52513,'Cero de flete no se conservó en todas las líneas.',1;

DECLARE @oldSupplierID INT=(SELECT SupplierID FROM std.Producto WHERE ProductID=11),
        @newSupplierID INT=(SELECT MIN(SupplierID) FROM dbo.DimSupplier
            WHERE SupplierKey<>0 AND SupplierID<>(SELECT SupplierID FROM std.Producto WHERE ProductID=11)),
        @grossProduct DECIMAL(19,2),@discountProduct DECIMAL(19,2),@netProduct DECIMAL(19,2);
SELECT @grossProduct=SUM(GrossAmount),@discountProduct=SUM(DiscountAmount),@netProduct=SUM(NetAmount)
FROM dbo.FactSales WHERE ProductKey=@productKey;
UPDATE std.Ventas SET SupplierID=@newSupplierID WHERE ProductID=11;
EXEC dbo.DW_ApplyPackage N'Ventas',@cut,@cut;
IF @newSupplierID IS NULL OR @newSupplierID=@oldSupplierID
 OR EXISTS(SELECT 1 FROM dbo.FactSales f JOIN dbo.DimProduct p ON p.ProductKey=f.ProductKey
    JOIN dbo.DimSupplier s ON s.SupplierKey=f.SupplierKey
    WHERE p.ProductID=11 AND s.SupplierID<>@newSupplierID)
 OR EXISTS
    (SELECT 1 FROM dbo.FactSales WHERE ProductKey=@productKey
     GROUP BY ProductKey HAVING SUM(GrossAmount)<>@grossProduct
       OR SUM(DiscountAmount)<>@discountProduct OR SUM(NetAmount)<>@netProduct)
    THROW 52514,'Reasignar proveedor actual cambió medidas o no llegó a todas las ventas.',1;

SELECT N'PASS' AS Result,N'atributos tipo 1, destinos, freight y proveedor actual' AS Scenario;
