CREATE VIEW [dbo].[Order Subtotals]
AS
SELECT
    [dbo].[OrderDetails].OrderID,
    SUM(
        CONVERT(
            MONEY,
            ([dbo].[OrderDetails].UnitPrice * Quantity * (1 - Discount) / 100)
        ) * 100
    ) AS Subtotal
FROM [dbo].[OrderDetails]
GROUP BY [dbo].[OrderDetails].OrderID;