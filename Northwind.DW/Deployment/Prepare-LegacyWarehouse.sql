SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'Northwind_DW' AND NOT EXISTS
 (SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
  AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
    THROW 52010,'Migracion rechazada: use Northwind_DW o una copia de prueba identificada.',1;
BEGIN TRY
    BEGIN TRANSACTION;
    IF EXISTS(SELECT CustomerID FROM dbo.Dim_Cliente GROUP BY CustomerID HAVING COUNT(*)>1)
       OR EXISTS(SELECT EmployeeID FROM dbo.Dim_Empleado GROUP BY EmployeeID HAVING COUNT(*)>1)
       OR EXISTS(SELECT ProductID FROM dbo.Dim_Producto GROUP BY ProductID HAVING COUNT(*)>1)
       OR EXISTS(SELECT ShipperID FROM dbo.Dim_Transportista GROUP BY ShipperID HAVING COUNT(*)>1)
       OR EXISTS(SELECT Fecha FROM dbo.Dim_Tiempo GROUP BY Fecha HAVING COUNT(*)>1)
        THROW 52011,'Migracion detenida: hay identidades comerciales o fechas duplicadas.',1;
    IF EXISTS(SELECT 1 FROM dbo.Dim_Cliente WHERE (Cliente_SK=0 AND CustomerID<>N'~UNK~') OR (CustomerID=N'~UNK~' AND Cliente_SK<>0))
       OR EXISTS(SELECT 1 FROM dbo.Dim_Empleado WHERE (Empleado_SK=0 AND EmployeeID<>0) OR (EmployeeID=0 AND Empleado_SK<>0))
       OR EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE (Tiempo_SK=0 AND Fecha<>'19000101') OR (Fecha='19000101' AND Tiempo_SK<>0))
        THROW 52012,'Migracion detenida: colision con miembro desconocido reservado.',1;
    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas f LEFT JOIN dbo.Dim_Producto p ON p.Producto_SK=f.Producto_SK WHERE p.ProductID IS NULL)
       OR EXISTS(SELECT f.OrderID,p.ProductID FROM dbo.Fact_Ventas f JOIN dbo.Dim_Producto p ON p.Producto_SK=f.Producto_SK
                 GROUP BY f.OrderID,p.ProductID HAVING COUNT(*)>1)
        THROW 52013,'Migracion ambigua: no se puede derivar una identidad unica OrderID/ProductID.',1;
    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas WHERE Cantidad<=0 OR PrecioUnitario<0 OR Descuento<0 OR Descuento>1)
        THROW 52014,'Migracion detenida: cantidad, precio o descuento invalido.',1;
    IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas f
        CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(CONVERT(decimal(5,0),Cantidad)*CONVERT(decimal(19,4),PrecioUnitario),2)))) b(Bruto)
        CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(b.Bruto*CONVERT(decimal(9,6),Descuento),2)))) d(DescuentoImporte)
        WHERE f.ImporteBruto<>b.Bruto OR f.ImporteDescuento<>d.DescuentoImporte OR f.ImporteNeto<>b.Bruto-d.DescuentoImporte)
        THROW 52015,'Migracion detenida: importes existentes no siguen la regla monetaria.',1;
    IF COL_LENGTH('dbo.Fact_Ventas','ProductID') IS NULL
        EXEC(N'ALTER TABLE dbo.Fact_Ventas ADD ProductID int NULL;');
    EXEC(N'UPDATE f SET ProductID=p.ProductID FROM dbo.Fact_Ventas f JOIN dbo.Dim_Producto p ON p.Producto_SK=f.Producto_SK WHERE f.ProductID IS NULL;
           IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas f LEFT JOIN dbo.Dim_Producto p ON p.Producto_SK=f.Producto_SK WHERE f.ProductID IS NULL OR f.ProductID<>p.ProductID)
              THROW 52016,''ProductID existente no coincide con dimension; migracion detenida.'',1;');
    -- Conversion explicita ya comprobada; SqlPackage conserva su bloqueo de perdida.
    IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.Fact_Ventas') AND name=N'ProductID' AND is_nullable=1)
        ALTER TABLE dbo.Fact_Ventas ALTER COLUMN ProductID int NOT NULL;
    IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.Fact_Ventas') AND name=N'PrecioUnitario' AND (system_type_id<>106 OR precision<>19 OR scale<>4))
        ALTER TABLE dbo.Fact_Ventas ALTER COLUMN PrecioUnitario decimal(19,4) NOT NULL;
    IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.Fact_Ventas') AND name=N'Descuento' AND (system_type_id<>106 OR precision<>9 OR scale<>6))
        ALTER TABLE dbo.Fact_Ventas ALTER COLUMN Descuento decimal(9,6) NOT NULL;
    IF EXISTS(SELECT 1 FROM std.Ventas WHERE UnitPrice<0 OR Quantity<=0 OR Discount<0 OR Discount>1)
        THROW 52018,'Staging contiene valores invalidos; migracion detenida.',1;
    IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'std.Ventas') AND name=N'UnitPrice' AND (system_type_id<>106 OR precision<>19 OR scale<>4))
        ALTER TABLE std.Ventas ALTER COLUMN UnitPrice decimal(19,4) NOT NULL;
    IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'std.Ventas') AND name=N'Discount' AND (system_type_id<>106 OR precision<>9 OR scale<>6))
        ALTER TABLE std.Ventas ALTER COLUMN Discount decimal(9,6) NOT NULL;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
