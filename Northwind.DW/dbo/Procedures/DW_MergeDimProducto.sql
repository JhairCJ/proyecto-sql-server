CREATE PROCEDURE dbo.DW_MergeDimProducto
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
      BEGIN TRANSACTION;
      DECLARE @lock int;
      EXEC @lock=sys.sp_getapplock @Resource=N'Northwind.Warehouse.Load',
       @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=0;
      IF @lock<0 THROW 52402,'DW ocupado por otra carga.',1;


    MERGE dbo.Dim_Producto WITH(HOLDLOCK) AS D
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

      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
      THROW;
    END CATCH;
END;