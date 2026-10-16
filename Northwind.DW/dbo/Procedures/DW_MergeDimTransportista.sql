CREATE PROCEDURE dbo.DW_MergeDimTransportista
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS(SELECT 1 FROM std.Transportista WHERE ShipperID=0)
        THROW 52408,'Transportista: identidad reservada para desconocido.',1;

    MERGE dbo.DimShipper WITH(HOLDLOCK) AS target
    USING std.Transportista AS source
       ON target.ShipperID=source.ShipperID
    WHEN MATCHED THEN UPDATE SET
        CompanyName=source.CompanyName,
        Phone=source.Phone
    WHEN NOT MATCHED BY TARGET THEN INSERT(ShipperID,CompanyName,Phone)
    VALUES(source.ShipperID,source.CompanyName,source.Phone);
END;
