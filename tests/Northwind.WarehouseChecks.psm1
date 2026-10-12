Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1')

function Read-WarehouseMetrics {
    param($Connection,[string]$Sql,$Transaction)
    $command=$Connection.CreateCommand();if($null -ne $Transaction){$command.Transaction=$Transaction};$command.CommandText=$Sql;$command.CommandTimeout=60
    $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($command);$table=[System.Data.DataTable]::new()
    try {[void]$adapter.Fill($table);return ,$table} finally {$adapter.Dispose();$command.Dispose()}
}

function Get-NorthwindWarehouseComparison {
    [CmdletBinding()]
    param([string]$Server='localhost',$WarehouseConnection,$WarehouseTransaction)
    $ErrorActionPreference='Stop'
    $source=New-NorthwindTestConnection -Database Northwind_Test -Server $Server
    $ownWarehouse=$null -eq $WarehouseConnection
    try {
        if($ownWarehouse){$WarehouseConnection=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server}
        $src=Read-WarehouseMetrics $source @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.Customers) Clientes,
 (SELECT COUNT_BIG(*) FROM dbo.Employees) Empleados,
 (SELECT COUNT_BIG(*) FROM dbo.Products) Productos,
 (SELECT COUNT_BIG(*) FROM dbo.Shippers) Transportistas,
 COUNT_BIG(*) Lineas,COUNT_BIG(DISTINCT OrderID) Pedidos,
 COALESCE(SUM(CONVERT(bigint,Quantity)),0) Unidades,
 COALESCE(SUM(b.Bruto),0) Bruto,COALESCE(SUM(d.DescuentoImporte),0) Descuento,
 COALESCE(SUM(b.Bruto-d.DescuentoImporte),0) Neto
FROM dbo.OrderDetails
CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(CONVERT(decimal(19,4),UnitPrice)*CONVERT(decimal(5,0),Quantity),2)))) b(Bruto)
CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(b.Bruto*CONVERT(decimal(9,6),Discount),2)))) d(DescuentoImporte);
'@
        $dst=Read-WarehouseMetrics $WarehouseConnection @'
IF DB_NAME()<>N'Northwind_DW_Test' THROW 52201,'Comparacion requiere DW de prueba.',1;
SELECT (SELECT COUNT_BIG(*) FROM dbo.Dim_Cliente WHERE Cliente_SK<>0) Clientes,
 (SELECT COUNT_BIG(*) FROM dbo.Dim_Empleado WHERE Empleado_SK<>0) Empleados,
 (SELECT COUNT_BIG(*) FROM dbo.Dim_Producto) Productos,
 (SELECT COUNT_BIG(*) FROM dbo.Dim_Transportista) Transportistas,
 COUNT_BIG(*) Lineas,COUNT_BIG(DISTINCT OrderID) Pedidos,
 COALESCE(SUM(CONVERT(bigint,Cantidad)),0) Unidades,
 COALESCE(SUM(ImporteBruto),0) Bruto,COALESCE(SUM(ImporteDescuento),0) Descuento,COALESCE(SUM(ImporteNeto),0) Neto
FROM dbo.Fact_Ventas;
'@ -Transaction $WarehouseTransaction
        foreach($column in $src.Columns){
            $name=$column.ColumnName
            [pscustomobject]@{Comprobacion=$name;Origen=$src.Rows[0][$name];DW=$dst.Rows[0][$name];Coincide=($src.Rows[0][$name] -eq $dst.Rows[0][$name])}
        }
        $integrity=Read-WarehouseMetrics $WarehouseConnection @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.Fact_Ventas f
 LEFT JOIN dbo.Dim_Cliente c ON c.Cliente_SK=f.Cliente_SK
 LEFT JOIN dbo.Dim_Empleado e ON e.Empleado_SK=f.Empleado_SK
 LEFT JOIN dbo.Dim_Producto p ON p.Producto_SK=f.Producto_SK
 LEFT JOIN dbo.Dim_Transportista s ON s.Transportista_SK=f.Transportista_SK
 LEFT JOIN dbo.Dim_Tiempo t ON t.Tiempo_SK=f.FechaPedido_SK
 LEFT JOIN dbo.Dim_Tiempo r ON r.Tiempo_SK=f.FechaRequerida_SK
 LEFT JOIN dbo.Dim_Tiempo v ON v.Tiempo_SK=f.FechaEnvio_SK
 WHERE c.Cliente_SK IS NULL OR e.Empleado_SK IS NULL OR p.Producto_SK IS NULL OR t.Tiempo_SK IS NULL
 OR p.ProductID<>f.ProductID OR (f.Transportista_SK IS NOT NULL AND s.Transportista_SK IS NULL)
 OR (f.FechaRequerida_SK IS NOT NULL AND r.Tiempo_SK IS NULL) OR (f.FechaEnvio_SK IS NOT NULL AND v.Tiempo_SK IS NULL)) ReferenciasInvalidas,
 (SELECT COUNT_BIG(*) FROM(SELECT OrderID,ProductID FROM dbo.Fact_Ventas GROUP BY OrderID,ProductID HAVING COUNT(*)>1) x) LineasDuplicadas,
 (SELECT COUNT_BIG(*) FROM(
 SELECT CustomerID AS Clave FROM dbo.Dim_Cliente GROUP BY CustomerID HAVING COUNT(*)>1
 UNION ALL SELECT CONVERT(nvarchar(20),EmployeeID) FROM dbo.Dim_Empleado GROUP BY EmployeeID HAVING COUNT(*)>1
 UNION ALL SELECT CONVERT(nvarchar(20),ProductID) FROM dbo.Dim_Producto GROUP BY ProductID HAVING COUNT(*)>1
 UNION ALL SELECT CONVERT(nvarchar(20),ShipperID) FROM dbo.Dim_Transportista GROUP BY ShipperID HAVING COUNT(*)>1
 UNION ALL SELECT CONVERT(nvarchar(20),Fecha,112) FROM dbo.Dim_Tiempo GROUP BY Fecha HAVING COUNT(*)>1) x) DimensionesDuplicadas,
 (SELECT COUNT_BIG(*) FROM dbo.Fact_Ventas f
 CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(CONVERT(decimal(5,0),Cantidad)*PrecioUnitario,2)))) b(Bruto)
 CROSS APPLY(VALUES(CONVERT(decimal(18,2),ROUND(b.Bruto*Descuento,2)))) d(DescuentoImporte)
 WHERE ImporteBruto<>b.Bruto OR ImporteDescuento<>d.DescuentoImporte OR ImporteNeto<>b.Bruto-d.DescuentoImporte) ImportesInvalidos;
'@ -Transaction $WarehouseTransaction
        foreach($column in $integrity.Columns){
            $name=$column.ColumnName
            [pscustomobject]@{Comprobacion=$name;Origen=0;DW=$integrity.Rows[0][$name];Coincide=($integrity.Rows[0][$name] -eq 0)}
        }
    } finally {$source.Dispose();if($ownWarehouse -and $null -ne $WarehouseConnection){$WarehouseConnection.Dispose()}}
}

Export-ModuleMember -Function Get-NorthwindWarehouseComparison
