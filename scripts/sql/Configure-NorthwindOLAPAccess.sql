USE [Northwind_DW_Test];
SET NOCOUNT ON;
DECLARE @ServiceAccount sysname=N'NT Service\MSSQLServerOLAPService';
IF DB_NAME()<>N'Northwind_DW_Test' OR NOT EXISTS(
 SELECT 1 FROM sys.extended_properties WHERE class=0
 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 51501,'El destino no es la copia marcada Northwind_DW_Test.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE name=DB_NAME() AND (is_trustworthy_on=1 OR is_db_chaining_on=1))
 THROW 51502,'La copia no conserva su aislamiento.',1;
DECLARE @Statement nvarchar(max);
IF SUSER_ID(@ServiceAccount) IS NULL
BEGIN
 SET @Statement=N'CREATE LOGIN '+QUOTENAME(@ServiceAccount)+N' FROM WINDOWS;';
 EXEC sys.sp_executesql @Statement;
END;
IF USER_ID(@ServiceAccount) IS NULL
BEGIN
 SET @Statement=N'CREATE USER '+QUOTENAME(@ServiceAccount)+N' FOR LOGIN '+QUOTENAME(@ServiceAccount)+N';';
 EXEC sys.sp_executesql @Statement;
END;
DECLARE @Sql nvarchar(max)=N'GRANT SELECT ON dbo.Dim_Cliente TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.Dim_Empleado TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.Dim_Producto TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.Dim_Transportista TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.Dim_Tiempo TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.Fact_Ventas TO '+QUOTENAME(@ServiceAccount)+N';';
EXEC sys.sp_executesql @Sql;
SELECT @ServiceAccount AS Cuenta,DB_NAME() AS Base,N'SELECT en seis tablas' AS Permiso;
