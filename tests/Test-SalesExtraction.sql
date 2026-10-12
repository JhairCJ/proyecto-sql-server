-- Ejecutar mediante Invoke-NorthwindTestSql; rollback automatico al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
CREATE TABLE #Sales(OrderID int,ProductID int,CustomerID nchar(5) COLLATE DATABASE_DEFAULT,EmployeeID int,ShipperID int,
    OrderDate datetime,RequiredDate datetime,ShippedDate datetime,UnitPrice money,
    Quantity smallint,Discount real,OrderRowVersion binary(8),OrderDetailRowVersion binary(8));
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Sales)<>2155 OR (SELECT COUNT(DISTINCT OrderID) FROM #Sales)<>830
    OR (SELECT SUM(CONVERT(bigint,Quantity)) FROM #Sales)<>51317
    OR EXISTS(SELECT OrderID,ProductID FROM #Sales GROUP BY OrderID,ProductID HAVING COUNT(*)<>1)
    THROW 51601,'Granularidad o referencia de ventas incorrecta.',1;
-- Comparacion independiente de todas las columnas en ambos sentidos.
SELECT o.OrderID,d.ProductID,o.CustomerID,o.EmployeeID,o.ShipVia AS ShipperID,
    o.OrderDate,o.RequiredDate,o.ShippedDate,d.UnitPrice,d.Quantity,d.Discount,
    CONVERT(binary(8),o.rowversion) AS OrderRowVersion,
    CONVERT(binary(8),d.rowversion) AS OrderDetailRowVersion INTO #Expected
FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.OrderID=o.OrderID;
IF EXISTS(SELECT * FROM #Expected EXCEPT SELECT * FROM #Sales)
    OR EXISTS(SELECT * FROM #Sales EXCEPT SELECT * FROM #Expected)
    THROW 51602,'Atributos de ventas diferentes del origen.',1;
IF (SELECT COUNT(*) FROM #Sales WHERE OrderID=10248)<>3
    OR EXISTS(SELECT ProductID FROM #Sales WHERE OrderID=10248 EXCEPT SELECT id FROM (VALUES(11),(42),(72)) v(id))
    OR (SELECT SUM(Quantity) FROM #Sales WHERE OrderID=10248)<>27
    OR (SELECT SUM(CONVERT(decimal(19,4),UnitPrice)*Quantity) FROM #Sales WHERE OrderID=10248)<>440
    THROW 51603,'Pedido 10248 incorrecto.',1;
SELECT N'2155 lineas, 830 pedidos, 51317 unidades; pedido 10248 con 11/42/72, 27 unidades y bruto 440' AS Passed;

DECLARE @before bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET UnitPrice=UnitPrice+100 WHERE ProductID IN(11,42,72);
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF EXISTS(SELECT 1 FROM #Sales) THROW 51604,'Catalogo selecciona ventas historicas.',1;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion 0,@end;
IF EXISTS(SELECT OrderID,ProductID,UnitPrice FROM #Sales WHERE OrderID=10248
    EXCEPT SELECT OrderID,ProductID,UnitPrice FROM #Expected WHERE OrderID=10248)
    THROW 51605,'Precio vendido cambiado por catalogo.',1;
SELECT N'Precio de catalogo cambiado: no selecciona ventas ni altera el precio vendido' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET ShippedDate='19960801',RequiredDate='19960815',CustomerID=N'VINET',
    EmployeeID=1,ShipVia=1 WHERE OrderID=10248;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Sales)<>3 OR EXISTS(SELECT 1 FROM #Sales WHERE OrderID<>10248
    OR ShippedDate<>'19960801' OR RequiredDate<>'19960815' OR CustomerID<>N'VINET' OR EmployeeID<>1 OR ShipperID<>1)
    OR EXISTS(SELECT ProductID FROM #Sales EXCEPT SELECT ProductID FROM #Expected WHERE OrderID=10248)
    THROW 51606,'Cambio de cabecera no propaga todas sus lineas.',1;
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @end,9223372036854775807;
IF EXISTS(SELECT 1 FROM #Sales) THROW 51607,'Cabecera en limite inferior seleccionada.',1;
SELECT N'Cabecera: fechas e identidades actualizan las tres lineas; inferior excluido' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.OrderDetails SET UnitPrice=20,Quantity=10,Discount=0.1 WHERE OrderID=10248 AND ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Sales)<>1 OR NOT EXISTS(SELECT 1 FROM #Sales WHERE OrderID=10248 AND ProductID=11
    AND UnitPrice=20 AND Quantity=10 AND CONVERT(decimal(9,6),Discount)=0.1
    AND OrderDetailRowVersion=CONVERT(binary(8),@end))
    THROW 51608,'Detalle no selecciona exactamente su linea.',1;
SELECT N'Detalle: una linea con precio, cantidad y descuento vendidos; superior incluido' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.OrderDetails SET Quantity=11 WHERE OrderID=10248 AND ProductID=11;
DECLARE @oldCut bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET ShippedDate='19960802' WHERE OrderID=10248;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Sales) THROW 51609,'Cabecera posterior al corte mezclada con detalle anterior.',1;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @oldCut,@end;
IF (SELECT COUNT(*) FROM #Sales)<>3 OR NOT EXISTS(SELECT 1 FROM #Sales WHERE ProductID=11 AND Quantity=11
    AND ShippedDate='19960802' AND OrderDetailRowVersion<=CONVERT(binary(8),@oldCut))
    THROW 51610,'Cabecera posterior no recupera linea diferida.',1;
SELECT N'Cabecera posterior difiere detalle anterior y siguiente intervalo recupera las tres lineas' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET RequiredDate='19960816' WHERE OrderID=10248;
SET @oldCut=CONVERT(bigint,@@DBTS);
UPDATE dbo.OrderDetails SET Quantity=12 WHERE OrderID=10248 AND ProductID=11;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@oldCut;
IF (SELECT COUNT(*) FROM #Sales)<>2 OR EXISTS(SELECT 1 FROM #Sales WHERE OrderID<>10248 OR ProductID=11)
    THROW 51611,'Detalle posterior no se difiere individualmente.',1;
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @oldCut,@end;
IF (SELECT COUNT(*) FROM #Sales)<>1 OR NOT EXISTS(SELECT 1 FROM #Sales WHERE ProductID=11 AND Quantity=12
    AND RequiredDate='19960816' AND OrderRowVersion<=CONVERT(binary(8),@oldCut))
    THROW 51612,'Detalle posterior perdido.',1;
SELECT N'Detalle posterior difiere solo su linea y siguiente intervalo la recupera' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Orders SET CustomerID=NULL,EmployeeID=NULL,ShipVia=NULL,OrderDate=NULL,
    RequiredDate=NULL,ShippedDate=NULL WHERE OrderID=10248;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Sales)<>3 OR EXISTS(SELECT 1 FROM #Sales WHERE OrderID<>10248 OR CustomerID IS NOT NULL
    OR EmployeeID IS NOT NULL OR ShipperID IS NOT NULL OR OrderDate IS NOT NULL
    OR RequiredDate IS NOT NULL OR ShippedDate IS NOT NULL)
    THROW 51613,'Ausencias legitimas excluyen lineas o inventan valores.',1;
SELECT N'Cliente, empleado, transportista y fechas NULL conservan todas las lineas' AS Passed;

TRUNCATE TABLE #Sales;
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @end,@end;
IF EXISTS(SELECT 1 FROM #Sales) THROW 51614,'Intervalo vacio devuelve filas.',1;
BEGIN TRY
    EXEC dbo.GetSalesChangesByRowVersion -1,@end;
    THROW 51615,'Se acepto negativo.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51104 THROW;
END CATCH;
BEGIN TRY
    EXEC dbo.GetSalesChangesByRowVersion 2,1;
    THROW 51616,'Se acepto intervalo invertido.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51104 THROW;
END CATCH;
BEGIN TRY
    EXEC dbo.GetSalesChangesByRowVersion 0,NULL;
    THROW 51617,'Se acepto NULL.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51104 THROW;
END CATCH;
SELECT N'Intervalo vacio e intervalos invalidos comprobados' AS Passed;
