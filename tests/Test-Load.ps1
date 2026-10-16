[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force
$loader=Join-Path $PSScriptRoot '../scripts/Load-NorthwindWarehouse.ps1'

function Read-State([switch]$IncludeStaging,[switch]$IncludeLoadTimes){
    $staging=if($IncludeStaging){@'
SELECT * FROM std.Cliente ORDER BY CustomerID;
SELECT * FROM std.Empleado ORDER BY EmployeeID;
SELECT * FROM std.Proveedor ORDER BY SupplierID;
SELECT * FROM std.Producto ORDER BY ProductID;
SELECT * FROM std.Transportista ORDER BY ShipperID;
SELECT * FROM std.Ventas ORDER BY OrderID,ProductID;
'@}else{''}
    $loadTimes=if($IncludeLoadTimes){',LastSuccessfulLoad'}else{''}
    $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @"
SELECT * FROM dbo.DimDate ORDER BY DateKey;
SELECT * FROM dbo.DimCustomer ORDER BY CustomerKey;
SELECT * FROM dbo.DimEmployee ORDER BY EmployeeKey;
SELECT * FROM dbo.DimProduct ORDER BY ProductKey;
SELECT * FROM dbo.DimShipper ORDER BY ShipperKey;
SELECT * FROM dbo.DimSupplier ORDER BY SupplierKey;
SELECT * FROM dbo.DimGeography ORDER BY GeographyKey;
SELECT * FROM dbo.FactSales ORDER BY SalesKey;
SELECT PackageName,LastRowVersion$loadTimes FROM dbo.PackageConfig ORDER BY PackageName;
$staging
"@
    return $state.GetXml()
}

& $loader -Server $Server | Out-Null
$comparison=@(Get-NorthwindWarehouseComparison -Server $Server)
if($comparison.Where({-not $_.Coincide}).Count){throw 'La carga actual no concilia antes de probar repetición.'}
$before=Read-State -IncludeStaging
& $loader -Server $Server | Out-Null
if((Read-State -IncludeStaging) -cne $before){throw 'La repetición cambió dimensiones, hechos, staging o controles.'}
'PASS: carga incremental repetida sin cambios conserva claves, líneas, destinos, medidas y marcas'

$lock=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
try{
    $command=$lock.CreateCommand()
    $command.CommandText=@'
DECLARE @result int;
EXEC @result=sys.sp_getapplock @Resource=N'Northwind.Warehouse.Load',
 @LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @result<0 THROW 52402,'No se pudo adquirir bloqueo de prueba.',1;
'@
    [void]$command.ExecuteNonQuery();$command.Dispose()
    $lockedState=Read-State -IncludeStaging
    $rejected=$false
    try{& $loader -Server $Server | Out-Null}
    catch{if($_.Exception.Message -notlike '*DW ocupado*'){throw};$rejected=$true}
    if(-not $rejected -or (Read-State -IncludeStaging) -cne $lockedState){
        throw 'Una carga competidora cambió staging, datos o controles antes del bloqueo.'
    }
    'PASS: una segunda carga concurrente se rechaza antes de leer o reemplazar staging'
}finally{$lock.Dispose()}

$source=New-NorthwindTestConnection -Database Northwind_Test -Server $Server
$admin=$null;$created=$false;$changed=$false
$oldCity=$null
try{
    $read=$source.CreateCommand()
    $read.CommandText="SELECT City FROM dbo.Customers WHERE CustomerID=N'VINET';"
    $oldCity=$read.ExecuteScalar();$read.Dispose()
    if($oldCity -is [DBNull]){$oldCity=$null}
    $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server;$builder['Initial Catalog']='Northwind_DW_Test'
    $builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
    $admin=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString);$admin.Open()
    $command=$admin.CreateCommand()
    $command.CommandText=@'
IF DB_NAME()<>N'Northwind_DW_Test' OR NOT EXISTS(SELECT 1 FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 51002,'La inyección requiere el DW de prueba marcado.',1;
IF OBJECT_ID(N'dbo.NorthwindTestFailMark',N'TR') IS NOT NULL
 THROW 52521,'Ya existe el trigger de fallo; revise una prueba anterior.',1;
'@
    [void]$command.ExecuteNonQuery()
    $command.CommandText=@'
CREATE TRIGGER dbo.NorthwindTestFailMark ON dbo.PackageConfig AFTER UPDATE AS
BEGIN
    IF EXISTS(SELECT 1 FROM inserted WHERE PackageName=N'Cliente')
        THROW 52520,'Fallo inyectado al confirmar la marca Cliente.',1;
END;
'@
    [void]$command.ExecuteNonQuery();$created=$true

    $write=$source.CreateCommand()
    $write.CommandText="UPDATE dbo.Customers SET City=N'Carga prueba' WHERE CustomerID=N'VINET';"
    [void]$write.ExecuteNonQuery();$write.Dispose();$changed=$true
    $beforeFailure=Read-State -IncludeLoadTimes
    $rejected=$false
    try{& $loader -Server $Server | Out-Null}
    catch{if($_.Exception.Message -notlike '*Fallo inyectado al confirmar*'){throw};$rejected=$true}
    if(-not $rejected -or (Read-State -IncludeLoadTimes) -cne $beforeFailure){
        throw 'El fallo al guardar la marca confirmó cambios o controles.'
    }
    $command.CommandText='DROP TRIGGER dbo.NorthwindTestFailMark;'
    [void]$command.ExecuteNonQuery();$created=$false
    & $loader -Server $Server | Out-Null
    $check=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
IF (SELECT COUNT(*) FROM dbo.DimCustomer WHERE CustomerID=N'VINET')<>1
 OR (SELECT City FROM dbo.DimCustomer WHERE CustomerID=N'VINET')<>N'Carga prueba'
 OR (SELECT COUNT(*) FROM dbo.FactSales)<>2155
 OR (SELECT COUNT(*) FROM dbo.PackageConfig WHERE LastSuccessfulLoad IS NULL)<>0
    THROW 52523,'El reintento incremental no confirmó el cambio completo.',1;
SELECT CustomerKey FROM dbo.DimCustomer WHERE CustomerID=N'VINET';
'@
    if(-not $check.Tables[0].Rows.Count){throw 'El reintento no devolvió la clave del cliente.'}
    'PASS: fallo al confirmar Cliente revierte cambios y marca; el reintento aplica el cambio una sola vez'
}finally{
    if($created -and $null -ne $admin -and $admin.State -eq 'Open'){
        $cleanup=$admin.CreateCommand()
        $cleanup.CommandText=@'
IF DB_NAME()=N'Northwind_DW_Test' AND EXISTS(SELECT 1 FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
    DROP TRIGGER IF EXISTS dbo.NorthwindTestFailMark;
'@
        try{[void]$cleanup.ExecuteNonQuery()}finally{$cleanup.Dispose()}
    }
    if($null -ne $admin){$admin.Dispose()}
    if($changed){
        $restore=$source.CreateCommand()
        $restore.CommandText='UPDATE dbo.Customers SET City=@city WHERE CustomerID=N''VINET'';'
        [void]$restore.Parameters.Add('@city',[Data.SqlDbType]::NVarChar,15)
        if($null -eq $oldCity){$restore.Parameters['@city'].Value=[DBNull]::Value}
        else{$restore.Parameters['@city'].Value=$oldCity}
        try{[void]$restore.ExecuteNonQuery()}finally{$restore.Dispose()}
    }
    $source.Dispose()
    if($changed){& $loader -Server $Server | Out-Null}
}

$comparison=@(Get-NorthwindWarehouseComparison -Server $Server)
$comparison | Format-Table -AutoSize
if($comparison.Where({-not $_.Coincide}).Count){throw 'Reconciliación final después de restaurar el fixture falló.'}
'PASS: origen de prueba restaurado; DW vuelve a coincidir con líneas, importes, proveedor, destino y flete'
