CREATE FUNCTION dbo.DW_CalculateAmounts
(
    @Quantity SMALLINT,
    @UnitPrice DECIMAL(19,4),
    @Discount DECIMAL(9,6)
)
RETURNS TABLE
AS RETURN
(
    SELECT b.ImporteBruto,d.ImporteDescuento,
           CONVERT(DECIMAL(18,2),b.ImporteBruto-d.ImporteDescuento) AS ImporteNeto
    FROM (VALUES(CONVERT(DECIMAL(18,2),ROUND(CONVERT(DECIMAL(5,0),@Quantity)*@UnitPrice,2)))) b(ImporteBruto)
    CROSS APPLY (VALUES(CONVERT(DECIMAL(18,2),ROUND(b.ImporteBruto*@Discount,2)))) d(ImporteDescuento)
);
