-- Batch de fixtures para Invoke-NorthwindTestSql, revertido al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
CREATE TABLE #Products(ProductID int,ProductName nvarchar(40) COLLATE DATABASE_DEFAULT,
    QuantityPerUnit nvarchar(20) COLLATE DATABASE_DEFAULT,CategoryID int,
    CategoryName nvarchar(15) COLLATE DATABASE_DEFAULT,
    CategoryDescription nvarchar(max) COLLATE DATABASE_DEFAULT,SupplierID int,
    UnitsInStock smallint,UnitsOnOrder smallint,ReorderLevel smallint,Discontinued bit,
    ProductRowVersion binary(8),CategoryRowVersion binary(8));
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
INSERT #Products EXEC dbo.GetProductChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Products)<>77
    OR EXISTS(SELECT ProductID FROM #Products GROUP BY ProductID HAVING COUNT(*)<>1)
    THROW 51401,'La referencia no devuelve 77 productos unicos.',1;
IF NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=1 AND SupplierID=1
    AND CategoryName=N'Beverages'
    AND CategoryDescription=N'Soft drinks, coffees, teas, beers, and ales')
    THROW 51402,'Atributos de categoria/proveedor incorrectos.',1;
IF EXISTS(SELECT 1 FROM #Products p JOIN dbo.Products s ON s.ProductID=p.ProductID
    WHERE ISNULL(p.UnitsInStock,-1)<>ISNULL(s.UnitsInStock,-1)
       OR ISNULL(p.UnitsOnOrder,-1)<>ISNULL(s.UnitsOnOrder,-1)
       OR ISNULL(p.ReorderLevel,-1)<>ISNULL(s.ReorderLevel,-1))
    THROW 51402,'Atributos de inventario actual difieren del origen.',1;
SELECT N'Referencia: 77 productos unicos y contrato std.Producto compatible' AS Passed;

SELECT ProductID,CategoryID,SupplierID INTO #OriginalRelations FROM dbo.Products WHERE ProductID IN(1,2,3);
UPDATE dbo.Products SET SupplierID=NULL WHERE ProductID=1;
UPDATE dbo.Products SET CategoryID=NULL WHERE ProductID=2;
UPDATE dbo.Products SET CategoryID=NULL,SupplierID=NULL WHERE ProductID=3;
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion 0,9223372036854775807;
IF (SELECT COUNT(*) FROM #Products)<>77
    OR NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=1 AND SupplierID IS NULL)
    OR NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=2 AND CategoryID IS NULL
        AND CategoryName IS NULL AND CategoryRowVersion IS NULL)
    OR NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=3 AND CategoryID IS NULL AND SupplierID IS NULL)
    THROW 51403,'Relacion opcional excluyo productos o invento atributos.',1;
UPDATE p SET p.CategoryID=o.CategoryID,p.SupplierID=o.SupplierID
    FROM dbo.Products p JOIN #OriginalRelations o ON o.ProductID=p.ProductID;
SELECT N'Productos sin proveedor, sin categoria y sin ambos conservados' AS Passed;

SELECT ProductID,CONVERT(binary(8),[rowversion]) AS OriginalVersion INTO #ProductVersions FROM dbo.Products;
DECLARE @before bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Categories SET CategoryName=N'Categoria Test',
    [Description]=REPLICATE(CONVERT(nvarchar(max),N'D'),1500) WHERE CategoryID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @before,@end;
IF EXISTS(SELECT ProductID FROM dbo.Products WHERE CategoryID=1 EXCEPT SELECT ProductID FROM #Products)
    OR EXISTS(SELECT ProductID FROM #Products EXCEPT SELECT ProductID FROM dbo.Products WHERE CategoryID=1)
    OR EXISTS(SELECT 1 FROM #Products WHERE CategoryName<>N'Categoria Test'
        OR LEN(CategoryDescription)<>1500)
    OR EXISTS(SELECT 1 FROM #Products p JOIN #ProductVersions v ON v.ProductID=p.ProductID
        WHERE p.ProductRowVersion<>v.OriginalVersion)
    THROW 51404,'Cambio de categoria no selecciono exactamente sus productos.',1;
SELECT N'Categoria modificada: todos sus productos con marca propia intacta' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET SupplierID=2 WHERE ProductID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Products)<>1
    OR NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=1 AND SupplierID=2)
    THROW 51405,'Cambio de SupplierID no selecciono el producto.',1;
SELECT N'Reasignar SupplierID selecciona el producto sin multiplicar entidades' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET ProductName=N'Producto dentro corte' WHERE ProductID=1;
DECLARE @oldCut bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Categories SET CategoryName=N'Categoria tarde' WHERE CategoryID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Products) THROW 51406,'Categoria posterior se mezclo con el corte antiguo.',1;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @oldCut,@end;
IF NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=1 AND ProductName=N'Producto dentro corte'
    AND CategoryName=N'Categoria tarde' AND CONVERT(bigint,ProductRowVersion)<=@oldCut)
    THROW 51407,'Producto diferido por categoria no reaparecio.',1;
SELECT N'Categoria posterior al corte difiere la fila y la recupera despues' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Suppliers SET CompanyName=N'Proveedor descriptivo test' WHERE SupplierID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @before,@end;
IF EXISTS(SELECT 1 FROM #Products)
    THROW 51408,'Un cambio descriptivo del proveedor seleccionó productos.',1;
SELECT N'Cambios descriptivos de proveedor se extraen independientemente del producto' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET QuantityPerUnit=N'Unidad dentro corte' WHERE ProductID=1;
SET @oldCut=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET ProductName=N'Producto posterior corte' WHERE ProductID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Products) THROW 51408,'Un producto posterior al corte se mezcló con el corte antiguo.',1;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @oldCut,@end;
IF NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=1 AND QuantityPerUnit=N'Unidad dentro corte'
    AND ProductName=N'Producto posterior corte' AND CONVERT(bigint,ProductRowVersion)>@oldCut)
    THROW 51409,'Producto diferido no reapareció con sus atributos actuales.',1;
SELECT N'Producto posterior al corte se recupera en el intervalo siguiente' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Categories SET CategoryName=N'Categoria corte' WHERE CategoryID=1;
SET @oldCut=CONVERT(bigint,@@DBTS);
UPDATE dbo.Products SET ProductName=N'Producto posterior' WHERE ProductID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Products WHERE ProductID=1) THROW 51410,'Producto posterior al corte no se difirio.',1;
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @oldCut,@end;
IF (SELECT COUNT(*) FROM #Products)<>1 OR NOT EXISTS(SELECT 1 FROM #Products WHERE ProductID=1
    AND ProductName=N'Producto posterior' AND CategoryName=N'Categoria corte')
    THROW 51411,'Cambio propio posterior no reaparecio exactamente una vez.',1;
TRUNCATE TABLE #Products;
INSERT #Products EXEC dbo.GetProductChangesByRowVersion @end,@end;
IF EXISTS(SELECT 1 FROM #Products) THROW 51412,'Intervalo vacio devolvio productos.',1;
BEGIN TRY
    EXEC dbo.GetProductChangesByRowVersion -1,@end;
    THROW 51413,'Intervalo negativo aceptado.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetProductChangesByRowVersion @end,0;
    THROW 51413,'Intervalo invertido aceptado.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetProductChangesByRowVersion NULL,@end;
    THROW 51413,'Intervalo NULL aceptado.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
SELECT N'Producto propio posterior recuperado; intervalos invalido/vacio correctos' AS Passed;
