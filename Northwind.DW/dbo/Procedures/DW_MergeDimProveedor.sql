CREATE PROCEDURE dbo.DW_MergeDimProveedor
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS(SELECT 1 FROM std.Proveedor WHERE SupplierID=0)
        THROW 52408,'Proveedor: identidad reservada para desconocido.',1;

    MERGE dbo.DimSupplier WITH(HOLDLOCK) AS target
    USING std.Proveedor AS source
       ON target.SupplierID=source.SupplierID
    WHEN MATCHED THEN UPDATE SET
        CompanyName=source.CompanyName,
        ContactName=source.ContactName,
        ContactTitle=source.ContactTitle,
        [Address]=source.[Address],
        City=source.City,
        Region=source.Region,
        PostalCode=source.PostalCode,
        Country=source.Country,
        Phone=source.Phone,
        Fax=source.Fax,
        HomePage=source.HomePage
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (SupplierID,CompanyName,ContactName,ContactTitle,[Address],City,Region,PostalCode,Country,Phone,Fax,HomePage)
    VALUES
        (source.SupplierID,source.CompanyName,source.ContactName,source.ContactTitle,source.[Address],
         source.City,source.Region,source.PostalCode,source.Country,source.Phone,source.Fax,source.HomePage);
END;
