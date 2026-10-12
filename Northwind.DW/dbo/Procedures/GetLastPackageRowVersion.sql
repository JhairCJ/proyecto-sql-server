CREATE PROCEDURE dbo.GetLastPackageRowVersion
 @PackageName nvarchar(100), @LastRowVersion binary(8) OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 SET @LastRowVersion=NULL;
 IF @PackageName IS NULL OR @PackageName NOT IN(N'Cliente',N'Empleado',N'Producto',N'Transportista',N'Ventas')
  THROW 52409,'Proceso desconocido: use Cliente, Empleado, Producto, Transportista o Ventas.',1;
 SELECT @LastRowVersion=LastRowVersion FROM dbo.PackageConfig WHERE PackageName=@PackageName;
 IF @LastRowVersion IS NULL THROW 52410,'Falta el control del proceso: publique el DW antes de cargar.',1;
 IF @LastRowVersion>0x7FFFFFFFFFFFFFFF
  THROW 52411,'Marca no representable como BIGINT: carga detenida.',1;
 DECLARE @empty bit=0;
 IF @PackageName=N'Cliente' AND NOT EXISTS(SELECT 1 FROM dbo.Dim_Cliente WHERE Cliente_SK<>0) SET @empty=1;
 IF @PackageName=N'Empleado' AND NOT EXISTS(SELECT 1 FROM dbo.Dim_Empleado WHERE Empleado_SK<>0) SET @empty=1;
 IF @PackageName=N'Producto' AND NOT EXISTS(SELECT 1 FROM dbo.Dim_Producto) SET @empty=1;
 IF @PackageName=N'Transportista' AND NOT EXISTS(SELECT 1 FROM dbo.Dim_Transportista) SET @empty=1;
 IF @PackageName=N'Ventas' AND NOT EXISTS(SELECT 1 FROM dbo.Fact_Ventas) SET @empty=1;
 IF @empty=1 AND @LastRowVersion>0x0000000000000000
  THROW 52404,'Destino comercial vacio con marca avanzada: requiere reconstruccion explicita.',1;
END;
