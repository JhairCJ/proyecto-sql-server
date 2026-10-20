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

    -- Cada fila conserva el precio vendido. El proveedor y el flete son valores
    -- actuales del producto y del encabezado, respectivamente.
    -- Primero se decide qué pedidos cambiaron; después se entregan todas sus
    -- líneas. Si alguna dependencia supera el corte, se difiere el pedido entero.
    SELECT o.OrderID, d.ProductID, o.CustomerID, o.EmployeeID,
           o.ShipVia AS ShipperID, p.SupplierID,
           o.OrderDate, o.RequiredDate, o.ShippedDate,
           CONVERT(DECIMAL(19,4), d.UnitPrice) AS UnitPrice,
           d.Quantity,
           CONVERT(DECIMAL(9,6), d.Discount) AS Discount,
           CONVERT(DECIMAL(19,4), o.Freight) AS Freight,
           o.ShipAddress, o.ShipCity, o.ShipRegion, o.ShipPostalCode, o.ShipCountry,
           CONVERT(BINARY(8), o.[rowversion]) AS OrderRowVersion,
           CONVERT(BINARY(8), d.[rowversion]) AS OrderDetailRowVersion,
           CONVERT(BINARY(8), p.[rowversion]) AS ProductRowVersion
    FROM dbo.Orders AS o
    INNER JOIN dbo.OrderDetails AS d ON d.OrderID = o.OrderID
    INNER JOIN dbo.Products AS p ON p.ProductID = d.ProductID
    WHERE o.[rowversion] <= @end
      AND EXISTS
      (
          SELECT 1
          FROM dbo.OrderDetails AS changedDetail
          INNER JOIN dbo.Products AS changedProduct
              ON changedProduct.ProductID = changedDetail.ProductID
          WHERE changedDetail.OrderID = o.OrderID
            AND (o.[rowversion] > @start
                 OR changedDetail.[rowversion] > @start
                 OR changedProduct.[rowversion] > @start)
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.OrderDetails AS pendingDetail
          INNER JOIN dbo.Products AS pendingProduct
              ON pendingProduct.ProductID = pendingDetail.ProductID
          WHERE pendingDetail.OrderID = o.OrderID
            AND (pendingDetail.[rowversion] > @end
                 OR pendingProduct.[rowversion] > @end)
      );
END;
