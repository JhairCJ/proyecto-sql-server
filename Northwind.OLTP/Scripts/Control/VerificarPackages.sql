USE Northwind_DW;
GO

DECLARE @RV BINARY(8);

-- CLIENTE
EXEC dbo.GetLastPackageRowVersion
    N'Cliente', @RV OUTPUT;
SELECT 'Cliente' AS Paquete, @RV AS LastRowVersion;

-- EMPLEADO
EXEC dbo.GetLastPackageRowVersion
    N'Empleado', @RV OUTPUT;
SELECT 'Empleado' AS Paquete, @RV AS LastRowVersion;

-- PRODUCTO
EXEC dbo.GetLastPackageRowVersion
    N'Producto', @RV OUTPUT;
SELECT 'Producto' AS Paquete, @RV AS LastRowVersion;

-- TRANSPORTISTA
EXEC dbo.GetLastPackageRowVersion
    N'Transportista', @RV OUTPUT;
SELECT 'Transportista' AS Paquete, @RV AS LastRowVersion;

-- VENTAS
EXEC dbo.GetLastPackageRowVersion
    N'Ventas', @RV OUTPUT;
SELECT 'Ventas' AS Paquete, @RV AS LastRowVersion;
GO

