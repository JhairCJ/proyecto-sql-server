CREATE PROCEDURE [dbo].[GetSupplierChangesByRowVersion]
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

    SELECT s.SupplierID, s.CompanyName, s.ContactName, s.ContactTitle,
           s.[Address], s.City, s.Region, s.PostalCode, s.Country,
           s.Phone, s.Fax, s.HomePage,
           CONVERT(BINARY(8), s.[rowversion]) AS SourceRowVersion
    FROM dbo.Suppliers AS s
    WHERE s.[rowversion] > @start AND s.[rowversion] <= @end;
END;
