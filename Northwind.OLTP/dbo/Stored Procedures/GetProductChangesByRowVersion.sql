CREATE PROCEDURE [dbo].[GetProductChangesByRowVersion]
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

    SELECT p.ProductID, p.ProductName, p.QuantityPerUnit,
           p.CategoryID, c.CategoryName,
           p.SupplierID, s.CompanyName AS SupplierName, s.Country AS SupplierCountry,
           p.Discontinued,
           CONVERT(BINARY(8), p.[rowversion]) AS ProductRowVersion,
           CONVERT(BINARY(8), c.[rowversion]) AS CategoryRowVersion,
           CONVERT(BINARY(8), s.[rowversion]) AS SupplierRowVersion
    FROM dbo.Products AS p
    LEFT JOIN dbo.Categories AS c ON c.CategoryID = p.CategoryID
    LEFT JOIN dbo.Suppliers AS s ON s.SupplierID = p.SupplierID
    -- Una dependencia posterior al corte difiere la entidad completa.
    WHERE p.[rowversion] <= @end
      AND (c.CategoryID IS NULL OR c.[rowversion] <= @end)
      AND (s.SupplierID IS NULL OR s.[rowversion] <= @end)
      AND (p.[rowversion] > @start OR c.[rowversion] > @start OR s.[rowversion] > @start);
END;
