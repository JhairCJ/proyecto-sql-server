CREATE PROCEDURE [dbo].[BigIntToRowVersion]
    @Value BIGINT,
    @RowVersion BINARY(8) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Value IS NULL OR @Value < 0
        THROW 51102, 'Int64 invalido: la marca debe ser no nula y no negativa.', 1;
    SET @RowVersion = CONVERT(BINARY(8), @Value);
    IF CONVERT(BIGINT, @RowVersion) <> @Value
        THROW 51102, 'La conversion de Int64 perdio informacion.', 1;
END;
