CREATE OR ALTER PROCEDURE dbo.UpdateLastPackageRowVersion
    @PackageName NVARCHAR(100),
    @LastRowVersion BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.PackageConfig
    SET
        LastRowVersion = @LastRowVersion,
        LastSuccessfulLoad = SYSDATETIME()
    WHERE PackageName = @PackageName;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.PackageConfig
        (
            PackageName,
            LastRowVersion,
            LastSuccessfulLoad
        )
        VALUES
        (
            @PackageName,
            @LastRowVersion,
            SYSDATETIME()
        );
    END;
END;
GO