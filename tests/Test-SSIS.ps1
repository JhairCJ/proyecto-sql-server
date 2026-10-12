[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$run=Join-Path $repo 'scripts/Run-NorthwindETL.ps1'
$id=[Guid]::NewGuid().ToString('N').Substring(0,8)
$src="Northwind_SSIS_OLTP_$id";$dst="Northwind_SSIS_DW_$id"
$evidence=Join-Path $repo "docs/evidencias/ssis/$id"
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
function Connect([string]$Database,[switch]$Restricted){
 $b=[Data.SqlClient.SqlConnectionStringBuilder]::new()
 $b['Data Source']=$Server;$b['Initial Catalog']=$Database;$b['Integrated Security']=$true
 $b['Encrypt']=$true;$b['TrustServerCertificate']=$true;$b['Pooling']=$false
 $c=[Data.SqlClient.SqlConnection]::new($b.ConnectionString);$c.Open()
 if($Restricted){
  $cmd=$c.CreateCommand();$expected=if($Database -eq $src){'NorthWind'}else{'Northwind_DW'}
  $cmd.CommandText="IF DB_NAME()<>@db OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=@origin) THROW 52540,'Copia SSIS no marcada.',1;"
  [void]$cmd.Parameters.AddWithValue('@db',$Database);[void]$cmd.Parameters.AddWithValue('@origin',$expected)
  try{[void]$cmd.ExecuteNonQuery()}catch{$c.Dispose();throw}finally{$cmd.Dispose()}
  $cmd=$c.CreateCommand();$cmd.CommandText="EXECUTE AS USER=N'NorthwindFixture' WITH NO REVERT;"
  try{[void]$cmd.ExecuteNonQuery()}catch{$c.Dispose();throw}finally{$cmd.Dispose()}
 }
 return $c
}
function Sql([string]$Database,[string]$Text,[switch]$Admin){
 $c=Connect $Database -Restricted:($Database -in @($src,$dst) -and -not $Admin)
 try{
  $cmd=$c.CreateCommand();$cmd.CommandText=$Text;$cmd.CommandTimeout=120
  $adapter=[Data.SqlClient.SqlDataAdapter]::new($cmd);$data=[Data.DataSet]::new()
  try{[void]$adapter.Fill($data);return ,$data}finally{$adapter.Dispose();$cmd.Dispose()}
 }finally{$c.Dispose()}
}
function Load([string]$Package='CargarNorthwind'){
 & $run -Server $Server -SourceDatabase $src -WarehouseDatabase $dst -Package $Package -LogDirectory $evidence 2>$null | Out-Null
}
function Snapshot([switch]$Staging,[switch]$Dates){
 $date=if($Dates){',LastSuccessfulLoad'}else{''}
 $query="SELECT * FROM dbo.Dim_Cliente ORDER BY Cliente_SK;SELECT * FROM dbo.Dim_Empleado ORDER BY Empleado_SK;SELECT * FROM dbo.Dim_Producto ORDER BY Producto_SK;SELECT * FROM dbo.Dim_Transportista ORDER BY Transportista_SK;SELECT * FROM dbo.Dim_Tiempo ORDER BY Tiempo_SK;SELECT * FROM dbo.Fact_Ventas ORDER BY Venta_SK;SELECT PackageName,LastRowVersion$date FROM dbo.PackageConfig ORDER BY PackageName;"
 if($Staging){$query+='SELECT * FROM std.Cliente ORDER BY CustomerID;SELECT * FROM std.Empleado ORDER BY EmployeeID;SELECT * FROM std.Producto ORDER BY ProductID;SELECT * FROM std.Transportista ORDER BY ShipperID;SELECT * FROM std.Ventas ORDER BY OrderID,ProductID;'}
 return (Sql $dst $query).GetXml()
}
function Check{
 # Independiente de los procedimientos de carga y de sus calculos.
 $s=Sql $src @'
SELECT (SELECT COUNT(*) FROM dbo.Customers) Clientes,(SELECT COUNT(*) FROM dbo.Employees) Empleados,
 (SELECT COUNT(*) FROM dbo.Products) Productos,(SELECT COUNT(*) FROM dbo.Shippers) Transportistas,
 COUNT(*) Lineas,COUNT(DISTINCT OrderID) Pedidos,SUM(CONVERT(bigint,Quantity)) Unidades,
 SUM(b.Bruto) Bruto,SUM(d.Dcto) Descuento,SUM(b.Bruto-d.Dcto) Neto
FROM dbo.OrderDetails
CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(CONVERT(decimal(19,4),UnitPrice)*Quantity,2)))) b(Bruto)
CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(b.Bruto*CONVERT(decimal(9,6),Discount),2)))) d(Dcto);
'@
 $w=Sql $dst @'
SELECT (SELECT COUNT(*) FROM dbo.Dim_Cliente WHERE Cliente_SK<>0) Clientes,
 (SELECT COUNT(*) FROM dbo.Dim_Empleado WHERE Empleado_SK<>0) Empleados,
 (SELECT COUNT(*) FROM dbo.Dim_Producto) Productos,(SELECT COUNT(*) FROM dbo.Dim_Transportista) Transportistas,
 COUNT(*) Lineas,COUNT(DISTINCT OrderID) Pedidos,SUM(CONVERT(bigint,Cantidad)) Unidades,
 SUM(ImporteBruto) Bruto,SUM(ImporteDescuento) Descuento,SUM(ImporteNeto) Neto FROM dbo.Fact_Ventas;
IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas GROUP BY OrderID,ProductID HAVING COUNT(*)>1)
 THROW 52541,'Lineas duplicadas.',1;
IF (SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)<>
 (SELECT DATEDIFF(day,MIN(Fecha),MAX(Fecha))+1 FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)
 THROW 52542,'Calendario discontinuo.',1;
'@
 foreach($col in $s.Tables[0].Columns){if($s.Tables[0].Rows[0][$col.ColumnName] -ne $w.Tables[0].Rows[0][$col.ColumnName]){throw "No coincide $($col.ColumnName)"}}
}
& (Join-Path $repo 'scripts/Build-NorthwindETL.ps1') | Out-Null
# Copia nueva por ejecucion; ninguna copia preexistente se reinicia o restaura encima.
$paths=Sql master "IF DB_ID(N'$src') IS NOT NULL OR DB_ID(N'$dst') IS NOT NULL THROW 52543,'Nombre de prueba ocupado.',1; SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath')) BackupPath,CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')) DataPath,CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultLogPath')) LogPath;"
$backup=Join-Path ([string]$paths.Tables[0].Rows[0].BackupPath) "SSIS_$id.bak"
$literal=$backup.Replace("'","''")
[void](Sql Northwind_Test "IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'NorthWind') THROW 52540,'Origen no marcado.',1; BACKUP DATABASE [Northwind_Test] TO DISK=N'$literal' WITH COPY_ONLY,CHECKSUM,COMPRESSION;" -Admin)
$files=Sql master "RESTORE FILELISTONLY FROM DISK=N'$literal';"
$moves=@();$i=0
foreach($file in $files.Tables[0].Rows){
 $i++;$path=if($file.Type -eq 'L'){$paths.Tables[0].Rows[0].LogPath}else{$paths.Tables[0].Rows[0].DataPath}
 $target=Join-Path ([string]$path) "$($src)_$i.$($file.Type.ToString().ToLower())"
 $moves+="MOVE N'$($file.LogicalName.Replace("'","''"))' TO N'$($target.Replace("'","''"))'"
}
[void](Sql master "RESTORE DATABASE [$src] FROM DISK=N'$literal' WITH CHECKSUM, RECOVERY, $($moves -join ','); CREATE DATABASE [$dst]; ALTER DATABASE [$src] SET TRUSTWORTHY OFF;ALTER DATABASE [$src] SET DB_CHAINING OFF;" -Admin)
[void](Sql $dst "EXEC sys.sp_addextendedproperty @name=N'NorthwindPracticeTestDatabase',@value=N'Northwind_DW';CREATE USER NorthwindFixture WITHOUT LOGIN;GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE TO NorthwindFixture;" -Admin)
$b=[Data.SqlClient.SqlConnectionStringBuilder]::new();$b['Data Source']=$Server;$b['Initial Catalog']=$dst;$b['Integrated Security']=$true;$b['Encrypt']=$true;$b['TrustServerCertificate']=$true
& 'C:/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/Extensions/Microsoft/SQLDB/DAC/SqlPackage.exe' /Action:Publish "/SourceFile:$repo/Northwind.DW/bin/Debug/Northwind.DW.dacpac" "/TargetConnectionString:$($b.ConnectionString)" /p:DropObjectsNotInSource=False /p:DropExtendedPropertiesNotInSource=False /p:ScriptDatabaseOptions=False *> (Join-Path $evidence 'publish.txt')
if($LASTEXITCODE -ne 0){throw 'Fallo publicacion del DW exclusivo de SSIS.'}
"Copias de esta prueba: $src / $dst (se conservan para inspeccion)"
Load;Check
[void](Sql $dst "IF (SELECT COUNT(*) FROM dbo.Fact_Ventas)<>2155 OR (SELECT COUNT(*) FROM dbo.PackageConfig WHERE LastSuccessfulLoad IS NOT NULL)<>5 THROW 52544,'Carga inicial incompleta.',1;")
'PASS: carga inicial SSIS, cinco marcas Int64 y reconciliacion independiente'
Load;$before=Snapshot -Staging;Load
if((Snapshot -Staging) -cne $before){throw 'Repeticion altera claves, datos o marcas.'}
foreach($name in @('Cliente','Empleado','Producto','Transportista','Ventas')){Load $name}
if((Snapshot -Staging) -cne $before){throw 'Paquetes independientes alteran carga sin cambios.'}
'PASS: repeticion principal e independiente conserva claves y datos'
$insert=Sql $src @'
SET XACT_ABORT ON;BEGIN TRAN;
INSERT dbo.Customers(CustomerID,CompanyName,City) VALUES(N'TSSIS',N'Cliente SSIS',N'La Paz');
INSERT dbo.Orders(CustomerID,EmployeeID,ShipVia,OrderDate,RequiredDate,ShippedDate)
 VALUES(N'TSSIS',1,1,'20000101','20000102',NULL);
DECLARE @id int=SCOPE_IDENTITY();
INSERT dbo.OrderDetails(OrderID,ProductID,UnitPrice,Quantity,Discount) VALUES(@id,11,14,2,0.15);
COMMIT;SELECT @id OrderID;
'@
$order=[int]$insert.Tables[0].Rows[0].OrderID
Load;Check
$keys=Sql $dst "SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'TSSIS'; SELECT Venta_SK FROM dbo.Fact_Ventas WHERE OrderID=$order AND ProductID=11;"
[void](Sql $src "SET XACT_ABORT ON;BEGIN TRAN; UPDATE dbo.OrderDetails SET Quantity=5,Discount=0.333333 WHERE OrderID=$order; UPDATE dbo.Orders SET EmployeeID=2,ShipVia=2,ShippedDate='20000105' WHERE OrderID=$order; UPDATE dbo.Categories SET CategoryName=N'Categoria SSIS' WHERE CategoryID=1;UPDATE dbo.Suppliers SET CompanyName=N'Proveedor SSIS' WHERE SupplierID=1;UPDATE dbo.Shippers SET Phone=N'555-SSIS' WHERE ShipperID=2;UPDATE dbo.Employees SET FirstName=N'Jefe SSIS' WHERE EmployeeID=2;COMMIT;")
Load;Check
[void](Sql $dst "IF (SELECT Cantidad FROM dbo.Fact_Ventas WHERE OrderID=$order)<>5 OR (SELECT FechaEnvio_SK FROM dbo.Fact_Ventas WHERE OrderID=$order)<>20000105 OR NOT EXISTS(SELECT 1 FROM dbo.Fact_Ventas f JOIN dbo.Dim_Empleado e ON f.Empleado_SK=e.Empleado_SK JOIN dbo.Dim_Transportista t ON f.Transportista_SK=t.Transportista_SK WHERE f.OrderID=$order AND e.EmployeeID=2 AND t.ShipperID=2) OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Producto WHERE ProductID=1 AND Categoria=N'Categoria SSIS' AND Proveedor=N'Proveedor SSIS') OR (SELECT Telefono FROM dbo.Dim_Transportista WHERE ShipperID=2)<>N'555-SSIS' OR (SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'TSSIS')<>$($keys.Tables[0].Rows[0].Cliente_SK) OR (SELECT Venta_SK FROM dbo.Fact_Ventas WHERE OrderID=$order)<>$($keys.Tables[1].Rows[0].Venta_SK) THROW 52545,'Incremento, dependencia o SK incorrectos.',1;")
'PASS: cliente/pedido nuevo, detalle, cabecera, categoria, proveedor y transportista'
[void](Sql $dst "CREATE TRIGGER dbo.SsisFailMark ON dbo.PackageConfig AFTER UPDATE AS IF EXISTS(SELECT 1 FROM inserted WHERE PackageName=N'Cliente') THROW 52546,'Fallo SSIS inyectado al confirmar marca.',1;" -Admin)
try{
 [void](Sql $src "UPDATE dbo.Customers SET City=N'Reintento' WHERE CustomerID=N'TSSIS';")
 $before=Snapshot -Dates;$rejected=$false
 try{Load}catch{$rejected=$true}
 if(-not $rejected -or (Snapshot -Dates) -cne $before){throw 'Fallo confirma finales/marcas o continua dependientes.'}
}finally{[void](Sql $dst 'DROP TRIGGER dbo.SsisFailMark;' -Admin)}
Load;Check
[void](Sql $dst "IF (SELECT Ciudad FROM dbo.Dim_Cliente WHERE CustomerID=N'TSSIS')<>N'Reintento' THROW 52547,'Reintento no aplica cambio pendiente.',1;")
'PASS: fallo atomico, detencion de dependientes, liberacion del bloqueo y reintento'
# Principal real detenido antes de staging, sin bloquear las lecturas de comprobacion.
$original=(Sql $src "SELECT OBJECT_DEFINITION(OBJECT_ID(N'dbo.GetDatabaseRowVersion')) Definition;" -Admin).Tables[0].Rows[0].Definition
$waiting=$original -replace 'CREATE\s+PROCEDURE','ALTER PROCEDURE'
$waiting=$waiting -replace 'SET NOCOUNT ON;',"SET NOCOUNT ON; IF CONTEXT_INFO() IS NULL OR CONTEXT_INFO()<>0x53534953 BEGIN SET CONTEXT_INFO 0x53534953;WAITFOR DELAY '00:00:20';END;"
[void](Sql $src $waiting -Admin)
$job=$null
try{
 $job=Start-Job -ScriptBlock {param($r,$s,$a,$b,$l) & $r -Server $s -SourceDatabase $a -WarehouseDatabase $b -LogDirectory $l} -ArgumentList $run,$Server,$src,$dst,$evidence
 $gate=Connect $dst -Restricted
 try{
  $locked=$false;$deadline=[DateTime]::UtcNow.AddSeconds(10)
  while([DateTime]::UtcNow -lt $deadline){
   $cmd=$gate.CreateCommand();$cmd.CommandText="SELECT APPLOCK_TEST(N'public',N'Northwind.Warehouse.Load',N'Exclusive',N'Session');"
   try{$locked=($cmd.ExecuteScalar() -eq 0)}finally{$cmd.Dispose()}
   if($locked){break};Start-Sleep -Milliseconds 100
  }
  if(-not $locked){throw 'El principal no retuvo el bloqueo.'}
  $before=Snapshot -Staging -Dates
  foreach($name in @('CargarNorthwind','Cliente','Empleado','Producto','Transportista','Ventas')){
   $rejected=$false;try{Load $name}catch{$rejected=$true}
   if(-not $rejected -or (Snapshot -Staging -Dates) -cne $before){throw "Competidor $name modifica staging o control."}
  }
 }finally{$gate.Dispose()}
 [void](Wait-Job $job -Timeout 35);Receive-Job $job -ErrorAction Stop | Out-Null
 if($job.State -ne 'Completed'){throw 'Carga principal concurrente no termino.'}
}finally{
 if($null -ne $job){if($job.State -eq 'Running'){Stop-Job $job};Remove-Job $job}
 [void](Sql $src ($original -replace 'CREATE\s+PROCEDURE','ALTER PROCEDURE') -Admin)
}
Load;Check
'PASS: principal mantiene sesion compartida y rechaza seis entradas antes de staging'
$prior=(Sql $dst "SELECT CONVERT(bigint,LastRowVersion) Mark,CONVERT(varchar(33),LastSuccessfulLoad,126) Loaded FROM dbo.PackageConfig WHERE PackageName=N'Cliente';").Tables[0].Rows[0]
try{
 [void](Sql $src 'ALTER PROCEDURE dbo.GetDatabaseRowVersion AS SELECT CONVERT(bigint,9223372036854775807) DBTS;' -Admin)
 Load Cliente;Load Cliente
 [void](Sql $dst "IF (SELECT CONVERT(bigint,LastRowVersion) FROM dbo.PackageConfig WHERE PackageName=N'Cliente')<>9223372036854775807 THROW 52548,'SSIS perdio precision de Int64.',1;")
}finally{
 [void](Sql $src ($original -replace 'CREATE\s+PROCEDURE','ALTER PROCEDURE') -Admin)
 [void](Sql $dst "UPDATE dbo.PackageConfig SET LastRowVersion=CONVERT(binary(8),CONVERT(bigint,$($prior.Mark))),LastSuccessfulLoad=CONVERT(datetime2,'$($prior.Loaded)',126) WHERE PackageName=N'Cliente';")
}
'PASS: enlaces SSIS de inicio/fin conservan Int64.MaxValue sin conversion a double'
$log=(Get-ChildItem -LiteralPath $evidence -Filter 'Northwind.ETL-*.log' | ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw}) -join "`n"
foreach($name in @('CargarNorthwind','Cliente','Empleado','Producto','Transportista','Ventas')){if($log -notmatch [regex]::Escape($name)){throw "Falta registro $name"}}
if($log -notmatch 'OnError' -or $log -notmatch 'PackageEnd'){throw 'Logging no registra errores y fin.'}
if($log -notmatch 'Fallo SSIS inyectado al confirmar marca' -or $log -notmatch 'DW ocupado por otra carga'){throw 'Los fallos no corresponden a las inyecciones esperadas.'}
'PASS: logging nativo contiene resultado correcto y error de cada entrada'
"Evidencias: $evidence"
