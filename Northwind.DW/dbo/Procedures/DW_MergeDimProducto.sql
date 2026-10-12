CREATE PROCEDURE dbo.DW_MergeDimProducto
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

