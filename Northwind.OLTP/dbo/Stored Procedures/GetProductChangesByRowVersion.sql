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
           p.CategoryID, c.CategoryName, c.[Description] AS CategoryDescription,
           p.SupplierID, p.UnitsInStock, p.UnitsOnOrder, p.ReorderLevel, p.Discontinued,
           CONVERT(BINARY(8), p.[rowversion]) AS ProductRowVersion,
           CONVERT(BINARY(8), c.[rowversion]) AS CategoryRowVersion
    FROM dbo.Products AS p
    LEFT JOIN dbo.Categories AS c ON c.CategoryID = p.CategoryID
    -- SupplierID es una clave comercial. Sus atributos se extraen por separado.
    -- Una categoria posterior al corte difiere el producto completo.
    WHERE p.[rowversion] <= @end
      AND (c.CategoryID IS NULL OR c.[rowversion] <= @end)
      AND (p.[rowversion] > @start OR c.[rowversion] > @start);
END;
