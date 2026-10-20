[CmdletBinding()]
param(
    [string]$Server='localhost',
    [ValidatePattern('^Northwind_DW_(?:[A-Za-z0-9]+_)*Test$')]
    [string]$WarehouseDatabase='Northwind_DW_Test'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../tests/Northwind.TestTools.psm1') -Force
$source=$null;$warehouse=$null
$entity='Conexión'
try {
    $source=New-NorthwindTestConnection -Database Northwind_Test -Server $Server
    $warehouse=New-NorthwindTestConnection -Database $WarehouseDatabase -Server $Server

    $control=$warehouse.CreateCommand();$control.CommandTimeout=120
    $control.CommandText=@'
IF DB_NAME()<>@targetDatabase OR NOT EXISTS
 (SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
  AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
    THROW 52010,'Carga rechazada: destino no es la copia marcada.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE name=DB_NAME() AND (is_trustworthy_on=1 OR is_db_chaining_on=1))
    THROW 52017,'Carga rechazada: aislamiento de copia desactivado.',1;
DECLARE @lock int;
EXEC @lock=sys.sp_getapplock @Resource=N'Northwind.Warehouse.Load',
    @LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @lock<0 THROW 52402,'DW ocupado por otra carga; no se modifica staging.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.WarehouseMigrationState
    WHERE MigrationName=N'ReplaceNorthwindStarModel' AND Stage IN(N'Validated',N'SkippedEmpty',N'Cutover'))
    THROW 52420,'Ejecute primero la publicación y la migración del esquema DW.',1;
'@
    [void]$control.Parameters.Add('@targetDatabase',[Data.SqlDbType]::NVarChar,128)
    $control.Parameters['@targetDatabase'].Value=$WarehouseDatabase
    [void]$control.ExecuteNonQuery()

    $read=$source.CreateCommand();$read.CommandTimeout=120
    $read.CommandText='EXEC dbo.GetDatabaseRowVersion;'
    $cut=[long]$read.ExecuteScalar()
    $entities=@(
        @('Cliente','Customer'),
        @('Empleado','Employee'),
        @('Proveedor','Supplier'),
        @('Producto','Product'),
        @('Transportista','Shipper'),
        @('Ventas','Sales')
    )

    foreach($item in $entities){
        $entity=$item[0]
        $control.CommandText=@'
DECLARE @mark binary(8);
EXEC dbo.GetLastPackageRowVersion @package,@mark OUTPUT;
SELECT CONVERT(bigint,@mark);
'@
        $control.Parameters.Clear()
        [void]$control.Parameters.Add('@package',[Data.SqlDbType]::NVarChar,100)
        $control.Parameters['@package'].Value=$entity
        $start=[long]$control.ExecuteScalar()
        if($start -gt $cut){throw "$entity : marca $start posterior al corte $cut; revise el origen sin reiniciar controles."}

        $read.Parameters.Clear()
        [void]$read.Parameters.Add('@start',[Data.SqlDbType]::BigInt)
        [void]$read.Parameters.Add('@end',[Data.SqlDbType]::BigInt)
        $read.Parameters['@start'].Value=$start
        $read.Parameters['@end'].Value=$cut
        $read.CommandText="EXEC dbo.Get$($item[1])ChangesByRowVersion @start,@end;"

        $adapter=[Data.SqlClient.SqlDataAdapter]::new($read)
        $rows=[Data.DataTable]::new()
        try{[void]$adapter.Fill($rows)}finally{$adapter.Dispose()}

        $control.CommandText="DELETE FROM std.$entity;"
        $control.Parameters.Clear()
        [void]$control.ExecuteNonQuery()
        $bulk=[Data.SqlClient.SqlBulkCopy]::new(
            $warehouse,[Data.SqlClient.SqlBulkCopyOptions]::CheckConstraints,$null)
        try {
            $bulk.DestinationTableName="std.$entity"
            $bulk.BulkCopyTimeout=120
            foreach($column in $rows.Columns){
                [void]$bulk.ColumnMappings.Add($column.ColumnName,$column.ColumnName)
            }
            $bulk.WriteToServer($rows)
        }finally{$bulk.Dispose()}

        $control.CommandText='EXEC dbo.DW_ApplyPackage @package,@start,@end;'
        $control.Parameters.Clear()
        [void]$control.Parameters.Add('@package',[Data.SqlDbType]::NVarChar,100)
        [void]$control.Parameters.Add('@start',[Data.SqlDbType]::BigInt)
        [void]$control.Parameters.Add('@end',[Data.SqlDbType]::BigInt)
        $control.Parameters['@package'].Value=$entity
        $control.Parameters['@start'].Value=$start
        $control.Parameters['@end'].Value=$cut
        [void]$control.ExecuteNonQuery()

        [pscustomobject]@{
            Entidad=$entity
            FilasExtraidas=$rows.Rows.Count
            Desde=$start
            Hasta=$cut
            Estado='Confirmado'
        }
        $rows.Dispose()
    }
}catch{
    throw "Carga fallida en $entity. $($_.Exception.Message)"
}finally{
    if($null -ne $source){$source.Dispose()}
    # Cerrar la conexión libera el bloqueo aunque falle extracción, staging o aplicación.
    if($null -ne $warehouse){$warehouse.Dispose()}
}
