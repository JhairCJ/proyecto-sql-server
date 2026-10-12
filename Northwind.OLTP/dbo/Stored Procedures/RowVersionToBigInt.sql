CREATE PROCEDURE [dbo].[RowVersionToBigInt]
    @RowVersion BINARY(8),
    @Value BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @RowVersion IS NULL OR @RowVersion > 0x7FFFFFFFFFFFFFFF
        THROW 51101, 'Marca binaria no representable como Int64 no negativo.', 1;
    SET @Value = CONVERT(BIGINT, @RowVersion);
    IF CONVERT(BINARY(8), @Value) <> @RowVersion
        THROW 51101, 'La conversion de rowversion perdio informacion.', 1;
END;
