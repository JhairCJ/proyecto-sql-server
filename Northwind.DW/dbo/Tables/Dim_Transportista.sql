CREATE TABLE dbo.Dim_Transportista (
    Transportista_SK INT IDENTITY(1,1) NOT NULL,
    ShipperID INT NOT NULL,

    NombreEmpresa NVARCHAR(40),
    Telefono NVARCHAR(24),
    CONSTRAINT PK_Dim_Transportista PRIMARY KEY (Transportista_SK),
    CONSTRAINT UQ_Dim_Transportista_ShipperID UNIQUE (ShipperID)
);
