[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../tests/Northwind.TestTools.psm1')
$source=$null;$warehouse=$null
$entity='Conexion'
try {
 $source=New-NorthwindTestConnection -Database Northwind_Test -Server $Server
 $warehouse=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
 $control=$warehouse.CreateCommand();$control.CommandTimeout=60
 $control.CommandText=@'
DECLARE @lock int;
EXEC @lock=sys.sp_getapplock @Resource=N'Northwind.Warehouse.Load',
 @LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @lock<0 THROW 52402,'DW ocupado por otra carga; no se modifica staging.',1;
'@
 [void]$control.ExecuteNonQuery()
 $read=$source.CreateCommand();$read.CommandTimeout=60
 $read.CommandText='EXEC dbo.GetDatabaseRowVersion;'
 $cut=[long]$read.ExecuteScalar()
 $entities=@(
  @('Cliente','Customer'),@('Empleado','Employee'),@('Producto','Product'),
  @('Transportista','Shipper'),@('Ventas','Sales'))
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
  $read.Parameters['@start'].Value=$start;$read.Parameters['@end'].Value=$cut
  $read.CommandText="EXEC dbo.Get$($item[1])ChangesByRowVersion @start,@end;"
  if($entity -eq 'Ventas'){
   $read.CommandText=@'
SET NOCOUNT ON;
CREATE TABLE #Sales(OrderID int,ProductID int,CustomerID nchar(5),EmployeeID int,ShipperID int,
 OrderDate datetime,RequiredDate datetime,ShippedDate datetime,UnitPrice decimal(19,4),Quantity smallint,
 Discount decimal(9,6),OrderRowVersion binary(8),OrderDetailRowVersion binary(8));
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion @start,@end;
SELECT * FROM #Sales;
DROP TABLE #Sales;
'@
  }
  $adapter=[Data.SqlClient.SqlDataAdapter]::new($read)
  $rows=[Data.DataTable]::new()
  try{[void]$adapter.Fill($rows)}finally{$adapter.Dispose()}
  # El bloqueo de sesion se retiene desde antes de leer controles hasta terminar las cinco entidades.
  $control.Parameters.Clear()
  $control.CommandText="DELETE FROM std.$entity;"
  [void]$control.ExecuteNonQuery()
  $bulk=[Data.SqlClient.SqlBulkCopy]::new($warehouse,[Data.SqlClient.SqlBulkCopyOptions]::CheckConstraints,$null)
  try {
   $bulk.DestinationTableName="std.$entity";$bulk.BulkCopyTimeout=60
   foreach($column in $rows.Columns){[void]$bulk.ColumnMappings.Add($column.ColumnName,$column.ColumnName)}
   $bulk.WriteToServer($rows)
  }finally{$bulk.Dispose()}
  $control.CommandText='EXEC dbo.DW_ApplyPackage @package,@start,@end;'
  [void]$control.Parameters.Add('@package',[Data.SqlDbType]::NVarChar,100)
  [void]$control.Parameters.Add('@start',[Data.SqlDbType]::BigInt)
  [void]$control.Parameters.Add('@end',[Data.SqlDbType]::BigInt)
  $control.Parameters['@package'].Value=$entity
  $control.Parameters['@start'].Value=$start;$control.Parameters['@end'].Value=$cut
  [void]$control.ExecuteNonQuery()
  [pscustomobject]@{Entidad=$entity;FilasExtraidas=$rows.Rows.Count;Desde=$start;Hasta=$cut;Estado='Confirmado'}
  $rows.Dispose()
 }
}catch{throw "Carga fallida en $entity. $($_.Exception.Message)"}
finally{
 if($null -ne $source){$source.Dispose()}
 # El cierre libera el bloqueo incluso si falla extraccion, staging o aplicacion.
 if($null -ne $warehouse){$warehouse.Dispose()}
}
