USE [Northwind_DW];
GO

-- Clientes: Country describe la ubicación del cliente, no el destino del pedido.
SELECT TOP (10)
    c.CustomerID, c.CompanyName AS Cliente, c.Country AS PaisCliente,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    SUM(CONVERT(bigint,f.Quantity)) AS Unidades,
    CONVERT(decimal(19,2),SUM(f.NetAmount)) AS VentasNetas
FROM dbo.FactSales AS f
JOIN dbo.DimCustomer AS c ON c.CustomerKey=f.CustomerKey
GROUP BY c.CustomerID,c.CompanyName,c.Country
ORDER BY VentasNetas DESC,c.CustomerID;
GO

-- Productos: la categoría se guarda en DimProduct; las ventas usan el precio de la línea.
SELECT TOP (10)
    p.ProductID,p.ProductName,p.CategoryName,
    SUM(CONVERT(bigint,f.Quantity)) AS UnidadesVendidas,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    CONVERT(decimal(19,2),SUM(f.NetAmount)) AS VentasNetas
FROM dbo.FactSales AS f
JOIN dbo.DimProduct AS p ON p.ProductKey=f.ProductKey
GROUP BY p.ProductID,p.ProductName,p.CategoryName
ORDER BY UnidadesVendidas DESC,p.ProductID;
GO

-- Proveedores: asociación actual del producto. Los importes vendidos no se revalorizan.
SELECT TOP (10)
    s.SupplierID,s.CompanyName AS Proveedor,
    SUM(CONVERT(bigint,f.Quantity)) AS UnidadesVendidas,
    COUNT(DISTINCT f.OrderID) AS Pedidos,
    CONVERT(decimal(19,2),SUM(f.NetAmount)) AS VentasNetas
FROM dbo.FactSales AS f
JOIN dbo.DimSupplier AS s ON s.SupplierKey=f.SupplierKey
GROUP BY s.SupplierID,s.CompanyName
ORDER BY VentasNetas DESC,s.SupplierID;
GO

-- Destino: Freight se reduce a una fila por OrderID antes de sumarse.
WITH OrderFreight AS
(
    SELECT OrderID,GeographyKey,MAX(Freight) AS Freight
    FROM dbo.FactSales
    GROUP BY OrderID,GeographyKey
)
SELECT TOP (10)
    g.ShipCountry AS PaisDestino,g.ShipCity AS CiudadDestino,
    COUNT_BIG(*) AS Pedidos,
    CONVERT(decimal(19,4),SUM(o.Freight)) AS FleteTotal
FROM OrderFreight AS o
JOIN dbo.DimGeography AS g ON g.GeographyKey=o.GeographyKey
GROUP BY g.ShipCountry,g.ShipCity
ORDER BY FleteTotal DESC,g.ShipCountry,g.ShipCity;
GO

-- Un pedido de referencia tiene tres líneas, pero el flete se cuenta una vez.
SELECT OrderID,COUNT_BIG(*) AS Lineas,MAX(Freight) AS FreightUnaVez,
       SUM(GrossAmount) AS Bruto,SUM(DiscountAmount) AS Descuento,SUM(NetAmount) AS Neto
FROM dbo.FactSales
WHERE OrderID=10248
GROUP BY OrderID;
GO
