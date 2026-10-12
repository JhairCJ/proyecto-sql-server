CREATE PROCEDURE dbo.DW_MergeDimTransportista
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

