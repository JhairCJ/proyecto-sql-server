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