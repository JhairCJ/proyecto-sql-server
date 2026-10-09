CREATE VIEW [dbo].[Order Details Extended]
AS
SELECT
    [dbo].[OrderDetails].OrderID,
    [dbo].[OrderDetails].ProductID,
    Products.ProductName,
    [dbo].[OrderDetails].UnitPrice,
    [dbo].[OrderDetails].Quantity,
    [dbo].[OrderDetails].Discount,
    (CONVERT(
        MONEY,
        ([dbo].[OrderDetails].UnitPrice * Quantity * (1 - Discount) / 100)
    ) * 100) AS ExtendedPrice
FROM Products
INNER JOIN [dbo].[OrderDetails]
    ON Products.ProductID = [dbo].[OrderDetails].ProductID;