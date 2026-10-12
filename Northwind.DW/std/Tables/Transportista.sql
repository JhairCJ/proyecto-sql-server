CREATE TABLE std.Transportista
(
    ShipperID INT NOT NULL,

    CompanyName NVARCHAR(40) NULL,
    Phone NVARCHAR(24) NULL,

    SourceRowVersion BINARY(8) NULL,

    CONSTRAINT PK_STD_Transportista
        PRIMARY KEY (ShipperID)
);
