CREATE PROCEDURE dbo.DW_MergeDimProducto
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS
    (
        SELECT 1 FROM std.Producto productSource
        WHERE productSource.SupplierID IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM dbo.DimSupplier supplier WHERE supplier.SupplierID=productSource.SupplierID)
    )
        THROW 52415,'Producto: SupplierID no existe en DimSupplier; cargue proveedores antes de productos.',1;

    MERGE dbo.DimProduct WITH(HOLDLOCK) AS target
    USING std.Producto AS source
       ON target.ProductID=source.ProductID
    WHEN MATCHED THEN UPDATE SET
        ProductName=source.ProductName,
        CategoryID=source.CategoryID,
        CategoryName=source.CategoryName,
        CategoryDescription=source.CategoryDescription,
        QuantityPerUnit=source.QuantityPerUnit,
        UnitsInStock=source.UnitsInStock,
        UnitsOnOrder=source.UnitsOnOrder,
        ReorderLevel=source.ReorderLevel,
        Discontinued=source.Discontinued
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (ProductID,ProductName,CategoryID,CategoryName,CategoryDescription,QuantityPerUnit,
         UnitsInStock,UnitsOnOrder,ReorderLevel,Discontinued)
    VALUES
        (source.ProductID,source.ProductName,source.CategoryID,source.CategoryName,
         source.CategoryDescription,source.QuantityPerUnit,source.UnitsInStock,
         source.UnitsOnOrder,source.ReorderLevel,source.Discontinued);
END;
