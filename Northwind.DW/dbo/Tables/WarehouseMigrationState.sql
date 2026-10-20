CREATE TABLE dbo.WarehouseMigrationState
(
    MigrationName NVARCHAR(80) NOT NULL,
    SchemaVersion SMALLINT NOT NULL,
    Stage NVARCHAR(20) NOT NULL,
    SourceDatabase SYSNAME NOT NULL,
    SourceCut BINARY(8) NOT NULL,
    UpdatedAt DATETIME2(0) NOT NULL
        CONSTRAINT DF_WarehouseMigrationState_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_WarehouseMigrationState PRIMARY KEY (MigrationName),
    CONSTRAINT CK_WarehouseMigrationState_SchemaVersion CHECK (SchemaVersion>0),
    CONSTRAINT CK_WarehouseMigrationState_Stage CHECK
        (Stage IN (N'Validated',N'SkippedEmpty',N'Cutover'))
);
