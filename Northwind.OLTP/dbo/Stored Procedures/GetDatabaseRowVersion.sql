
CREATE PROCEDURE [dbo].[GetDatabaseRowVersion]
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    -- Corte exclusivo: no avanzar sobre escrituras pendientes.
    DECLARE @exclusive BINARY(8) = MIN_ACTIVE_ROWVERSION();
    DECLARE @cut BIGINT;
    IF @exclusive = 0x0000000000000000 OR @exclusive > 0x8000000000000000
        THROW 51103, 'Corte rowversion no representable como Int64 inclusivo.', 1;
    IF @exclusive = 0x8000000000000000
        SET @cut = 9223372036854775807;
    ELSE
    BEGIN
        EXEC dbo.RowVersionToBigInt @exclusive, @cut OUTPUT;
        SET @cut = @cut - 1;
    END;
    SELECT DBTS = @cut;
END
