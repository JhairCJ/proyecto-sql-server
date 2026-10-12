CREATE PROCEDURE [dbo].[GetSalesChangesByRowVersion]
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
    -- Una fila por linea; los precios proceden de la venta, no del catalogo.
    -- Contrato actual de std.Ventas, sin flete repetido ni joins de dimensiones.
    SELECT o.OrderID, d.ProductID, o.CustomerID, o.EmployeeID,
           o.ShipVia AS ShipperID, o.OrderDate, o.RequiredDate, o.ShippedDate,
           d.UnitPrice, d.Quantity, d.Discount,
           CONVERT(BINARY(8), o.[rowversion]) AS OrderRowVersion,
           CONVERT(BINARY(8), d.[rowversion]) AS OrderDetailRowVersion
    FROM dbo.Orders AS o
    INNER JOIN dbo.OrderDetails AS d ON d.OrderID = o.OrderID
    WHERE o.[rowversion] <= @end AND d.[rowversion] <= @end
      AND (o.[rowversion] > @start OR d.[rowversion] > @start);
END;
