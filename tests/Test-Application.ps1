[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1')
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1')
$snapshot=Invoke-NorthwindTestSql -Database Northwind_Test -Server $Server -Sql @'
DECLARE @cut TABLE(DBTS bigint); INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
EXEC dbo.GetCustomerChangesByRowVersion 0,@end;
EXEC dbo.GetEmployeeChangesByRowVersion 0,@end;
EXEC dbo.GetProductChangesByRowVersion 0,@end;
EXEC dbo.GetShipperChangesByRowVersion 0,@end;
CREATE TABLE #Sales(OrderID int,ProductID int,CustomerID nchar(5),EmployeeID int,ShipperID int,
 OrderDate datetime,RequiredDate datetime,ShippedDate datetime,UnitPrice decimal(19,4),Quantity smallint,
 Discount decimal(9,6),OrderRowVersion binary(8),OrderDetailRowVersion binary(8));
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion 0,@end;
SELECT * FROM #Sales;
SELECT @end AS Cut;
'@
$cut=[long]$snapshot.Tables[5].Rows[0].Cut

function Copy-Staging($connection,$transaction) {
 $cmd=$connection.CreateCommand();$cmd.Transaction=$transaction
 $cmd.CommandText='DELETE std.Cliente;DELETE std.Empleado;DELETE std.Producto;DELETE std.Transportista;DELETE std.Ventas;'
 try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}
 $tables=@('std.Cliente','std.Empleado','std.Producto','std.Transportista','std.Ventas')
 for($i=0;$i -lt 5;$i++){
  $bulk=[Data.SqlClient.SqlBulkCopy]::new($connection,[Data.SqlClient.SqlBulkCopyOptions]::CheckConstraints,$transaction)
  try{
   $bulk.DestinationTableName=$tables[$i]
   foreach($column in $snapshot.Tables[$i].Columns){[void]$bulk.ColumnMappings.Add($column.ColumnName,$column.ColumnName)}
   $bulk.WriteToServer($snapshot.Tables[$i])
  }finally{$bulk.Dispose()}
 }
}
function Read-State {
 $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
SELECT PackageName,LastRowVersion,LastSuccessfulLoad FROM dbo.PackageConfig ORDER BY PackageName;
SELECT (SELECT COUNT(*) FROM dbo.Dim_Cliente) AS Clientes,
 (SELECT COUNT(*) FROM dbo.Dim_Empleado) AS Empleados,
 (SELECT COUNT(*) FROM dbo.Dim_Producto) AS Productos,
 (SELECT COUNT(*) FROM dbo.Dim_Transportista) AS Transportistas,
 (SELECT COUNT(*) FROM dbo.Dim_Tiempo) AS Fechas,
 (SELECT COUNT(*) FROM dbo.Fact_Ventas) AS Ventas,
 (SELECT SUM(ImporteNeto) FROM dbo.Fact_Ventas) AS Neto;
SELECT CustomerID,Cliente_SK,Ciudad FROM dbo.Dim_Cliente ORDER BY CustomerID;
'@
 return $state.GetXml()
}
function Invoke-Failure([string]$Sql,[int]$ErrorNumber) {
 $before=Read-State
 $dw=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
 $tx=$null
 try{
  $tx=$dw.BeginTransaction();Copy-Staging $dw $tx
  $cmd=$dw.CreateCommand();$cmd.Transaction=$tx;$cmd.CommandTimeout=60
  $cmd.CommandText=$Sql;[void]$cmd.Parameters.AddWithValue('@cut',$cut)
  $caught=$false
  try{[void]$cmd.ExecuteNonQuery()}
  catch{
   $ex=$_.Exception
   while($null -ne $ex -and $ex -isnot [Data.SqlClient.SqlException]){$ex=$ex.InnerException}
   if($null -eq $ex -or $ex.Number -ne $ErrorNumber){throw}
   $caught=$true
  }finally{$cmd.Dispose()}
  if(-not $caught){throw "Se acepto el caso invalido $ErrorNumber."}
 }finally{
  if($null -ne $tx){try{$tx.Rollback()}catch{};$tx.Dispose()}
  $dw.Dispose()
 }
 if((Read-State) -cne $before){throw "El fallo $ErrorNumber no preservo datos, marca y fecha."}
 "PASS: error $ErrorNumber conserva datos, marca y fecha"
}
$dw=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
$tx=$null
try{
 $tx=$dw.BeginTransaction();Copy-Staging $dw $tx
 $cmd=$dw.CreateCommand();$cmd.Transaction=$tx;$cmd.CommandTimeout=120
 $cmd.CommandText=Get-Content (Join-Path $PSScriptRoot 'Test-Application.sql') -Raw
 [void]$cmd.Parameters.AddWithValue('@cut',$cut)
 [void]$cmd.ExecuteNonQuery();$cmd.Dispose()
 'PASS: carga, altas y actualizaciones de cuatro dimensiones; SK estables; repeticion; pedido 10248; cantidad/cabecera; calendario; nulos'
}finally{
 if($null -ne $tx){try{$tx.Rollback()}catch{};$tx.Dispose()}
 $dw.Dispose()
}

Invoke-Failure @'
DECLARE @mark binary(8),@start bigint;
EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Cliente',@start,@cut;
EXEC dbo.GetLastPackageRowVersion N'Empleado',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Empleado',@start,@cut;
EXEC dbo.GetLastPackageRowVersion N'Producto',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Producto',@start,@cut;
EXEC dbo.GetLastPackageRowVersion N'Transportista',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Transportista',@start,@cut;
UPDATE std.Ventas SET ProductID=-902 WHERE OrderID=10248 AND ProductID=11;
EXEC dbo.GetLastPackageRowVersion N'Ventas',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Ventas',@start,@cut;
'@ 52407
Invoke-Failure @'
UPDATE dbo.PackageConfig SET LastRowVersion=0x0000000000000001 WHERE PackageName=N'Producto';
DELETE std.Ventas;DELETE dbo.Fact_Ventas;DELETE dbo.Dim_Producto;
EXEC dbo.DW_ApplyPackage N'Producto',1,@cut;
'@ 52404
Invoke-Failure @'
EXEC dbo.DW_ApplyPackage N'Cliente',1,0;
'@ 52401
Invoke-Failure @'
UPDATE dbo.PackageConfig SET LastRowVersion=0xFFFFFFFFFFFFFFFF WHERE PackageName=N'Cliente';
DECLARE @mark binary(8);EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;
'@ 52411
Invoke-Failure @'
EXEC dbo.DW_ApplyPackage N'NoExiste',0,@cut;
'@ 52409
Invoke-Failure @'
DELETE dbo.PackageConfig WHERE PackageName=N'Cliente';
DECLARE @mark binary(8);EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;
'@ 52410
Invoke-Failure @'
DECLARE @mark binary(8),@wrong bigint;
EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;SET @wrong=CONVERT(bigint,@mark)+1;
EXEC dbo.DW_ApplyPackage N'Cliente',@wrong,@wrong;
'@ 52403
Invoke-Failure @'
UPDATE std.Cliente SET SourceRowVersion=CONVERT(binary(8),@cut+1) WHERE CustomerID=N'VINET';
DECLARE @mark binary(8),@start bigint;
EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Cliente',@start,@cut;
'@ 52405
Invoke-Failure @'
UPDATE std.Cliente SET CustomerID=N'~UNK~' WHERE CustomerID=N'VINET';
DECLARE @mark binary(8),@start bigint;
EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Cliente',@start,@cut;
'@ 52408

# Inyeccion DDL solo en la copia marcada; siempre retirar el trigger en finally.
$builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$Server;$builder['Initial Catalog']='Northwind_DW_Test'
$builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
$created=$false
$admin=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try{
 $admin.Open();$cmd=$admin.CreateCommand()
 $cmd.CommandText=@'
IF DB_NAME()<>N'Northwind_DW_Test' OR NOT EXISTS(SELECT 1 FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 51002,'Inyeccion rechazada: destino no marcado.',1;
IF OBJECT_ID(N'dbo.NorthwindTestFailMark',N'TR') IS NOT NULL
 THROW 52521,'Ya existe el trigger de prueba; revise una ejecucion anterior.',1;
'@
 [void]$cmd.ExecuteNonQuery()
 $cmd.CommandText=@'
CREATE TRIGGER dbo.NorthwindTestFailMark ON dbo.PackageConfig AFTER UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted WHERE PackageName=N'Cliente')
  THROW 52520,'Fallo inyectado al guardar marca de Cliente.',1;
END;
'@
 [void]$cmd.ExecuteNonQuery()
 $created=$true
 Invoke-Failure @'
UPDATE std.Cliente SET City=N'Ciudad fallo' WHERE CustomerID=N'VINET';
DECLARE @mark binary(8),@start bigint;
EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Cliente',@start,@cut;
'@ 52520
}finally{
 if($created -and $admin.State -eq 'Open'){
  $cleanup=$admin.CreateCommand()
  $cleanup.CommandText=@'
IF DB_NAME()=N'Northwind_DW_Test' AND EXISTS(SELECT 1 FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 DROP TRIGGER IF EXISTS dbo.NorthwindTestFailMark;
'@
  try{[void]$cleanup.ExecuteNonQuery()}finally{$cleanup.Dispose()}
 }
 $admin.Dispose()
}

# Reintento del mismo staging despues de retirar el fallo; conserva exactamente una fila.
$dw=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
$tx=$null
try{
 $tx=$dw.BeginTransaction();Copy-Staging $dw $tx
 $cmd=$dw.CreateCommand();$cmd.Transaction=$tx
 $cmd.CommandText=@'
UPDATE std.Cliente SET City=N'Reintento' WHERE CustomerID=N'VINET';
DECLARE @mark binary(8),@start bigint;
EXEC dbo.GetLastPackageRowVersion N'Cliente',@mark OUTPUT;SET @start=CONVERT(bigint,@mark);
EXEC dbo.DW_ApplyPackage N'Cliente',@start,@cut;
DECLARE @sk int=(SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET');
EXEC dbo.DW_ApplyPackage N'Cliente',@cut,@cut;
IF (SELECT COUNT(*) FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>1
 OR (SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>@sk
 OR (SELECT Ciudad FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>N'Reintento'
 THROW 52522,'Reintento no aplica el cambio una sola vez.',1;
'@
 [void]$cmd.Parameters.AddWithValue('@cut',$cut);[void]$cmd.ExecuteNonQuery();$cmd.Dispose()
 'PASS: reintento aplica el cambio una vez y conserva SK; fixtures revertidos'
}finally{
 if($null -ne $tx){try{$tx.Rollback()}catch{};$tx.Dispose()}
 $dw.Dispose()
}
