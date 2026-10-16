CREATE TABLE dbo.DimGeography
(
    GeographyKey INT IDENTITY(1,1) NOT NULL,
    ShipAddress NVARCHAR(60) NULL,
    ShipCity NVARCHAR(15) NULL,
    ShipRegion NVARCHAR(15) NULL,
    ShipPostalCode NVARCHAR(10) NULL,
    ShipCountry NVARCHAR(15) NULL,
    CONSTRAINT PK_DimGeography PRIMARY KEY (GeographyKey),
    CONSTRAINT UQ_DimGeography_Destination UNIQUE
        (ShipAddress, ShipCity, ShipRegion, ShipPostalCode, ShipCountry)
);
