CREATE PROCEDURE dbo.GetLastPackageRowVersion
    @PackageName NVARCHAR(100),
    @LastRowVersion BINARY(8) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        @LastRowVersion = LastRowVersion
    FROM dbo.PackageConfig
    WHERE PackageName = @PackageName;

    IF @LastRowVersion IS NULL
        SET @LastRowVersion = 0x0000000000000000;
END;

