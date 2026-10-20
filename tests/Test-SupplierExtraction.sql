-- Ejecutar mediante Invoke-NorthwindTestSql; el proveedor agregado se revierte.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
CREATE TABLE #Suppliers
(
    SupplierID int, CompanyName nvarchar(40) COLLATE DATABASE_DEFAULT,
    ContactName nvarchar(30) COLLATE DATABASE_DEFAULT,ContactTitle nvarchar(30) COLLATE DATABASE_DEFAULT,
    [Address] nvarchar(60) COLLATE DATABASE_DEFAULT,City nvarchar(15) COLLATE DATABASE_DEFAULT,
    Region nvarchar(15) COLLATE DATABASE_DEFAULT,PostalCode nvarchar(10) COLLATE DATABASE_DEFAULT,
    Country nvarchar(15) COLLATE DATABASE_DEFAULT,Phone nvarchar(24) COLLATE DATABASE_DEFAULT,
    Fax nvarchar(24) COLLATE DATABASE_DEFAULT,HomePage nvarchar(max) COLLATE DATABASE_DEFAULT,
    SourceRowVersion binary(8)
);
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
INSERT #Suppliers EXEC dbo.GetSupplierChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Suppliers)<>(SELECT COUNT(*) FROM dbo.Suppliers)
    OR EXISTS(SELECT SupplierID FROM #Suppliers GROUP BY SupplierID HAVING COUNT(*)<>1)
    THROW 51501,'La extraccion inicial no devuelve una fila por proveedor.',1;
IF EXISTS(SELECT 1 FROM #Suppliers x JOIN dbo.Suppliers s ON s.SupplierID=x.SupplierID
    WHERE x.CompanyName<>s.CompanyName OR ISNULL(x.ContactName,N'')<>ISNULL(s.ContactName,N'')
       OR ISNULL(x.[Address],N'')<>ISNULL(s.[Address],N'')
       OR ISNULL(x.HomePage,N'')<>ISNULL(s.HomePage,N''))
    THROW 51502,'Atributos completos del proveedor difieren del origen.',1;
SELECT N'Extracción inicial: una fila por identidad y datos completos' AS Passed;

IF EXISTS(SELECT 1 FROM dbo.Suppliers WHERE CompanyName=N'RT Supplier No Products')
    THROW 51503,'El fixture de proveedor ya existe; no se reutiliza.',1;
DECLARE @newSupplier table(SupplierID int);
INSERT dbo.Suppliers(CompanyName,ContactName,ContactTitle,HomePage)
OUTPUT inserted.SupplierID INTO @newSupplier
VALUES(N'RT Supplier No Products',NULL,NULL,REPLICATE(CONVERT(nvarchar(max),N'X'),1200));
DECLARE @supplierID int=(SELECT SupplierID FROM @newSupplier);
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Suppliers;
INSERT #Suppliers EXEC dbo.GetSupplierChangesByRowVersion 0,@end;
IF NOT EXISTS(SELECT 1 FROM #Suppliers WHERE SupplierID=@supplierID
    AND ContactName IS NULL AND ContactTitle IS NULL AND LEN(HomePage)=1200)
    OR EXISTS(SELECT 1 FROM dbo.Products WHERE SupplierID=@supplierID)
    THROW 51504,'Un proveedor sin productos, con nulos o texto largo se perdió.',1;
SELECT N'Proveedor sin productos, atributos NULL y HomePage de 1200 caracteres conservados' AS Passed;

DECLARE @before bigint=@end;
UPDATE dbo.Suppliers SET CompanyName=N'RT Supplier Updated',Phone=N'555-0100'
WHERE SupplierID=@supplierID;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Suppliers;
INSERT #Suppliers EXEC dbo.GetSupplierChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Suppliers)<>1
    OR NOT EXISTS(SELECT 1 FROM #Suppliers WHERE SupplierID=@supplierID
        AND CompanyName=N'RT Supplier Updated' AND Phone=N'555-0100')
    THROW 51505,'Un cambio descriptivo no seleccionó exactamente al proveedor.',1;
TRUNCATE TABLE #Suppliers;
INSERT #Suppliers EXEC dbo.GetSupplierChangesByRowVersion @end,@end;
IF EXISTS(SELECT 1 FROM #Suppliers) THROW 51506,'El intervalo vacío devolvió proveedores.',1;
BEGIN TRY
    EXEC dbo.GetSupplierChangesByRowVersion -1,@end;
    THROW 51507,'Se aceptó un intervalo negativo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
SELECT N'Actualización, límite superior, intervalo vacío e inválido comprobados' AS Passed;
