CREATE PROCEDURE dbo.DW_MergeDimEmpleado
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
      IF EXISTS(SELECT 1 FROM std.Empleado WHERE EmployeeID=0) THROW 52408,'Empleado: identidad reservada para desconocido.',1;

    MERGE dbo.Dim_Empleado WITH(HOLDLOCK) AS D
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

      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
      THROW;
    END CATCH;
END;