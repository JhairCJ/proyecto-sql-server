CREATE FUNCTION dbo.DW_CalculateAmounts
(
    @Quantity SMALLINT,
    @UnitPrice DECIMAL(19,4),
    @Discount DECIMAL(9,6)
)
RETURNS TABLE
AS RETURN
(
    SELECT b.GrossAmount,d.DiscountAmount,
           CONVERT(DECIMAL(19,2),b.GrossAmount-d.DiscountAmount) AS NetAmount
    FROM (VALUES(CONVERT(DECIMAL(19,2),ROUND(CONVERT(DECIMAL(5,0),@Quantity)*@UnitPrice,2)))) b(GrossAmount)
    CROSS APPLY (VALUES(CONVERT(DECIMAL(19,2),ROUND(b.GrossAmount*@Discount,2)))) d(DiscountAmount)
);
