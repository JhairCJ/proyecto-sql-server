USE Northwind_DW;
GO

CREATE OR ALTER PROCEDURE dbo.GetLastPackageRowVersion
    @PackageName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ISNULL
        (
            CONVERT(BIGINT, LastRowVersion),
            0
        ) AS LastRowVersion

    FROM dbo.PackageConfig

    WHERE PackageName = @PackageName;
END;
GO