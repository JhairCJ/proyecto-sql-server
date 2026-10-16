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
DECLARE @Sql nvarchar(max)=N'GRANT SELECT ON dbo.DimDate TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.DimProduct TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.DimCustomer TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.DimEmployee TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.DimShipper TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.DimSupplier TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.DimGeography TO '+QUOTENAME(@ServiceAccount)+N';
GRANT SELECT ON dbo.FactSales TO '+QUOTENAME(@ServiceAccount)+N';';
IF OBJECT_ID(N'dbo.Dim_Cliente',N'U') IS NOT NULL
 REVOKE SELECT ON OBJECT::dbo.Dim_Cliente FROM [NT SERVICE\MSSQLServerOLAPService];
IF OBJECT_ID(N'dbo.Dim_Empleado',N'U') IS NOT NULL
 REVOKE SELECT ON OBJECT::dbo.Dim_Empleado FROM [NT SERVICE\MSSQLServerOLAPService];
IF OBJECT_ID(N'dbo.Dim_Producto',N'U') IS NOT NULL
 REVOKE SELECT ON OBJECT::dbo.Dim_Producto FROM [NT SERVICE\MSSQLServerOLAPService];
IF OBJECT_ID(N'dbo.Dim_Transportista',N'U') IS NOT NULL
 REVOKE SELECT ON OBJECT::dbo.Dim_Transportista FROM [NT SERVICE\MSSQLServerOLAPService];
IF OBJECT_ID(N'dbo.Dim_Tiempo',N'U') IS NOT NULL
 REVOKE SELECT ON OBJECT::dbo.Dim_Tiempo FROM [NT SERVICE\MSSQLServerOLAPService];
IF OBJECT_ID(N'dbo.Fact_Ventas',N'U') IS NOT NULL
 REVOKE SELECT ON OBJECT::dbo.Fact_Ventas FROM [NT SERVICE\MSSQLServerOLAPService];
EXEC sys.sp_executesql @Sql;
SELECT @ServiceAccount AS Cuenta,DB_NAME() AS Base,N'SELECT en ocho tablas' AS Permiso;
