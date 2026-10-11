CREATE OR ALTER PROCEDURE dbo.UpdateLastPackageRowVersion
    @PackageName NVARCHAR(100),
    @LastRowVersion BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.PackageConfig
    SET
        LastRowVersion =
            CONVERT(BINARY(8), @LastRowVersion),

        LastSuccessfulLoad =
            SYSDATETIME()

    WHERE PackageName = @PackageName;


    /* Por seguridad, si no existe el PackageName,
       lo creamos. */

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
            CONVERT(BINARY(8), @LastRowVersion),
            SYSDATETIME()
        );

    END;

END;
GO