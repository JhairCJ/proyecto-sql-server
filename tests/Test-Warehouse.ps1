[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1') -Force

function Assert-Rejected {
    param($Command,[string]$Sql,[int[]]$Numbers)
    $Command.CommandText=$Sql
    try {[void]$Command.ExecuteNonQuery();throw 'Se acepto una fila invalida.'}
    catch {
        $ex=$_.Exception
        while($null -ne $ex -and $ex -isnot [System.Data.SqlClient.SqlException]){$ex=$ex.InnerException}
        if($null -eq $ex -or $ex.Number -notin $Numbers){throw}
    }
}

$snapshot=Invoke-NorthwindTestSql -Database Northwind_Test -Server $Server -Sql @'
DECLARE @cut TABLE(DBTS bigint); INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @end bigint=(SELECT DBTS FROM @cut);
EXEC dbo.GetCustomerChangesByRowVersion 0,@end;
EXEC dbo.GetEmployeeChangesByRowVersion 0,@end;
EXEC dbo.GetProductChangesByRowVersion 0,@end;
EXEC dbo.GetShipperChangesByRowVersion 0,@end;
-- Normalizar en SQL antes del transporte: BulkCopy de REAL a DECIMAL puede truncar.
CREATE TABLE #Sales(OrderID int,ProductID int,CustomerID nchar(5),EmployeeID int,ShipperID int,
 OrderDate datetime,RequiredDate datetime,ShippedDate datetime,UnitPrice decimal(19,4),Quantity smallint,
 Discount decimal(9,6),OrderRowVersion binary(8),OrderDetailRowVersion binary(8));
INSERT #Sales EXEC dbo.GetSalesChangesByRowVersion 0,@end;
SELECT * FROM #Sales;
'@
$warehouse=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
$transaction=$null
try {
    $transaction=$warehouse.BeginTransaction()
    $command=$warehouse.CreateCommand();$command.Transaction=$transaction;$command.CommandTimeout=60
    $command.CommandText=@'
SET NOCOUNT ON; SET XACT_ABORT OFF;
IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas)
 OR EXISTS(SELECT 1 FROM dbo.Dim_Cliente WHERE Cliente_SK<>0)
 OR EXISTS(SELECT 1 FROM dbo.Dim_Empleado WHERE Empleado_SK<>0)
 OR EXISTS(SELECT 1 FROM dbo.Dim_Producto)
 OR EXISTS(SELECT 1 FROM dbo.Dim_Transportista)
 THROW 52301,'La suite requiere DW de prueba sin datos comerciales; no los vacia.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Dim_Cliente WHERE Cliente_SK=0 AND CustomerID=N'~UNK~')
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Empleado WHERE Empleado_SK=0 AND EmployeeID=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE Tiempo_SK=0 AND Fecha='19000101')
 THROW 52302,'Faltan miembros desconocidos.',1;
DELETE std.Cliente; DELETE std.Empleado; DELETE std.Producto; DELETE std.Transportista; DELETE std.Ventas;
'@
    [void]$command.ExecuteNonQuery()
    $tables=@('std.Cliente','std.Empleado','std.Producto','std.Transportista','std.Ventas')
    for($i=0;$i -lt $tables.Count;$i++){
        $bulk=[System.Data.SqlClient.SqlBulkCopy]::new($warehouse,[System.Data.SqlClient.SqlBulkCopyOptions]::CheckConstraints,$transaction)
        try {
            $bulk.DestinationTableName=$tables[$i]
            foreach($column in $snapshot.Tables[$i].Columns){[void]$bulk.ColumnMappings.Add($column.ColumnName,$column.ColumnName)}
            $bulk.WriteToServer($snapshot.Tables[$i])
        } finally {$bulk.Dispose()}
    }
    $command.CommandText=@'
EXEC dbo.DW_MergeDimCliente;
EXEC dbo.DW_MergeDimEmpleado;
EXEC dbo.DW_MergeDimProducto;
EXEC dbo.DW_MergeDimTransportista;
EXEC dbo.DW_LoadDimTiempo;
INSERT dbo.Fact_Ventas(Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,
 OrderID,ProductID,Cantidad,PrecioUnitario,Descuento,ImporteBruto,ImporteDescuento,ImporteNeto)
SELECT c.Cliente_SK,e.Empleado_SK,p.Producto_SK,s.Transportista_SK,t.Tiempo_SK,r.Tiempo_SK,v.Tiempo_SK,
 x.OrderID,x.ProductID,x.Quantity,x.UnitPrice,x.Discount,a.ImporteBruto,a.ImporteDescuento,a.ImporteNeto
FROM std.Ventas x
JOIN dbo.Dim_Cliente c ON c.CustomerID=x.CustomerID
JOIN dbo.Dim_Empleado e ON e.EmployeeID=x.EmployeeID
JOIN dbo.Dim_Producto p ON p.ProductID=x.ProductID
LEFT JOIN dbo.Dim_Transportista s ON s.ShipperID=x.ShipperID
JOIN dbo.Dim_Tiempo t ON t.Fecha=CONVERT(date,x.OrderDate)
LEFT JOIN dbo.Dim_Tiempo r ON r.Fecha=CONVERT(date,x.RequiredDate)
LEFT JOIN dbo.Dim_Tiempo v ON v.Fecha=CONVERT(date,x.ShippedDate)
CROSS APPLY dbo.DW_CalculateAmounts(x.Quantity,x.UnitPrice,x.Discount) a;
'@
    [void]$command.ExecuteNonQuery()
    $comparison=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseConnection $warehouse -WarehouseTransaction $transaction)
    $comparison | Format-Table -AutoSize
    if($comparison.Where({-not $_.Coincide}).Count){throw 'Referencia DW no reconciliada.'}
    'PASS: referencia completa reconciliada; desconocidos excluidos de entidades comerciales'

    $command.CommandText=@'
DECLARE @sk int=(SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET');
UPDATE std.Cliente SET City=N'Ciudad prueba' WHERE CustomerID=N'VINET';
EXEC dbo.DW_MergeDimCliente;
IF (SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>@sk
 OR (SELECT Ciudad FROM dbo.Dim_Cliente WHERE CustomerID=N'VINET')<>N'Ciudad prueba'
 THROW 52303,'Cambio tipo 1 no conserva clave o atributos.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DW_CalculateAmounts(10,20,0.1) WHERE ImporteBruto=200 AND ImporteDescuento=20 AND ImporteNeto=180)
 OR NOT EXISTS(SELECT 1 FROM dbo.DW_CalculateAmounts(1,0.0050,0) WHERE ImporteBruto=0.01 AND ImporteNeto=0.01)
 OR NOT EXISTS(SELECT 1 FROM dbo.DW_CalculateAmounts(1,1,0.005000) WHERE ImporteDescuento=0.01 AND ImporteNeto=0.99)
 THROW 52304,'Regla monetaria o empate de redondeo incorrecto.',1;
IF (SELECT COUNT(*) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>3
 OR (SELECT SUM(Cantidad) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>27
 OR (SELECT SUM(ImporteNeto) FROM dbo.Fact_Ventas WHERE OrderID=10248)<>440
 THROW 52305,'Pedido 10248 no coincide.',1;
SET LANGUAGE us_english; SET DATEFIRST 7;
DECLARE @dias int=(SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0);
EXEC dbo.DW_LoadDimTiempo;
IF @dias<>(SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE Fecha='19960704' AND NombreDia=N'Jueves' AND NombreMes=N'Julio')
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE Fecha='19980611')
 THROW 52306,'Calendario no repetible o dependiente de idioma/DATEFIRST.',1;
SET LANGUAGE Spanish; SET DATEFIRST 1;
EXEC dbo.DW_LoadDimTiempo;
IF @dias<>(SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)
 THROW 52307,'Calendario se duplica con otra configuracion.',1;
DECLARE @max date=(SELECT MAX(Fecha) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0),@hasta date;
SET @hasta=DATEADD(day,4,@max);
EXEC dbo.DW_LoadDimTiempo @max,@hasta;
EXEC dbo.DW_LoadDimTiempo @max,@hasta;
IF @dias+4<>(SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)
 OR (SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)<>(SELECT DATEDIFF(day,MIN(Fecha),MAX(Fecha))+1 FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0)
 THROW 52308,'Extension no continua o repetible.',1;
'@
    [void]$command.ExecuteNonQuery()
    'PASS: tipo 1 conserva SK; calendario continuo, tres fechas, extension e idioma; importes y empates'

    foreach($sql in @(
       "INSERT dbo.Dim_Cliente(CustomerID) VALUES(N'VINET');",
       'INSERT dbo.Dim_Empleado(EmployeeID) VALUES(1);',
       'INSERT dbo.Dim_Producto(ProductID) VALUES(11);',
       'INSERT dbo.Dim_Transportista(ShipperID) VALUES(1);')){
        Assert-Rejected $command $sql @(2601,2627)
    }
    $columns='Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,OrderID,ProductID,Cantidad,PrecioUnitario,Descuento,ImporteBruto,ImporteDescuento,ImporteNeto'
    Assert-Rejected $command "INSERT dbo.Fact_Ventas($columns) SELECT $columns FROM dbo.Fact_Ventas WHERE OrderID=10248 AND ProductID=11;" @(2601,2627)
    foreach($changes in @(@('Cantidad','0'),@('PrecioUnitario','-1'),@('Descuento','1.1'),@('Cliente_SK','-999999'))){
        $projection=$columns.Replace('OrderID,','-9002,')
        $projection=[regex]::Replace($projection,"(?<!\w)$($changes[0])(?!\w)",$changes[1])
        Assert-Rejected $command "INSERT dbo.Fact_Ventas($columns) SELECT $projection FROM dbo.Fact_Ventas WHERE OrderID=10248 AND ProductID=11;" @(547)
    }
    $command.CommandText=@'
INSERT dbo.Fact_Ventas(Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,
 OrderID,ProductID,Cantidad,PrecioUnitario,Descuento,ImporteBruto,ImporteDescuento,ImporteNeto)
SELECT 0,0,Producto_SK,NULL,0,NULL,NULL,-9100,ProductID,1,1,0,1,0,1 FROM dbo.Dim_Producto WHERE ProductID=11;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_Ventas WHERE OrderID=-9100 AND Cliente_SK=0 AND Empleado_SK=0 AND FechaPedido_SK=0
 AND Transportista_SK IS NULL AND FechaRequerida_SK IS NULL AND FechaEnvio_SK IS NULL)
 THROW 52309,'Modelo no conserva ausencias legitimas.',1;
DELETE dbo.Fact_Ventas WHERE OrderID=-9100;
UPDATE dbo.Fact_Ventas SET ImporteNeto=ImporteNeto+1 WHERE OrderID=10248 AND ProductID=11;
'@
    [void]$command.ExecuteNonQuery()
    $invalid=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseConnection $warehouse -WarehouseTransaction $transaction)
    if(-not $invalid.Where({$_.Comprobacion -eq 'ImportesInvalidos' -and $_.DW -eq 1}).Count -or
        -not $invalid.Where({$_.Comprobacion -eq 'Neto' -and -not $_.Coincide}).Count){throw 'Comparacion no detecta fixture monetario invalido.'}
    'PASS: restricciones rechazan duplicados, cantidad/precio/descuento y FK; ausencias admitidas; comparacion detecta error'
    $command.CommandText='UPDATE dbo.Fact_Ventas SET ImporteNeto=ImporteNeto-1 WHERE OrderID=10248 AND ProductID=11;'
    [void]$command.ExecuteNonQuery()
    $final=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseConnection $warehouse -WarehouseTransaction $transaction)
    if($final.Where({-not $_.Coincide}).Count){throw 'Reconciliacion final fallida.'}
    $command.CommandText='UPDATE dbo.Fact_Ventas SET ProductID=-99 WHERE OrderID=10248 AND ProductID=11;'
    [void]$command.ExecuteNonQuery()
    $invalidKey=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseConnection $warehouse -WarehouseTransaction $transaction)
    if(-not $invalidKey.Where({$_.Comprobacion -eq 'ReferenciasInvalidas' -and $_.DW -eq 1}).Count){throw 'Comparacion no detecta identidad de producto inconsistente.'}
    $command.CommandText='UPDATE dbo.Fact_Ventas SET ProductID=11 WHERE OrderID=10248 AND ProductID=-99;'
    [void]$command.ExecuteNonQuery()
    'PASS: comparacion identifica ProductID comercial incoherente con su SK'
    $command.Dispose()
} finally {
    if($null -ne $transaction){$transaction.Rollback();$transaction.Dispose()}
    $warehouse.Dispose()
}
'PASS: fixture completo revertido; copia conserva solo preparacion de esquema/calendario'
