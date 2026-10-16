-- Solo ejecutar después de procesar OLAP y aprobar la reconciliación del modelo nuevo.
-- Cambie ConfirmCutover a 1 de forma deliberada para autorizar la retirada física.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ConfirmCutover BIT=0;
DECLARE @TargetDatabase SYSNAME=DB_NAME(),
        @MigrationStage NVARCHAR(20);

IF @ConfirmCutover<>1
    THROW 52180,'Retirada detenida: confirme la conciliación y cambie ConfirmCutover a 1.',1;

IF @TargetDatabase<>N'Northwind_DW'
   AND NOT (@TargetDatabase LIKE N'Northwind_DW[_]%[_]Test'
       AND EXISTS(SELECT 1 FROM sys.extended_properties
          WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
            AND CONVERT(NVARCHAR(128),value)=N'Northwind_DW'))
    THROW 52181,'Retirada rechazada: use Northwind_DW o una copia de DW identificada.',1;

IF OBJECT_ID(N'dbo.WarehouseMigrationState',N'U') IS NULL
   OR OBJECT_ID(N'dbo.FactSales',N'U') IS NULL
    THROW 52182,'Retirada detenida: el modelo DW nuevo no está publicado.',1;

SELECT @MigrationStage=Stage
FROM dbo.WarehouseMigrationState
WHERE MigrationName=N'ReplaceNorthwindStarModel' AND SchemaVersion=1;
IF @MigrationStage=N'Cutover'
BEGIN
    PRINT N'El legado ya fue retirado; no se aplicaron cambios.';
    RETURN;
END;
IF @MigrationStage IS NULL OR @MigrationStage NOT IN(N'Validated',N'SkippedEmpty')
    THROW 52183,'Retirada detenida: la migración no llegó a Validated o SkippedEmpty.',1;

IF (SELECT COUNT(*) FROM dbo.PackageConfig)<>6
   OR EXISTS(SELECT PackageName FROM dbo.PackageConfig
        WHERE PackageName IN(N'Cliente',N'Empleado',N'Proveedor',N'Producto',N'Transportista',N'Ventas')
        GROUP BY PackageName HAVING COUNT(*)<>1)
    THROW 52184,'Retirada detenida: los seis procesos no están registrados en PackageConfig.',1;
IF EXISTS(SELECT 1 FROM dbo.PackageConfig WHERE LastSuccessfulLoad IS NULL)
    THROW 52186,'Retirada detenida: complete y concilie una carga de los seis procesos.',1;

IF EXISTS(SELECT OrderID FROM dbo.FactSales
          GROUP BY OrderID
          HAVING COUNT(DISTINCT Freight)>1 OR (COUNT(Freight)>0 AND COUNT(Freight)<COUNT(*)))
    THROW 52185,'Retirada detenida: el Freight no coincide entre las líneas de algún pedido.',1;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.DW_LoadDimTiempo',N'P') IS NOT NULL
        DROP PROCEDURE dbo.DW_LoadDimTiempo;

    IF OBJECT_ID(N'dbo.Fact_Ventas',N'U') IS NOT NULL
        DROP TABLE dbo.Fact_Ventas;
    IF OBJECT_ID(N'dbo.Dim_Tiempo',N'U') IS NOT NULL
        DROP TABLE dbo.Dim_Tiempo;
    IF OBJECT_ID(N'dbo.Dim_Producto',N'U') IS NOT NULL
        DROP TABLE dbo.Dim_Producto;
    IF OBJECT_ID(N'dbo.Dim_Cliente',N'U') IS NOT NULL
        DROP TABLE dbo.Dim_Cliente;
    IF OBJECT_ID(N'dbo.Dim_Empleado',N'U') IS NOT NULL
        DROP TABLE dbo.Dim_Empleado;
    IF OBJECT_ID(N'dbo.Dim_Transportista',N'U') IS NOT NULL
        DROP TABLE dbo.Dim_Transportista;

    IF COL_LENGTH(N'std.Producto',N'SupplierName') IS NOT NULL
        ALTER TABLE std.Producto DROP COLUMN SupplierName;
    IF COL_LENGTH(N'std.Producto',N'SupplierCountry') IS NOT NULL
        ALTER TABLE std.Producto DROP COLUMN SupplierCountry;
    IF COL_LENGTH(N'std.Producto',N'SupplierRowVersion') IS NOT NULL
        ALTER TABLE std.Producto DROP COLUMN SupplierRowVersion;

    UPDATE dbo.WarehouseMigrationState
    SET Stage=N'Cutover',UpdatedAt=SYSUTCDATETIME()
    WHERE MigrationName=N'ReplaceNorthwindStarModel' AND SchemaVersion=1;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

PRINT N'Cutover registrado; objetos heredados retirados después de la confirmación.';
