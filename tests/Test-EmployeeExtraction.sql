-- Batch de fixtures para Invoke-NorthwindTestSql, revertido al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF; -- Capturar rechazos deliberados dentro del fixture.
CREATE TABLE #Employees(EmployeeID int,FirstName nvarchar(10) COLLATE DATABASE_DEFAULT,
    LastName nvarchar(20) COLLATE DATABASE_DEFAULT,FullName nvarchar(60) COLLATE DATABASE_DEFAULT,
    Title nvarchar(30) COLLATE DATABASE_DEFAULT,TitleOfCourtesy nvarchar(25) COLLATE DATABASE_DEFAULT,
    BirthDate date,HireDate date,[Address] nvarchar(60) COLLATE DATABASE_DEFAULT,
    City nvarchar(15) COLLATE DATABASE_DEFAULT,Region nvarchar(15) COLLATE DATABASE_DEFAULT,
    Country nvarchar(15) COLLATE DATABASE_DEFAULT,PostalCode nvarchar(10) COLLATE DATABASE_DEFAULT,
    HomePhone nvarchar(24) COLLATE DATABASE_DEFAULT,Extension nvarchar(4) COLLATE DATABASE_DEFAULT,
    ReportsTo int,SourceRowVersion binary(8),SupervisorName nvarchar(60) COLLATE DATABASE_DEFAULT);
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion 0,@end;
IF (SELECT COUNT(*) FROM #Employees)<>9
    OR EXISTS(SELECT EmployeeID FROM #Employees GROUP BY EmployeeID HAVING COUNT(*)<>1)
    THROW 51301,'La referencia no devuelve nueve empleados unicos.',1;
IF NOT EXISTS(SELECT 1 FROM #Employees WHERE EmployeeID=2 AND ReportsTo IS NULL AND SupervisorName IS NULL)
    THROW 51302,'Se perdio el empleado sin supervisor.',1;
IF EXISTS(SELECT 1 FROM #Employees e JOIN dbo.Employees s ON s.EmployeeID=e.EmployeeID
    WHERE e.FullName<>CONCAT(s.FirstName,N' ',s.LastName)
       OR ISNULL(e.[Address],N'')<>ISNULL(s.[Address],N'')
       OR ISNULL(e.HomePhone,N'')<>ISNULL(s.HomePhone,N'')
       OR ISNULL(e.Extension,N'')<>ISNULL(s.Extension,N''))
    THROW 51302,'Atributos completos del empleado difieren del origen.',1;
SELECT N'Referencia: 9 empleados unicos y contrato std.Empleado compatible' AS Passed;

DELETE dbo.EmployeeTerritories WHERE EmployeeID=1;
IF (SELECT COUNT(*) FROM dbo.EmployeeTerritories WHERE EmployeeID=2)<2
    THROW 51303,'La referencia necesita varios territorios para el empleado 2.',1;
TRUNCATE TABLE #Employees;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion 0,9223372036854775807;
IF (SELECT COUNT(*) FROM #Employees)<>9
    OR (SELECT COUNT(*) FROM #Employees WHERE EmployeeID=1)<>1
    OR (SELECT COUNT(*) FROM #Employees WHERE EmployeeID=2)<>1
    THROW 51304,'Cero/varios territorios excluyen o multiplican empleados.',1;
SELECT N'Empleado sin territorios y con varios territorios: una fila por identidad' AS Passed;

DECLARE @before bigint=CONVERT(bigint,@@DBTS);
DECLARE @childVersion binary(8)=(SELECT [rowversion] FROM dbo.Employees WHERE EmployeeID=1);
UPDATE dbo.Employees SET FirstName=N'Cambio' WHERE EmployeeID=2;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Employees;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion @before,@end;
IF EXISTS(SELECT EmployeeID FROM dbo.Employees WHERE EmployeeID=2 OR ReportsTo=2
    EXCEPT SELECT EmployeeID FROM #Employees)
    OR EXISTS(SELECT EmployeeID FROM #Employees
    EXCEPT SELECT EmployeeID FROM dbo.Employees WHERE EmployeeID=2 OR ReportsTo=2)
    THROW 51305,'Cambio del supervisor no selecciono exactamente sus dependientes.',1;
IF NOT EXISTS(SELECT 1 FROM #Employees WHERE EmployeeID=1
    AND SupervisorName=N'Cambio Fuller' AND SourceRowVersion=@childVersion)
    THROW 51306,'Nombre de supervisor incorrecto o marca propia alterada.',1;
IF EXISTS(SELECT EmployeeID FROM #Employees GROUP BY EmployeeID HAVING COUNT(*)<>1)
    THROW 51307,'Cambio del supervisor duplico empleados.',1;
SELECT N'Supervisor modificado: subordinados seleccionados con marca propia intacta' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Employees SET Title=N'Prueba de corte' WHERE EmployeeID=1;
DECLARE @oldCut bigint=CONVERT(bigint,@@DBTS);
UPDATE dbo.Employees SET FirstName=N'Posterior' WHERE EmployeeID=2;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Employees;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion @before,@oldCut;
IF EXISTS(SELECT 1 FROM #Employees) THROW 51308,'Se mezclo un supervisor posterior con el corte anterior.',1;
TRUNCATE TABLE #Employees;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion @oldCut,@end;
IF NOT EXISTS(SELECT 1 FROM #Employees WHERE EmployeeID=1 AND Title=N'Prueba de corte'
    AND SupervisorName=N'Posterior Fuller')
    THROW 51309,'Empleado diferido no reaparecio en el intervalo siguiente.',1;
SELECT N'Supervisor posterior al corte difiere la fila; siguiente intervalo la recupera' AS Passed;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Employees SET ReportsTo=NULL WHERE EmployeeID=1;
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Employees;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion @before,@end;
IF (SELECT COUNT(*) FROM #Employees)<>1 OR NOT EXISTS(SELECT 1 FROM #Employees
    WHERE EmployeeID=1 AND ReportsTo IS NULL AND SupervisorName IS NULL)
    THROW 51310,'Empleado con supervisor retirado se perdio.',1;

SET @before=CONVERT(bigint,@@DBTS);
UPDATE dbo.Territories SET TerritoryDescription=N'No utilizado por dimension'
    WHERE TerritoryID=(SELECT MIN(TerritoryID) FROM dbo.Territories);
SET @end=CONVERT(bigint,@@DBTS);
TRUNCATE TABLE #Employees;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion @before,@end;
IF EXISTS(SELECT 1 FROM #Employees) THROW 51311,'Territorio ajeno al contrato selecciono empleados.',1;
INSERT #Employees EXEC dbo.GetEmployeeChangesByRowVersion @end,@end;
IF EXISTS(SELECT 1 FROM #Employees) THROW 51312,'Intervalo vacio devolvio empleados.',1;
BEGIN TRY
    EXEC dbo.GetEmployeeChangesByRowVersion -1,@end;
    THROW 51313,'Intervalo negativo aceptado.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetEmployeeChangesByRowVersion @end,0;
    THROW 51313,'Intervalo invertido aceptado.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
BEGIN TRY
    EXEC dbo.GetEmployeeChangesByRowVersion NULL,@end;
    THROW 51313,'Intervalo NULL aceptado.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>51104 THROW; END CATCH;
SELECT N'Relacion opcional preservada; territorios ignorados; intervalos invalido/vacio correctos' AS Passed;
