CREATE VIEW [dbo].[Invoices]
AS
SELECT
    o.ShipName,
    o.ShipAddress,
    o.ShipCity,
    o.ShipRegion,
    o.ShipPostalCode,
    o.ShipCountry,

    o.CustomerID,

    c.CompanyName AS CustomerName,
    c.Address,
    c.City,
    c.Region,
    c.PostalCode,
    c.Country,

    (e.FirstName + ' ' + e.LastName) AS Salesperson,

    o.OrderID,
    o.OrderDate,
    o.RequiredDate,
    o.ShippedDate,

    s.CompanyName AS ShipperName,

    od.ProductID,
    p.ProductName,
    od.UnitPrice,
    od.Quantity,
    od.Discount,

    CONVERT(
        MONEY,
        od.UnitPrice * od.Quantity * (1 - od.Discount)
    ) AS ExtendedPrice,

    o.Freight

FROM [dbo].[Orders] AS o

INNER JOIN [dbo].[Customers] AS c
    ON c.CustomerID = o.CustomerID

INNER JOIN [dbo].[Employees] AS e
    ON e.EmployeeID = o.EmployeeID

INNER JOIN [dbo].[OrderDetails] AS od
    ON od.OrderID = o.OrderID

INNER JOIN [dbo].[Products] AS p
    ON p.ProductID = od.ProductID

INNER JOIN [dbo].[Shippers] AS s
    ON s.ShipperID = o.ShipVia;