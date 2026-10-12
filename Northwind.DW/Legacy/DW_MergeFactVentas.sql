CREATE PROCEDURE dbo.DW_MergeFactVentas
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.Fact_Ventas AS D

    USING
    (
        SELECT
            V.OrderID,

            DC.Cliente_SK,
            DE.Empleado_SK,
            DP.Producto_SK,
            DTR.Transportista_SK,

            /* Fecha Pedido */
            YEAR(V.OrderDate) * 10000
            + MONTH(V.OrderDate) * 100
            + DAY(V.OrderDate)
                AS FechaPedido_SK,

            /* Fecha Requerida */
            CASE
                WHEN V.RequiredDate IS NULL
                    THEN NULL
                ELSE
                    YEAR(V.RequiredDate) * 10000
                    + MONTH(V.RequiredDate) * 100
                    + DAY(V.RequiredDate)
            END AS FechaRequerida_SK,

            /* Fecha Envío */
            CASE
                WHEN V.ShippedDate IS NULL
                    THEN NULL
                ELSE
                    YEAR(V.ShippedDate) * 10000
                    + MONTH(V.ShippedDate) * 100
                    + DAY(V.ShippedDate)
            END AS FechaEnvio_SK,

            V.Quantity,
            V.UnitPrice,
            V.Discount,

            /* Importe sin descuento */
            CAST(
                V.Quantity * V.UnitPrice
                AS DECIMAL(18,2)
            ) AS ImporteBruto,

            /* Monto descontado */
            CAST(
                V.Quantity
                * V.UnitPrice
                * V.Discount
                AS DECIMAL(18,2)
            ) AS ImporteDescuento,

            /* Total después del descuento */
            CAST(
                V.Quantity
                * V.UnitPrice
                * (1 - V.Discount)
                AS DECIMAL(18,2)
            ) AS ImporteNeto

        FROM std.Ventas V

        INNER JOIN dbo.Dim_Cliente DC
            ON DC.CustomerID = V.CustomerID

        INNER JOIN dbo.Dim_Empleado DE
            ON DE.EmployeeID = V.EmployeeID

        INNER JOIN dbo.Dim_Producto DP
            ON DP.ProductID = V.ProductID

        LEFT JOIN dbo.Dim_Transportista DTR
            ON DTR.ShipperID = V.ShipperID

        WHERE V.OrderDate IS NOT NULL

    ) AS S

    ON
        D.OrderID = S.OrderID
        AND D.Producto_SK = S.Producto_SK

    WHEN MATCHED THEN
        UPDATE SET

            D.Cliente_SK         = S.Cliente_SK,
            D.Empleado_SK        = S.Empleado_SK,
            D.Transportista_SK   = S.Transportista_SK,

            D.FechaPedido_SK     = S.FechaPedido_SK,
            D.FechaRequerida_SK  = S.FechaRequerida_SK,
            D.FechaEnvio_SK      = S.FechaEnvio_SK,

            D.Cantidad           = S.Quantity,
            D.PrecioUnitario     = S.UnitPrice,
            D.Descuento          = S.Discount,

            D.ImporteBruto       = S.ImporteBruto,
            D.ImporteDescuento   = S.ImporteDescuento,
            D.ImporteNeto        = S.ImporteNeto

    WHEN NOT MATCHED BY TARGET THEN
        INSERT
        (
            Cliente_SK,
            Empleado_SK,
            Producto_SK,
            Transportista_SK,

            FechaPedido_SK,
            FechaRequerida_SK,
            FechaEnvio_SK,

            OrderID,

            Cantidad,
            PrecioUnitario,
            Descuento,

            ImporteBruto,
            ImporteDescuento,
            ImporteNeto
        )

        VALUES
        (
            S.Cliente_SK,
            S.Empleado_SK,
            S.Producto_SK,
            S.Transportista_SK,

            S.FechaPedido_SK,
            S.FechaRequerida_SK,
            S.FechaEnvio_SK,

            S.OrderID,

            S.Quantity,
            S.UnitPrice,
            S.Discount,

            S.ImporteBruto,
            S.ImporteDescuento,
            S.ImporteNeto
        );

END;

