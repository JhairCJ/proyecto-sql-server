CREATE PROCEDURE dbo.DW_MergeDimCliente
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS(SELECT 1 FROM std.Cliente WHERE CustomerID=N'~UNK~')
        THROW 52408,'Cliente: identidad reservada para desconocido.',1;

    MERGE dbo.DimCustomer WITH(HOLDLOCK) AS target
    USING std.Cliente AS source
       ON target.CustomerID=source.CustomerID
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
        Fax=source.Fax
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (CustomerID,CompanyName,ContactName,ContactTitle,[Address],City,Region,PostalCode,Country,Phone,Fax)
    VALUES
        (source.CustomerID,source.CompanyName,source.ContactName,source.ContactTitle,source.[Address],
         source.City,source.Region,source.PostalCode,source.Country,source.Phone,source.Fax);
END;
