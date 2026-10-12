-- Ejecutar mediante Invoke-NorthwindTestSql; rollback automatico al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
CREATE TABLE #Shippers(ShipperID int,CompanyName nvarchar(40) COLLATE DATABASE_DEFAULT,Phone nvarchar(24) COLLATE DATABASE_DEFAULT,SourceRowVersion binary(8));
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
INSERT #Shippers EXEC dbo.GetShipperChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Shippers)<>3
    OR EXISTS(SELECT ShipperID FROM #Shippers GROUP BY ShipperID HAVING COUNT(*)<>1)
    THROW 51501,'Referencia de transportistas incorrecta.',1;
IF EXISTS(SELECT ShipperID,CompanyName,Phone,CONVERT(binary(8),rowversion) FROM dbo.Shippers
    EXCEPT SELECT * FROM #Shippers)
    THROW 51502,'Atributos o marca del transportista incorrectos.',1;
SELECT N'Tres transportistas unicos y contrato std.Transportista compatible' AS Passed;

DECLARE @before bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Shippers SET CompanyName=N'Transporte prueba',Phone=NULL WHERE ShipperID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Shippers;
INSERT #Shippers EXEC dbo.GetShipperChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Shippers)<>1 OR NOT EXISTS(SELECT 1 FROM #Shippers
    WHERE ShipperID=1 AND CompanyName=N'Transporte prueba' AND Phone IS NULL
    AND SourceRowVersion=CONVERT(binary(8),@end))
    THROW 51503,'Actualizacion o limite superior excluido.',1;
TRUNCATE TABLE #Shippers;
INSERT #Shippers EXEC dbo.GetShipperChangesByRowVersion @end,9223372036854775807;
IF EXISTS(SELECT 1 FROM #Shippers) THROW 51504,'Limite inferior debe excluirse.',1;
SELECT N'Actualizacion y telefono NULL; superior incluido e inferior excluido' AS Passed;

INSERT dbo.Shippers(CompanyName,Phone) VALUES(N'Alta de prueba',N'555');
DECLARE @newID int=CONVERT(int,SCOPE_IDENTITY()),@later bigint=CONVERT(bigint,@@DBTS);
INSERT #Shippers EXEC dbo.GetShipperChangesByRowVersion @before,@end;
IF EXISTS(SELECT 1 FROM #Shippers WHERE ShipperID=@newID)
    THROW 51505,'Alta posterior al corte publicada antes de tiempo.',1;
TRUNCATE TABLE #Shippers;
INSERT #Shippers EXEC dbo.GetShipperChangesByRowVersion @end,@later;
IF (SELECT COUNT(*) FROM #Shippers)<>1 OR NOT EXISTS(SELECT 1 FROM #Shippers WHERE ShipperID=@newID)
    THROW 51506,'Alta diferida perdida.',1;
SELECT N'Alta posterior excluida y recuperada en el siguiente intervalo' AS Passed;

TRUNCATE TABLE #Shippers;
INSERT #Shippers EXEC dbo.GetShipperChangesByRowVersion @later,@later;
IF EXISTS(SELECT 1 FROM #Shippers) THROW 51507,'Intervalo vacio devuelve filas.',1;
BEGIN TRY
    EXEC dbo.GetShipperChangesByRowVersion -1,@later;
    THROW 51508,'Se acepto inicio negativo.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51104 THROW;
END CATCH;
BEGIN TRY
    EXEC dbo.GetShipperChangesByRowVersion 2,1;
    THROW 51509,'Se acepto intervalo invertido.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51104 THROW;
END CATCH;
BEGIN TRY
    EXEC dbo.GetShipperChangesByRowVersion NULL,@later;
    THROW 51510,'Se acepto NULL.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51104 THROW;
END CATCH;
SELECT N'Intervalo vacio e intervalos invalidos comprobados' AS Passed;
