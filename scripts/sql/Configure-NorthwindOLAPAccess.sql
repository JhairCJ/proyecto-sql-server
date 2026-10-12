USE [Northwind_DW];
SET NOCOUNT ON;
DECLARE @ServiceAccount sysname=N'NT Service\MSSQLServerOLAPService';
IF DB_NAME()<>N'Northwind_DW'
 THROW 51501,'El destino debe ser la base real Northwind_DW.',1;
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
