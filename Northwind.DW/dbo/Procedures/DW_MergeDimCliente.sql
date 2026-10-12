CREATE PROCEDURE dbo.DW_MergeDimCliente
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
      IF EXISTS(SELECT 1 FROM std.Cliente WHERE CustomerID=N'~UNK~') THROW 52408,'Cliente: identidad reservada para desconocido.',1;

    MERGE dbo.Dim_Cliente WITH(HOLDLOCK) AS D
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

      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
      THROW;
    END CATCH;
END;