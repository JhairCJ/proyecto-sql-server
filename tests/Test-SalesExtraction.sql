-- Ejecutar mediante Invoke-NorthwindTestSql; las modificaciones se revierten.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
CREATE TABLE #Sales
(
    OrderID int, ProductID int, CustomerID nchar(5) COLLATE DATABASE_DEFAULT,
    EmployeeID int, ShipperID int, SupplierID int,
    OrderDate datetime, RequiredDate datetime, ShippedDate datetime,
    UnitPrice decimal(19,4), Quantity smallint, Discount decimal(9,6), Freight decimal(19,4),
    ShipAddress nvarchar(60) COLLATE DATABASE_DEFAULT,
    ShipCity nvarchar(15) COLLATE DATABASE_DEFAULT,ShipRegion nvarchar(15) COLLATE DATABASE_DEFAULT,
    ShipPostalCode nvarchar(10) COLLATE DATABASE_DEFAULT,ShipCountry nvarchar(15) COLLATE DATABASE_DEFAULT,
    OrderRowVersion binary(8), OrderDetailRowVersion binary(8), ProductRowVersion binary(8)
);
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Sales)<>2155 OR (SELECT COUNT(DISTINCT OrderID) FROM #Sales)<>830
    OR (SELECT SUM(CONVERT(bigint,Quantity)) FROM #Sales)<>51317
    OR EXISTS(SELECT OrderID,ProductID FROM #Sales GROUP BY OrderID,ProductID HAVING COUNT(*)<>1)
    THROW 51601,'Granularidad o referencia de ventas incorrecta.',1;

SELECT o.OrderID,d.ProductID,o.CustomerID,o.EmployeeID,o.ShipVia AS ShipperID,p.SupplierID,
    o.OrderDate,o.RequiredDate,o.ShippedDate,CONVERT(decimal(19,4),d.UnitPrice) AS UnitPrice,
    d.Quantity,CONVERT(decimal(9,6),d.Discount) AS Discount,
    CONVERT(decimal(19,4),o.Freight) AS Freight,o.ShipAddress,o.ShipCity,o.ShipRegion,
    o.ShipPostalCode,o.ShipCountry,CONVERT(binary(8),o.rowversion) AS OrderRowVersion,
    CONVERT(binary(8),d.rowversion) AS OrderDetailRowVersion,
    CONVERT(binary(8),p.rowversion) AS ProductRowVersion
INTO #Expected
FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.OrderID=o.OrderID
JOIN dbo.Products p ON p.ProductID=d.ProductID;
IF EXISTS(SELECT * FROM #Expected EXCEPT SELECT * FROM #Sales)
    OR EXISTS(SELECT * FROM #Sales EXCEPT SELECT * FROM #Expected)
    THROW 51602,'Atributos completos de ventas difieren del origen.',1;
IF (SELECT COUNT(*) FROM #Sales WHERE OrderID=10248)<>3
    OR EXISTS(SELECT ProductID FROM #Sales WHERE OrderID=10248
        EXCEPT SELECT id FROM (VALUES(11),(42),(72)) v(id))
    OR (SELECT SUM(Quantity) FROM #Sales WHERE OrderID=10248)<>27
    OR (SELECT SUM(UnitPrice*Quantity) FROM #Sales WHERE OrderID=10248)<>440
    THROW 51603,'Pedido 10248 incorrecto.',1;
SELECT N'2155 líneas, 830 pedidos, 51317 unidades; pedido 10248 conserva 11/42/72 y flete original' AS Passed;

-- Una modificación de producto selecciona todos los pedidos que lo contienen,
-- pero el precio de venta sigue viniendo de OrderDetails.
SELECT DISTINCT OrderID INTO #ProductOrders FROM dbo.OrderDetails WHERE ProductID=11;
DECLARE @before bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET UnitPrice=UnitPrice+100 WHERE ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF EXISTS(SELECT OrderID,ProductID FROM #Expected WHERE OrderID IN(SELECT OrderID FROM #ProductOrders)
          EXCEPT SELECT OrderID,ProductID FROM #Sales)
    OR EXISTS(SELECT OrderID,ProductID FROM #Sales
          EXCEPT SELECT OrderID,ProductID FROM #Expected WHERE OrderID IN(SELECT OrderID FROM #ProductOrders))
    OR EXISTS(SELECT 1 FROM #Sales s JOIN dbo.OrderDetails d
          ON d.OrderID=s.OrderID AND d.ProductID=s.ProductID WHERE s.UnitPrice<>d.UnitPrice)
    THROW 51604,'Cambio de catálogo no devolvió todos los pedidos o alteró el precio vendido.',1;
SELECT N'Un cambio de producto vuelve a seleccionar pedidos completos sin revalorizar las ventas' AS Passed;

DECLARE @oldSupplier int=(SELECT SupplierID FROM dbo.Products WHERE ProductID=11),
        @newSupplier int;
SET @newSupplier=CASE WHEN @oldSupplier=1 THEN 2 ELSE 1 END;
SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET SupplierID=@newSupplier WHERE ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF EXISTS(SELECT OrderID,ProductID FROM #Expected WHERE OrderID IN(SELECT OrderID FROM #ProductOrders)
          EXCEPT SELECT OrderID,ProductID FROM #Sales)
    OR EXISTS(SELECT OrderID,ProductID FROM #Sales
          EXCEPT SELECT OrderID,ProductID FROM #Expected WHERE OrderID IN(SELECT OrderID FROM #ProductOrders))
    OR NOT EXISTS(SELECT 1 FROM #Sales WHERE ProductID=11 AND SupplierID=@newSupplier)
    OR EXISTS(SELECT 1 FROM #Sales s WHERE s.ProductID=11 AND s.UnitPrice<>
          (SELECT d.UnitPrice FROM dbo.OrderDetails d WHERE d.OrderID=s.OrderID AND d.ProductID=11))
    THROW 51605,'Cambio de proveedor del producto no se propagó coherentemente.',1;
SELECT N'La reasignación del proveedor actual se propaga sin cambiar el precio vendido' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET ShippedDate='19960801',RequiredDate='19960815',CustomerID=N'VINET',
    EmployeeID=1,ShipVia=1,Freight=17.1234,ShipAddress=N'Entrega test',ShipCity=N'London',
    ShipRegion=NULL,ShipPostalCode=N'EC1 2AA',ShipCountry=N'UK'
WHERE OrderID=10248;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Sales)<>3
    OR EXISTS(SELECT 1 FROM #Sales WHERE OrderID<>10248 OR ShippedDate<>'19960801'
        OR RequiredDate<>'19960815' OR CustomerID<>N'VINET' OR EmployeeID<>1 OR ShipperID<>1
        OR Freight<>17.1234 OR ShipAddress<>N'Entrega test' OR ShipCity<>N'London'
        OR ShipRegion IS NOT NULL OR ShipPostalCode<>N'EC1 2AA' OR ShipCountry<>N'UK')
    THROW 51606,'Cambio de cabecera no propagó flete, destino y fechas a todas las líneas.',1;
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @end,9223372036854775807;
IF EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248)
    THROW 51607,'El límite inferior inclusivo seleccionó una cabecera sin cambio.',1;
SELECT N'Freight, destino y fechas del encabezado llegan iguales a las tres líneas' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.OrderDetails SET UnitPrice=20,Quantity=10,Discount=0.1
WHERE OrderID=10248 AND ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Sales)<>3
    OR NOT EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248 AND ProductID=11
        AND UnitPrice=20 AND Quantity=10 AND Discount=0.1)
    OR EXISTS(SELECT ProductID FROM #Sales WHERE OrderID=10248
        EXCEPT SELECT id FROM (VALUES(11),(42),(72)) v(id))
    THROW 51608,'Cambio de detalle no devolvió el pedido completo.',1;
SELECT N'Un cambio en una línea vuelve a entregar las tres líneas del pedido' AS Passed;

-- Una dependencia posterior al corte difiere todo el pedido, no solo esa línea.
SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET RequiredDate='19960816' WHERE OrderID=10248;
DECLARE @oldCut bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.OrderDetails SET Quantity=12 WHERE OrderID=10248 AND ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248)
    THROW 51609,'El pedido se entregó parcialmente antes de incluir todos sus detalles.',1;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @oldCut,@end;
IF (SELECT COUNT(*) FROM #Sales WHERE OrderID=10248)<>3
    OR NOT EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248 AND ProductID=11
        AND Quantity=12 AND RequiredDate='19960816')
    THROW 51610,'El pedido diferido no reapareció completo en el siguiente intervalo.',1;
SELECT N'Un detalle posterior al corte difiere y recupera el pedido completo' AS Passed;

-- Una modificación de proveedor posterior también difiere todas las líneas.
SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET ShipCity=N'Ciudad corte' WHERE OrderID=10248;
SET @oldCut=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET SupplierID=@oldSupplier WHERE ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248)
    THROW 51611,'Una dependencia de producto posterior al corte dejó líneas parciales.',1;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @oldCut,@end;
IF (SELECT COUNT(*) FROM #Sales WHERE OrderID=10248)<>3
    OR NOT EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248 AND ProductID=11 AND SupplierID=@oldSupplier)
    THROW 51612,'El pedido diferido por producto no reapareció completo.',1;
SELECT N'Un cambio de producto posterior al corte difiere el pedido completo' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET CustomerID=NULL,EmployeeID=NULL,ShipVia=NULL,OrderDate=NULL,
    RequiredDate=NULL,ShippedDate=NULL,Freight=NULL,ShipAddress=NULL,ShipCity=NULL,
    ShipRegion=NULL,ShipPostalCode=NULL,ShipCountry=NULL WHERE OrderID=10248;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Sales)<>3 OR EXISTS(SELECT 1 FROM #Sales WHERE OrderID<>10248
    OR CustomerID IS NOT NULL OR EmployeeID IS NOT NULL OR ShipperID IS NOT NULL
    OR OrderDate IS NOT NULL OR RequiredDate IS NOT NULL OR ShippedDate IS NOT NULL
    OR Freight IS NOT NULL OR ShipAddress IS NOT NULL OR ShipCity IS NOT NULL
    OR ShipRegion IS NOT NULL OR ShipPostalCode IS NOT NULL OR ShipCountry IS NOT NULL)
    THROW 51613,'Referencias, fechas, flete o destino NULL excluyeron las líneas.',1;
SELECT N'Las ausencias legítimas de encabezado conservan las tres líneas' AS Passed;

TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @end,@end;
IF EXISTS(SELECT 1 FROM #Sales) THROW 51614,'El intervalo vacío devolvió líneas.',1;
BEGIN TRY
    EXEC dbo.GetSalesChangesByRowVersion -1,@end;
    THROW 51615,'Se aceptó un intervalo negativo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetSalesChangesByRowVersion 2,1;
    THROW 51616,'Se aceptó un intervalo invertido.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetSalesChangesByRowVersion 0,NULL;
    THROW 51617,'Se aceptó un intervalo NULL.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
SELECT N'Límites e intervalos inválidos comprobados' AS Passed;
