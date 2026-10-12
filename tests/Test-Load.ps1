[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1')
$loader=Join-Path $PSScriptRoot '../scripts/Load-NorthwindWarehouse.ps1'
function Read-LoadedState([switch]$WithDates){
 $dateColumn=if($WithDates){',LastSuccessfulLoad'}else{''}
 $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @"
SELECT * FROM dbo.Dim_Cliente ORDER BY Cliente_SK;
SELECT * FROM dbo.Dim_Empleado ORDER BY Empleado_SK;
SELECT * FROM dbo.Dim_Producto ORDER BY Producto_SK;
SELECT * FROM dbo.Dim_Transportista ORDER BY Transportista_SK;
SELECT * FROM dbo.Dim_Tiempo ORDER BY Tiempo_SK;
SELECT * FROM dbo.Fact_Ventas ORDER BY Venta_SK;
SELECT PackageName,LastRowVersion$dateColumn FROM dbo.PackageConfig ORDER BY PackageName;
SELECT * FROM std.Cliente ORDER BY CustomerID;
SELECT * FROM std.Empleado ORDER BY EmployeeID;
SELECT * FROM std.Producto ORDER BY ProductID;
SELECT * FROM std.Transportista ORDER BY ShipperID;
SELECT * FROM std.Ventas ORDER BY OrderID,ProductID;
"@
 return $state.GetXml()
}
# Dejar staging vacio despues de una repeticion correcta antes de comparar.
& $loader -Server $Server | Out-Null
$before=Read-LoadedState
& $loader -Server $Server | Out-Null
if((Read-LoadedState) -cne $before){throw 'Repeticion modifico claves, hechos, importes o marcas.'}
'PASS: repeticion real sin cambios conserva todas las claves, atributos, medidas y marcas'

$lock=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
try{
 $cmd=$lock.CreateCommand();$cmd.CommandText=@'
DECLARE @result int;
EXEC @result=sys.sp_getapplock @Resource=N'Northwind.Warehouse.Load',
 @LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @result<0 THROW 52402,'No se pudo adquirir bloqueo de prueba.',1;
'@
 [void]$cmd.ExecuteNonQuery();$cmd.Dispose()
 $before=Read-LoadedState -WithDates
 $rejected=$false
 try{& $loader -Server $Server | Out-Null}
 catch{if($_.Exception.Message -notlike '*DW ocupado*'){throw};$rejected=$true}
 if(-not $rejected -or (Read-LoadedState -WithDates) -cne $before){throw 'Competencia no rechazada antes de modificar staging.'}
 'PASS: segundo cargador rechazado antes de modificar staging, datos o controles'
}finally{$lock.Dispose()}

$source=New-NorthwindTestConnection -Database Northwind_Test -Server $Server
$admin=$null;$created=$false;$changed=$false
try{
 $read=$source.CreateCommand();$read.CommandText="SELECT City FROM dbo.Customers WHERE CustomerID=N'VINET';"
 $oldCity=$read.ExecuteScalar();$read.Dispose()
 $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
 $builder['Data Source']=$Server;$builder['Initial Catalog']='Northwind_DW_Test'
 $builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
 $admin=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString);$admin.Open()
 $cmd=$admin.CreateCommand();$cmd.CommandText=@'
IF DB_NAME()<>N'Northwind_DW_Test' OR NOT EXISTS(SELECT 1 FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 51002,'Destino de inyeccion no marcado.',1;
IF OBJECT_ID(N'dbo.NorthwindTestFailMark',N'TR') IS NOT NULL THROW 52521,'Trigger de prueba ya existente.',1;
'@
 [void]$cmd.ExecuteNonQuery()
 $cmd.CommandText=@'
CREATE TRIGGER dbo.NorthwindTestFailMark ON dbo.PackageConfig AFTER UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted WHERE PackageName=N'Cliente')
  THROW 52520,'Fallo inyectado al guardar marca de Cliente.',1;
END;
'@
 [void]$cmd.ExecuteNonQuery();$created=$true
 $write=$source.CreateCommand()
 $write.CommandText="SET XACT_ABORT ON;BEGIN TRANSACTION;UPDATE dbo.Customers SET City=N'Carga prueba' WHERE CustomerID=N'VINET';COMMIT;"
 [void]$write.ExecuteNonQuery();$changed=$true;$write.Dispose()
 $before=Read-LoadedState -WithDates
 $rejected=$false
 try{& $loader -Server $Server | Out-Null}
 catch{if($_.Exception.Message -notlike '*Fallo inyectado al guardar marca*'){throw};$rejected=$true}
 # Staging es reconstruible y ahora contiene la fila pendiente; comparar finales/control.
 $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
SELECT City=Ciudad FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET';
SELECT PackageName,LastRowVersion,LastSuccessfulLoad FROM dbo.PackageConfig ORDER BY PackageName;
'@
 $beforeData=[Data.DataSet]::new();$beforeData.ReadXml([IO.StringReader]::new($before)) | Out-Null
 if([string]$state.Tables[0].Rows[0].City -ne [string]$oldCity){throw 'Fallo de marca confirmo atributos finales.'}
 foreach($row in $state.Tables[1].Rows){
  $prior=$beforeData.Tables[6].Select("PackageName='$($row.PackageName)'")[0]
  if(([Convert]::ToBase64String($row.LastRowVersion) -ne [string]$prior.LastRowVersion) -or ($row.LastSuccessfulLoad -ne [datetime]$prior.LastSuccessfulLoad)){throw 'Fallo adelanto marca/fecha o continuo entidades dependientes.'}
 }
 if(-not $rejected){throw 'El cargador no fallo ante el trigger.'}
 $cmd.CommandText='DROP TRIGGER dbo.NorthwindTestFailMark;';[void]$cmd.ExecuteNonQuery();$created=$false
 & $loader -Server $Server | Out-Null
 $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
IF (SELECT COUNT(*) FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>1
 OR (SELECT Ciudad FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>N'Carga prueba'
 OR (SELECT COUNT(*) FROM dbo.Fact_Ventas)<>2155
 THROW 52523,'Reintento incremental incorrecto.',1;
SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET';
'@
 $priorSk=$beforeData.Tables[0].Select("CustomerID='VINET'")[0].Cliente_SK
 if($state.Tables[0].Rows[0].Cliente_SK -ne $priorSk){throw 'Reintento cambio la SK.'}
 'PASS: fallo real conserva finales y cinco controles; reintento extrae cambio pendiente y conserva SK'
}finally{
 if($created -and $null -ne $admin -and $admin.State -eq 'Open'){
  $cleanup=$admin.CreateCommand();$cleanup.CommandText='DROP TRIGGER dbo.NorthwindTestFailMark;'
  try{[void]$cleanup.ExecuteNonQuery()}finally{$cleanup.Dispose()}
 }
 if($null -ne $admin){$admin.Dispose()}
 if($changed){
  $restore=$source.CreateCommand()
  $restore.CommandText="SET XACT_ABORT ON;BEGIN TRANSACTION;UPDATE dbo.Customers SET City=@city WHERE CustomerID=N'VINET';COMMIT;"
  [void]$restore.Parameters.Add('@city',[Data.SqlDbType]::NVarChar,15);$restore.Parameters['@city'].Value=$oldCity
  try{[void]$restore.ExecuteNonQuery()}finally{$restore.Dispose()}
 }
 $source.Dispose()
 if($changed){& $loader -Server $Server | Out-Null}
}
& (Join-Path $PSScriptRoot '../scripts/Compare-NorthwindWarehouse.ps1') -Server $Server
'PASS: ciudad original restaurada en copia y DW; reconciliacion completa; originales no usados como fixtures'
