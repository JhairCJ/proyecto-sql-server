CREATE PROCEDURE dbo.DW_MergeDimTransportista
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


    MERGE dbo.Dim_Transportista WITH(HOLDLOCK) AS D
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

      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
      THROW;
    END CATCH;
END;