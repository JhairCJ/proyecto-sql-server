-- Ejecutar con Invoke-NorthwindTestSql: rollback automático de los fixtures.
SET NOCOUNT ON;
-- Solo en este fixture: capturar rechazos esperados sin inutilizar su transacción.
SET XACT_ABORT OFF;
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
CREATE TABLE #Customers(CustomerID nchar(5) COLLATE DATABASE_DEFAULT,
    CompanyName nvarchar(40) COLLATE DATABASE_DEFAULT,ContactName nvarchar(30) COLLATE DATABASE_DEFAULT,
    ContactTitle nvarchar(30) COLLATE DATABASE_DEFAULT,[Address] nvarchar(60) COLLATE DATABASE_DEFAULT,
    City nvarchar(15) COLLATE DATABASE_DEFAULT,Region nvarchar(15) COLLATE DATABASE_DEFAULT,
    PostalCode nvarchar(10) COLLATE DATABASE_DEFAULT,Country nvarchar(15) COLLATE DATABASE_DEFAULT,
    Phone nvarchar(24) COLLATE DATABASE_DEFAULT,Fax nvarchar(24) COLLATE DATABASE_DEFAULT,
    SourceRowVersion binary(8));
INSERT #Customers EXEC dbo.GetCustomerChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Customers)<>91 THROW 51201,'La referencia no devuelve 91 clientes.',1;
IF EXISTS(SELECT CustomerID FROM #Customers GROUP BY CustomerID HAVING COUNT(*)<>1)
    THROW 51202,'Clientes duplicados.',1;
IF EXISTS(SELECT 1 FROM #Customers c JOIN dbo.Customers s ON s.CustomerID=c.CustomerID
    WHERE c.CompanyName<>s.CompanyName OR ISNULL(c.[Address],N'')<>ISNULL(s.[Address],N'')
       OR ISNULL(c.Phone,N'')<>ISNULL(s.Phone,N'') OR ISNULL(c.Fax,N'')<>ISNULL(s.Fax,N''))
    THROW 51202,'Atributos completos del cliente difieren del origen.',1;
SELECT N'Referencia: 91 clientes, una fila por identidad y contrato std.Cliente' AS Passed;

DECLARE @values TABLE(Value bigint);
INSERT @values VALUES(0),(1),(9007199254740993),(9223372036854775807);
DECLARE @value bigint,@binary binary(8),@roundtrip bigint;
DECLARE values_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT Value FROM @values;
OPEN values_cursor;
FETCH NEXT FROM values_cursor INTO @value;
WHILE @@FETCH_STATUS=0
BEGIN
    EXEC dbo.BigIntToRowVersion @value,@binary OUTPUT;
    EXEC dbo.RowVersionToBigInt @binary,@roundtrip OUTPUT;
    IF @roundtrip<>@value THROW 51203,'Se perdio precision en conversion.',1;
    FETCH NEXT FROM values_cursor INTO @value;
END;
CLOSE values_cursor;
DEALLOCATE values_cursor;
BEGIN TRY
    EXEC dbo.RowVersionToBigInt 0x8000000000000000,@roundtrip OUTPUT;
    THROW 51204,'Se acepto binario fuera de Int64.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51101 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.RowVersionToBigInt NULL,@roundtrip OUTPUT;
    THROW 51204,'Se acepto binario NULL.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51101 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.BigIntToRowVersion -1,@binary OUTPUT;
    THROW 51204,'Se acepto Int64 negativo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51102 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.BigIntToRowVersion NULL,@binary OUTPUT;
    THROW 51204,'Se acepto Int64 NULL.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51102 THROW; END CATCH;
SELECT N'Conversiones exactas, >2^53, maximo Int64 y valores invalidos rechazados' AS Passed;

IF EXISTS(SELECT 1 FROM dbo.Customers WHERE CustomerID IN(N'RT001',N'RT002',N'RT003'))
    THROW 51205,'Fixtures previos presentes; no se sobrescriben.',1;
INSERT dbo.Customers(CustomerID,CompanyName) VALUES(N'RT001',N'Inferior');
INSERT dbo.Customers(CustomerID,CompanyName) VALUES(N'RT002',N'Superior');
INSERT dbo.Customers(CustomerID,CompanyName) VALUES(N'RT003',N'Posterior');
DECLARE @low bigint=(SELECT CONVERT(bigint,[rowversion]) FROM dbo.Customers WHERE CustomerID=N'RT001'),
    @high bigint=(SELECT CONVERT(bigint,[rowversion]) FROM dbo.Customers WHERE CustomerID=N'RT002'),
    @later bigint=(SELECT CONVERT(bigint,[rowversion]) FROM dbo.Customers WHERE CustomerID=N'RT003');
TRUNCATE TABLE #Customers;
INSERT #Customers EXEC dbo.GetCustomerChangesByRowVersion @low,@high;
IF (SELECT COUNT(*) FROM #Customers)<>1 OR NOT EXISTS(SELECT 1 FROM #Customers WHERE CustomerID=N'RT002')
    THROW 51206,'Limites inferior exclusivo/superior inclusivo incorrectos.',1;
TRUNCATE TABLE #Customers;
INSERT #Customers EXEC dbo.GetCustomerChangesByRowVersion @high,@later;
IF (SELECT COUNT(*) FROM #Customers)<>1 OR NOT EXISTS(SELECT 1 FROM #Customers WHERE CustomerID=N'RT003')
    THROW 51207,'El cambio posterior no reaparece.',1;
TRUNCATE TABLE #Customers;
INSERT #Customers EXEC dbo.GetCustomerChangesByRowVersion @high,@high;
IF EXISTS(SELECT 1 FROM #Customers) THROW 51208,'Intervalo vacio devolvio filas.',1;
BEGIN TRY
    EXEC dbo.GetCustomerChangesByRowVersion -1,@high;
    THROW 51209,'Se acepto intervalo negativo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetCustomerChangesByRowVersion @high,@low;
    THROW 51209,'Se acepto intervalo invertido.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetCustomerChangesByRowVersion NULL,@high;
    THROW 51209,'Se acepto intervalo NULL.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
SELECT N'Limites y cambio posterior correctos; intervalos invalidos rechazados' AS Passed;

DECLARE @beforeDemographics bigint=CONVERT(bigint,@@DBTS);
INSERT dbo.CustomerDemographics(CustomerTypeID,CustomerDesc) VALUES(N'RV_CLASS1',N'Clase 1'),(N'RV_CLASS2',N'Clase 2');
INSERT dbo.CustomerCustomerDemo(CustomerID,CustomerTypeID) VALUES(N'VINET',N'RV_CLASS1'),(N'VINET',N'RV_CLASS2');
TRUNCATE TABLE #Customers;
INSERT #Customers EXEC dbo.GetCustomerChangesByRowVersion 0,9223372036854775807;
IF (SELECT COUNT(*) FROM #Customers WHERE CustomerID=N'VINET')<>1
    OR (SELECT COUNT(*) FROM #Customers WHERE CustomerID=N'RT001')<>1
    OR (SELECT COUNT(*) FROM #Customers)<>94
    THROW 51210,'Cero/varias clasificaciones multiplican o excluyen clientes.',1;
TRUNCATE TABLE #Customers;
DECLARE @afterDemographics bigint=CONVERT(bigint,@@DBTS);
INSERT #Customers EXEC dbo.GetCustomerChangesByRowVersion @beforeDemographics,@afterDemographics;
IF EXISTS(SELECT 1 FROM #Customers) THROW 51211,'Demografia inutil selecciono clientes.',1;
SELECT N'Cero/varias clasificaciones: una fila; cambios demograficos no seleccionan clientes' AS Passed;
