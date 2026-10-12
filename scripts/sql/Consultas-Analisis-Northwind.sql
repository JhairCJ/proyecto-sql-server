USE [Northwind_DW];
GO

-- Clientes con mayores ventas netas. El pais corresponde al pais del cliente.
SELECT TOP (10)
    c.CustomerID,
    c.NombreEmpresa AS Cliente,
    c.Pais AS PaisCliente,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    SUM(CONVERT(bigint, f.Cantidad)) AS Unidades,
    CONVERT(decimal(18,2), SUM(f.ImporteNeto)) AS VentasNetas
FROM dbo.Fact_Ventas AS f
INNER JOIN dbo.Dim_Cliente AS c ON c.Cliente_SK = f.Cliente_SK
GROUP BY c.CustomerID, c.NombreEmpresa, c.Pais
ORDER BY VentasNetas DESC, c.CustomerID;
GO

-- Productos mas comprados, ordenados por unidades vendidas.
SELECT TOP (10)
    p.ProductID,
    p.NombreProducto AS Producto,
    p.Categoria,
    SUM(CONVERT(bigint, f.Cantidad)) AS UnidadesVendidas,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    CONVERT(decimal(18,2), SUM(f.ImporteNeto)) AS VentasNetas
FROM dbo.Fact_Ventas AS f
INNER JOIN dbo.Dim_Producto AS p ON p.Producto_SK = f.Producto_SK
GROUP BY p.ProductID, p.NombreProducto, p.Categoria
ORDER BY UnidadesVendidas DESC, p.ProductID;
GO

-- Categorias mas compradas, ordenadas por unidades vendidas.
SELECT TOP (10)
    COALESCE(NULLIF(LTRIM(RTRIM(p.Categoria)), N''), N'Sin categoria') AS Categoria,
    SUM(CONVERT(bigint, f.Cantidad)) AS UnidadesVendidas,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    COUNT_BIG(*) AS LineasDeVenta,
    CONVERT(decimal(18,2), SUM(f.ImporteNeto)) AS VentasNetas
FROM dbo.Fact_Ventas AS f
INNER JOIN dbo.Dim_Producto AS p ON p.Producto_SK = f.Producto_SK
GROUP BY COALESCE(NULLIF(LTRIM(RTRIM(p.Categoria)), N''), N'Sin categoria')
ORDER BY UnidadesVendidas DESC, Categoria;
GO

-- Paises de clientes con mayores ventas netas; no representa el pais de envio.
SELECT TOP (10)
    COALESCE(NULLIF(LTRIM(RTRIM(c.Pais)), N''), N'Sin pais') AS PaisCliente,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    SUM(CONVERT(bigint, f.Cantidad)) AS Unidades,
    CONVERT(decimal(18,2), SUM(f.ImporteNeto)) AS VentasNetas
FROM dbo.Fact_Ventas AS f
INNER JOIN dbo.Dim_Cliente AS c ON c.Cliente_SK = f.Cliente_SK
GROUP BY COALESCE(NULLIF(LTRIM(RTRIM(c.Pais)), N''), N'Sin pais')
ORDER BY VentasNetas DESC, PaisCliente;
GO
