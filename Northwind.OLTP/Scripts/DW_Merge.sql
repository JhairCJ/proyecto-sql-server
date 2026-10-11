-- CREACION DEL DW MERGE Dim_Cliente
USE Northwind_DW;
GO

CREATE OR ALTER PROCEDURE dbo.DW_MergeDimCliente
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.Dim_Cliente AS D
    USING std.Cliente AS S
        ON D.CustomerID = S.CustomerID

    WHEN MATCHED THEN
        UPDATE SET
            D.NombreEmpresa  = S.CompanyName,
            D.NombreContacto = S.ContactName,
            D.TituloContacto = S.ContactTitle,
            D.Ciudad         = S.City,
            D.Region         = S.Region,
            D.CodigoPostal   = S.PostalCode,
            D.Pais           = S.Country

    WHEN NOT MATCHED BY TARGET THEN
        INSERT
        (
            CustomerID,
            NombreEmpresa,
            NombreContacto,
            TituloContacto,
            Ciudad,
            Region,
            CodigoPostal,
            Pais
        )
        VALUES
        (
            S.CustomerID,
            S.CompanyName,
            S.ContactName,
            S.ContactTitle,
            S.City,
            S.Region,
            S.PostalCode,
            S.Country
        );

END;
GO


---- CREACION DEL DW MERGE Dim_Empleado

CREATE OR ALTER PROCEDURE dbo.DW_MergeDimEmpleado
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.Dim_Empleado AS D
    USING
    (
        SELECT
            EmployeeID,
            CONCAT(FirstName, N' ', LastName) AS NombreCompleto,
            Title,
            City,
            Region,
            Country,
            ReportsTo,
            SupervisorName
        FROM std.Empleado
    ) AS S

        ON D.EmployeeID = S.EmployeeID

    WHEN MATCHED THEN
        UPDATE SET
            D.NombreCompleto   = S.NombreCompleto,
            D.Titulo           = S.Title,
            D.Ciudad           = S.City,
            D.Region           = S.Region,
            D.Pais             = S.Country,
            D.ReportsTo        = S.ReportsTo,
            D.NombreSupervisor = S.SupervisorName

    WHEN NOT MATCHED BY TARGET THEN
        INSERT
        (
            EmployeeID,
            NombreCompleto,
            Titulo,
            Ciudad,
            Region,
            Pais,
            ReportsTo,
            NombreSupervisor
        )
        VALUES
        (
            S.EmployeeID,
            S.NombreCompleto,
            S.Title,
            S.City,
            S.Region,
            S.Country,
            S.ReportsTo,
            S.SupervisorName
        );

END;
GO

---- CREACION DEL DW MERGE Dim_Producto

CREATE OR ALTER PROCEDURE dbo.DW_MergeDimProducto
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.Dim_Producto AS D
    USING std.Producto AS S

        ON D.ProductID = S.ProductID

    WHEN MATCHED THEN
        UPDATE SET
            D.NombreProducto     = S.ProductName,
            D.CantidadPorUnidad  = S.QuantityPerUnit,

            D.CategoryID         = S.CategoryID,
            D.Categoria          = S.CategoryName,

            D.SupplierID         = S.SupplierID,
            D.Proveedor          = S.SupplierName,
            D.PaisProveedor      = S.SupplierCountry,

            D.Descontinuado      = S.Discontinued

    WHEN NOT MATCHED BY TARGET THEN
        INSERT
        (
            ProductID,
            NombreProducto,
            CantidadPorUnidad,

            CategoryID,
            Categoria,

            SupplierID,
            Proveedor,
            PaisProveedor,

            Descontinuado
        )
        VALUES
        (
            S.ProductID,
            S.ProductName,
            S.QuantityPerUnit,

            S.CategoryID,
            S.CategoryName,

            S.SupplierID,
            S.SupplierName,
            S.SupplierCountry,

            S.Discontinued
        );

END;
GO

---- CREACION DEL DW MERGE DimTransportista

CREATE OR ALTER PROCEDURE dbo.DW_MergeDimTransportista
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.Dim_Transportista AS D
    USING std.Transportista AS S

        ON D.ShipperID = S.ShipperID

    WHEN MATCHED THEN
        UPDATE SET
            D.NombreEmpresa = S.CompanyName,
            D.Telefono      = S.Phone

    WHEN NOT MATCHED BY TARGET THEN
        INSERT
        (
            ShipperID,
            NombreEmpresa,
            Telefono
        )
        VALUES
        (
            S.ShipperID,
            S.CompanyName,
            S.Phone
        );

END;
GO

-- CREACION DEL DW MERGE Dim_Tiempo

CREATE OR ALTER PROCEDURE dbo.DW_LoadDimTiempo
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Fechas AS
    (
        SELECT CAST(OrderDate AS DATE) AS Fecha
        FROM std.Ventas
        WHERE OrderDate IS NOT NULL

        UNION

        SELECT CAST(RequiredDate AS DATE)
        FROM std.Ventas
        WHERE RequiredDate IS NOT NULL

        UNION

        SELECT CAST(ShippedDate AS DATE)
        FROM std.Ventas
        WHERE ShippedDate IS NOT NULL
    )

    INSERT INTO dbo.Dim_Tiempo
    (
        Tiempo_SK,
        Fecha,

        Dia,
        NombreDia,

        Mes,
        NombreMes,

        Trimestre,
        Anio
    )

    SELECT
        YEAR(F.Fecha) * 10000
        + MONTH(F.Fecha) * 100
        + DAY(F.Fecha) AS Tiempo_SK,

        F.Fecha,

        DAY(F.Fecha),
        DATENAME(WEEKDAY, F.Fecha),

        MONTH(F.Fecha),
        DATENAME(MONTH, F.Fecha),

        DATEPART(QUARTER, F.Fecha),
        YEAR(F.Fecha)

    FROM Fechas F

    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.Dim_Tiempo DT
        WHERE DT.Fecha = F.Fecha
    );

END;
GO

-- CREACION DEL DW MERGE Fact_Ventas

CREATE OR ALTER PROCEDURE dbo.DW_MergeFactVentas
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
GO