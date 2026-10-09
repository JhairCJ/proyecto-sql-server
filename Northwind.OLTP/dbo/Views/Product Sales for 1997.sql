CREATE VIEW [dbo].[Product Sales for 1997]
AS
SELECT
    Categories.CategoryName,
    Products.ProductName,
    SUM(
        CONVERT(
            MONEY,
            ([dbo].[OrderDetails].UnitPrice * Quantity * (1 - Discount) / 100)
        ) * 100
    ) AS ProductSales
FROM
    (Categories
        INNER JOIN Products
            ON Categories.CategoryID = Products.CategoryID)
    INNER JOIN
    (Orders
        INNER JOIN [dbo].[OrderDetails]
            ON Orders.OrderID = [dbo].[OrderDetails].OrderID)
        ON Products.ProductID = [dbo].[OrderDetails].ProductID
WHERE
    Orders.ShippedDate BETWEEN '19970101' AND '19971231'
GROUP BY
    Categories.CategoryName,
    Products.ProductName;