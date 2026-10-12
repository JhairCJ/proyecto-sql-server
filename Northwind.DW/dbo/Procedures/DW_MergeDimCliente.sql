CREATE PROCEDURE dbo.DW_MergeDimCliente
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

