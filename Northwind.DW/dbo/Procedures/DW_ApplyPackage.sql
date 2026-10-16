CREATE PROCEDURE dbo.DW_ApplyPackage
    @PackageName NVARCHAR(100),
    @StartRow BIGINT,
    @EndRow BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @StartRow IS NULL OR @EndRow IS NULL OR @StartRow<0 OR @EndRow<@StartRow
        THROW 52401,'Marca incompatible con el corte del origen: revise origen y control sin reiniciar marcas.',1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @lock INT;
        EXEC @lock=sys.sp_getapplock
            @Resource=N'Northwind.Warehouse.Load',
            @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=0;
        IF @lock<0 THROW 52402,'DW ocupado por otra carga.',1;

        DECLARE @current BINARY(8),@cut BINARY(8)=CONVERT(BINARY(8),@EndRow);
        EXEC dbo.GetLastPackageRowVersion @PackageName,@current OUTPUT;
        IF @current<>CONVERT(BINARY(8),@StartRow)
            THROW 52403,'La marca cambió desde la extracción; reconstruya staging y reintente.',1;

        IF (@PackageName=N'Cliente' AND EXISTS
            (SELECT 1 FROM std.Cliente WHERE SourceRowVersion IS NULL OR SourceRowVersion>@cut))
         OR (@PackageName=N'Empleado' AND EXISTS
            (SELECT 1 FROM std.Empleado WHERE SourceRowVersion IS NULL OR SourceRowVersion>@cut))
         OR (@PackageName=N'Producto' AND EXISTS
            (SELECT 1 FROM std.Producto WHERE ProductRowVersion IS NULL OR ProductRowVersion>@cut OR CategoryRowVersion>@cut))
         OR (@PackageName=N'Transportista' AND EXISTS
            (SELECT 1 FROM std.Transportista WHERE SourceRowVersion IS NULL OR SourceRowVersion>@cut))
         OR (@PackageName=N'Proveedor' AND EXISTS
            (SELECT 1 FROM std.Proveedor WHERE SourceRowVersion IS NULL OR SourceRowVersion>@cut))
         OR (@PackageName=N'Ventas' AND EXISTS
            (SELECT 1 FROM std.Ventas WHERE OrderRowVersion IS NULL OR OrderDetailRowVersion IS NULL
               OR ProductRowVersion IS NULL OR OrderRowVersion>@cut OR OrderDetailRowVersion>@cut OR ProductRowVersion>@cut))
            THROW 52405,'Staging contiene marcas ausentes o posteriores al corte.',1;

        IF @PackageName=N'Cliente' EXEC dbo.DW_MergeDimCliente;
        ELSE IF @PackageName=N'Empleado' EXEC dbo.DW_MergeDimEmpleado;
        ELSE IF @PackageName=N'Proveedor' EXEC dbo.DW_MergeDimProveedor;
        ELSE IF @PackageName=N'Producto' EXEC dbo.DW_MergeDimProducto;
        ELSE IF @PackageName=N'Transportista' EXEC dbo.DW_MergeDimTransportista;
        ELSE IF @PackageName=N'Ventas' EXEC dbo.DW_MergeFactVentas;

        EXEC dbo.UpdateLastPackageRowVersion @PackageName,@cut,@current;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
