-- Ejecutar después de restaurar las dos copias con los nombres indicados.
USE [Northwind_Test];
SET NOCOUNT ON;
IF DB_NAME()<>N'Northwind_Test' OR OBJECT_ID(N'dbo.Customers',N'U') IS NULL
 OR OBJECT_ID(N'dbo.Orders',N'U') IS NULL OR OBJECT_ID(N'dbo.OrderDetails',N'U') IS NULL
 THROW 51510,'El destino no es la copia operativa esperada.',1;
IF EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)<>N'NorthWind')
 THROW 51511,'La copia contiene una identificación diferente.',1;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase')
 EXEC sys.sp_addextendedproperty @name=N'NorthwindPracticeTestDatabase',@value=N'NorthWind';
IF USER_ID(N'NorthwindFixture') IS NULL CREATE USER [NorthwindFixture] WITHOUT LOGIN;
GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE TO [NorthwindFixture];
ALTER DATABASE [Northwind_Test] SET TRUSTWORTHY OFF;
ALTER DATABASE [Northwind_Test] SET DB_CHAINING OFF;
GO
USE [Northwind_DW_Test];
SET NOCOUNT ON;
IF DB_NAME()<>N'Northwind_DW_Test' OR OBJECT_ID(N'dbo.Dim_Cliente',N'U') IS NULL
 OR OBJECT_ID(N'dbo.Fact_Ventas',N'U') IS NULL OR OBJECT_ID(N'dbo.PackageConfig',N'U') IS NULL
 THROW 51512,'El destino no es la copia del almacén esperada.',1;
IF EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)<>N'Northwind_DW')
 THROW 51513,'La copia contiene una identificación diferente.',1;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase')
 EXEC sys.sp_addextendedproperty @name=N'NorthwindPracticeTestDatabase',@value=N'Northwind_DW';
IF USER_ID(N'NorthwindFixture') IS NULL CREATE USER [NorthwindFixture] WITHOUT LOGIN;
GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE TO [NorthwindFixture];
ALTER DATABASE [Northwind_DW_Test] SET TRUSTWORTHY OFF;
ALTER DATABASE [Northwind_DW_Test] SET DB_CHAINING OFF;
SELECT DB_NAME() AS Almacen,N'Copias identificadas' AS Resultado;
