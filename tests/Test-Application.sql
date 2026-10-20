SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME()<>N'Northwind_DW_Test' OR @cut<0
    THROW 52500,'La aplicación requiere la copia DW y un corte válido.',1;
IF (SELECT COUNT(*) FROM dbo.PackageConfig WHERE PackageName IN
    (N'Cliente',N'Empleado',N'Proveedor',N'Producto',N'Transportista',N'Ventas'))<>6
    THROW 52502,'Faltan controles de carga.',1;
IF EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE LastRowVersion<>0x0000000000000000)
    THROW 52507,'El fixture debe reiniciar sus controles dentro de la transacción.',1;

DECLARE @packages TABLE(LoadOrder INT IDENTITY(1,1),PackageName NVARCHAR(100));
INSERT @packages(PackageName) VALUES
    (N'Cliente'),(N'Empleado'),(N'Proveedor'),(N'Producto'),(N'Transportista'),(N'Ventas');
DECLARE @package NVARCHAR(100),@start BIGINT=0;
DECLARE packageCursor CURSOR LOCAL FAST_FORWARD FOR SELECT PackageName FROM @packages ORDER BY LoadOrder;
OPEN packageCursor;
FETCH NEXT FROM packageCursor INTO @package;
WHILE @@FETCH_STATUS=0
BEGIN
    EXEC dbo.DW_ApplyPackage @package,@start,@cut;
    FETCH NEXT FROM packageCursor INTO @package;
END;
CLOSE packageCursor;
DEALLOCATE packageCursor;

IF (SELECT COUNT(*) FROM dbo.DimCustomer WHERE CustomerKey<>0)<>91
 OR (SELECT COUNT(*) FROM dbo.DimEmployee WHERE EmployeeKey<>0)<>9
 OR (SELECT COUNT(*) FROM dbo.DimProduct)<>77
 OR (SELECT COUNT(*) FROM dbo.DimShipper WHERE ShipperKey<>0)<>3
 OR (SELECT COUNT(*) FROM dbo.DimSupplier WHERE SupplierKey<>0)<>29
 OR (SELECT COUNT(*) FROM dbo.FactSales)<>2155
 OR (SELECT COUNT(DISTINCT OrderID) FROM dbo.FactSales)<>830
 OR (SELECT SUM(CONVERT(BIGINT,Quantity)) FROM dbo.FactSales)<>51317
    THROW 52501,'Carga inicial no conserva las entidades y líneas de referencia.',1;
IF EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE LastRowVersion<>CONVERT(BINARY(8),@cut)
    OR LastSuccessfulLoad IS NULL)
    THROW 52502,'Los seis controles no avanzaron con la aplicación.',1;

DECLARE @productKey INT=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11),
        @salesKey BIGINT=(SELECT SalesKey FROM dbo.FactSales
            WHERE OrderID=10248 AND ProductKey=(SELECT ProductKey FROM dbo.DimProduct WHERE ProductID=11));
DECLARE repeatedCursor CURSOR LOCAL FAST_FORWARD FOR SELECT PackageName FROM @packages ORDER BY LoadOrder;
OPEN repeatedCursor;
FETCH NEXT FROM repeatedCursor INTO @package;
WHILE @@FETCH_STATUS=0
BEGIN
    EXEC dbo.DW_ApplyPackage @package,@cut,@cut;
    FETCH NEXT FROM repeatedCursor INTO @package;
END;
CLOSE repeatedCursor;
DEALLOCATE repeatedCursor;
IF (SELECT COUNT(*) FROM dbo.FactSales)<>2155
 OR (SELECT SalesKey FROM dbo.FactSales WHERE OrderID=10248 AND ProductKey=@productKey)<>@salesKey
    THROW 52503,'La repetición duplicó hechos o cambió SalesKey.',1;

SELECT N'PASS' AS Result,N'carga inicial y repetición de seis procesos' AS Scenario;
