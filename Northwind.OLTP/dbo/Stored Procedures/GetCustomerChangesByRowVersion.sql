CREATE PROCEDURE [dbo].[GetCustomerChangesByRowVersion]
    @startRow BIGINT,
    @endRow BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    IF @startRow IS NULL OR @endRow IS NULL OR @startRow < 0 OR @endRow < @startRow
        THROW 51104, 'Intervalo invalido: requiere 0 <= inicio <= fin y valores no nulos.', 1;
    DECLARE @start BINARY(8), @end BINARY(8);
    EXEC dbo.BigIntToRowVersion @startRow, @start OUTPUT;
    EXEC dbo.BigIntToRowVersion @endRow, @end OUTPUT;
    -- Contrato de std.Cliente. Demografia no aporta atributos de esta dimension.
    SELECT c.CustomerID, c.CompanyName, c.ContactName, c.ContactTitle,
           c.City, c.Region, c.PostalCode, c.Country,
           CONVERT(BINARY(8), c.[rowversion]) AS SourceRowVersion
    FROM dbo.Customers AS c
    WHERE c.[rowversion] > @start AND c.[rowversion] <= @end;
END;
