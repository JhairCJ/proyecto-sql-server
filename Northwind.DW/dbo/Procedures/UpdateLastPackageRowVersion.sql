CREATE PROCEDURE dbo.UpdateLastPackageRowVersion
 @PackageName nvarchar(100), @LastRowVersion binary(8), @ExpectedLastRowVersion binary(8)
AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT=0
  THROW 52412,'El avance requiere la transaccion de DW_ApplyPackage.',1;
 DECLARE @current binary(8);
 EXEC dbo.GetLastPackageRowVersion @PackageName,@current OUTPUT;
 IF @LastRowVersion IS NULL OR @ExpectedLastRowVersion IS NULL
  OR @LastRowVersion>0x7FFFFFFFFFFFFFFF OR @LastRowVersion<@current
  OR @ExpectedLastRowVersion<>@current
  THROW 52413,'Avance incompatible o control modificado.',1;
 UPDATE dbo.PackageConfig SET LastRowVersion=@LastRowVersion,LastSuccessfulLoad=SYSDATETIME()
 WHERE PackageName=@PackageName AND LastRowVersion=@ExpectedLastRowVersion;
 IF @@ROWCOUNT<>1 THROW 52413,'No se pudo confirmar el avance del proceso.',1;
END;
