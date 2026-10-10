
CREATE TABLE dbo.PackageConfig
(
    PackageName NVARCHAR(100) NOT NULL,

    LastRowVersion BINARY(8) NOT NULL
        CONSTRAINT DF_PackageConfig_RowVersion
        DEFAULT (0x0000000000000000),

    LastSuccessfulLoad DATETIME2 NULL,

    CONSTRAINT PK_PackageConfig
        PRIMARY KEY (PackageName)
);
GO

INSERT INTO dbo.PackageConfig
(
    PackageName,
    LastRowVersion
)
VALUES
(N'Cliente',       0x0000000000000000),
(N'Empleado',      0x0000000000000000),
(N'Producto',      0x0000000000000000),
(N'Transportista', 0x0000000000000000),
(N'Ventas',        0x0000000000000000);
GO
