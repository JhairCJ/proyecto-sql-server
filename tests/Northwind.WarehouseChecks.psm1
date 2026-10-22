Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force

function New-MetricsConnection([string]$Database,[string]$Server) {
    if($Database -notin @('NorthWind','Northwind_DW')){
        return New-NorthwindTestConnection -Database $Database -Server $Server
    }
    $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server;$builder['Initial Catalog']=$Database
    $builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
    $connection=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try{$connection.Open();return $connection}catch{$connection.Dispose();throw}
}

function Read-WarehouseMetrics {
    param($Connection,[string]$Sql,$Transaction)
    $command=$Connection.CreateCommand()
    if($null -ne $Transaction){$command.Transaction=$Transaction}
    $command.CommandText=$Sql
    $command.CommandTimeout=120
    $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($command)
    $table=[System.Data.DataTable]::new()
    try{[void]$adapter.Fill($table);return ,$table}
    finally{$adapter.Dispose();$command.Dispose()}
}

function Get-NorthwindWarehouseComparison {
    [CmdletBinding()]
    param(
        [string]$Server='localhost',
        [ValidatePattern('^(Northwind_DW|Northwind_DW_(?:[A-Za-z0-9]+_)*Test)$')]
        [string]$WarehouseDatabase='Northwind_DW_Test',
        $WarehouseConnection,
        $WarehouseTransaction
    )
    $ErrorActionPreference='Stop'
    $sourceDatabase=if($WarehouseDatabase -eq 'Northwind_DW'){'NorthWind'}else{'Northwind_Test'}
    $source=New-MetricsConnection -Database $sourceDatabase -Server $Server
    $ownWarehouse=$null -eq $WarehouseConnection
    try {
        if($ownWarehouse){$WarehouseConnection=New-MetricsConnection -Database $WarehouseDatabase -Server $Server}
        $src=Read-WarehouseMetrics $source @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.Customers) Customers,
       (SELECT COUNT_BIG(*) FROM dbo.Employees) Employees,
       (SELECT COUNT_BIG(*) FROM dbo.Products) Products,
       (SELECT COUNT_BIG(*) FROM dbo.Shippers) Shippers,
       (SELECT COUNT_BIG(*) FROM dbo.Suppliers) Suppliers,
       COUNT_BIG(*) Lines,
       COUNT_BIG(DISTINCT OrderID) Orders,
       COALESCE(SUM(CONVERT(BIGINT,Quantity)),0) Units,
       COALESCE(SUM(amounts.GrossAmount),0) GrossAmount,
       COALESCE(SUM(amounts.DiscountAmount),0) DiscountAmount,
       COALESCE(SUM(amounts.NetAmount),0) NetAmount,
       (SELECT COUNT_BIG(*) FROM dbo.Orders WHERE Freight IS NULL) MissingFreightOrders,
       (SELECT COALESCE(SUM(CONVERT(DECIMAL(19,4),Freight)),0) FROM dbo.Orders) FreightTotal
FROM dbo.OrderDetails
CROSS APPLY
(
    SELECT gross.GrossAmount,
           CONVERT(DECIMAL(19,2),ROUND(gross.GrossAmount*CONVERT(DECIMAL(9,6),Discount),2)) AS DiscountAmount,
           CONVERT(DECIMAL(19,2),gross.GrossAmount-
               ROUND(gross.GrossAmount*CONVERT(DECIMAL(9,6),Discount),2)) AS NetAmount
    FROM (VALUES(CONVERT(DECIMAL(19,2),ROUND(CONVERT(DECIMAL(5,0),Quantity)*
        CONVERT(DECIMAL(19,4),UnitPrice),2)))) AS gross(GrossAmount)
) AS amounts;
'@
        $dst=Read-WarehouseMetrics $WarehouseConnection @'
IF DB_NAME() NOT IN(N'Northwind_DW',N'Northwind_DW_Test') AND DB_NAME() NOT LIKE N'Northwind_DW[_]%[_]Test'
    THROW 52201,'Comparación requiere Northwind_DW o una copia DW de prueba.',1;
SELECT (SELECT COUNT_BIG(*) FROM dbo.DimCustomer WHERE CustomerKey<>0) Customers,
       (SELECT COUNT_BIG(*) FROM dbo.DimEmployee WHERE EmployeeKey<>0) Employees,
       (SELECT COUNT_BIG(*) FROM dbo.DimProduct) Products,
       (SELECT COUNT_BIG(*) FROM dbo.DimShipper WHERE ShipperKey<>0) Shippers,
       (SELECT COUNT_BIG(*) FROM dbo.DimSupplier WHERE SupplierKey<>0) Suppliers,
       COUNT_BIG(*) Lines,
       COUNT_BIG(DISTINCT OrderID) Orders,
       COALESCE(SUM(CONVERT(BIGINT,Quantity)),0) Units,
       COALESCE(SUM(GrossAmount),0) GrossAmount,
       COALESCE(SUM(DiscountAmount),0) DiscountAmount,
       COALESCE(SUM(NetAmount),0) NetAmount,
       (SELECT COUNT_BIG(*) FROM
          (SELECT OrderID FROM dbo.FactSales GROUP BY OrderID HAVING COUNT(Freight)=0) missing) MissingFreightOrders,
       (SELECT COALESCE(SUM(Freight),0) FROM
          (SELECT OrderID,MAX(Freight) Freight FROM dbo.FactSales GROUP BY OrderID) orders) FreightTotal
FROM dbo.FactSales;
'@ -Transaction $WarehouseTransaction
        foreach($column in $src.Columns){
            $name=$column.ColumnName
            [pscustomobject]@{
                Comprobacion=$name
                Origen=$src.Rows[0][$name]
                DW=$dst.Rows[0][$name]
                Coincide=($src.Rows[0][$name] -eq $dst.Rows[0][$name])
            }
        }

        $integrity=Read-WarehouseMetrics $WarehouseConnection @'
SELECT
 (SELECT COUNT_BIG(*) FROM dbo.FactSales f
   LEFT JOIN dbo.DimDate od ON od.DateKey=f.OrderDateKey
   LEFT JOIN dbo.DimDate rd ON rd.DateKey=f.RequiredDateKey
   LEFT JOIN dbo.DimDate sd ON sd.DateKey=f.ShippedDateKey
   LEFT JOIN dbo.DimProduct p ON p.ProductKey=f.ProductKey
   LEFT JOIN dbo.DimCustomer c ON c.CustomerKey=f.CustomerKey
   LEFT JOIN dbo.DimEmployee e ON e.EmployeeKey=f.EmployeeKey
   LEFT JOIN dbo.DimShipper sh ON sh.ShipperKey=f.ShipperKey
   LEFT JOIN dbo.DimSupplier su ON su.SupplierKey=f.SupplierKey
   LEFT JOIN dbo.DimGeography g ON g.GeographyKey=f.GeographyKey
   WHERE od.DateKey IS NULL OR p.ProductKey IS NULL OR c.CustomerKey IS NULL
      OR e.EmployeeKey IS NULL OR sh.ShipperKey IS NULL OR su.SupplierKey IS NULL
      OR g.GeographyKey IS NULL
      OR (f.RequiredDateKey IS NOT NULL AND rd.DateKey IS NULL)
      OR (f.ShippedDateKey IS NOT NULL AND sd.DateKey IS NULL)) InvalidReferences,
 (SELECT COUNT_BIG(*) FROM
   (SELECT OrderID FROM dbo.FactSales GROUP BY OrderID
    HAVING MIN(Freight)<>MAX(Freight) OR (COUNT(Freight)>0 AND COUNT(Freight)<COUNT_BIG(*))) x) InconsistentFreight,
 (SELECT COUNT_BIG(*) FROM
   (SELECT ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry
    FROM dbo.DimGeography GROUP BY ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry
    HAVING COUNT_BIG(*)>1) x) DuplicateDestinations,
 (SELECT COUNT_BIG(*) FROM sys.columns
    WHERE object_id=OBJECT_ID(N'dbo.FactSales') AND name=N'FreightAmount') FreightAmountColumns;
'@ -Transaction $WarehouseTransaction
        foreach($column in $integrity.Columns){
            $name=$column.ColumnName
            [pscustomobject]@{
                Comprobacion=$name
                Origen=0
                DW=$integrity.Rows[0][$name]
                Coincide=($integrity.Rows[0][$name] -eq 0)
            }
        }

        $sourceRows=Read-WarehouseMetrics $source @'
SELECT o.OrderID,d.ProductID,p.SupplierID,CONVERT(DECIMAL(19,4),o.Freight) Freight,
       NULLIF(LTRIM(RTRIM(o.ShipAddress)),N'') ShipAddress,
       NULLIF(LTRIM(RTRIM(o.ShipCity)),N'') ShipCity,
       NULLIF(LTRIM(RTRIM(o.ShipRegion)),N'') ShipRegion,
       NULLIF(LTRIM(RTRIM(o.ShipPostalCode)),N'') ShipPostalCode,
       NULLIF(LTRIM(RTRIM(o.ShipCountry)),N'') ShipCountry
FROM dbo.OrderDetails d
JOIN dbo.Orders o ON o.OrderID=d.OrderID
JOIN dbo.Products p ON p.ProductID=d.ProductID
ORDER BY o.OrderID,d.ProductID;
'@
        $targetRows=Read-WarehouseMetrics $WarehouseConnection @'
SELECT f.OrderID,p.ProductID,NULLIF(s.SupplierID,0) SupplierID,f.Freight,
       g.ShipAddress,g.ShipCity,g.ShipRegion,g.ShipPostalCode,g.ShipCountry
FROM dbo.FactSales f
JOIN dbo.DimProduct p ON p.ProductKey=f.ProductKey
JOIN dbo.DimSupplier s ON s.SupplierKey=f.SupplierKey
JOIN dbo.DimGeography g ON g.GeographyKey=f.GeographyKey
ORDER BY f.OrderID,p.ProductID;
'@ -Transaction $WarehouseTransaction
        $targetByLine=@{}
        foreach($row in $targetRows.Rows){$targetByLine["$($row.OrderID)/$($row.ProductID)"]=$row}
        $supplierMismatch=0;$freightMismatch=0;$destinationMismatch=0
        foreach($row in $sourceRows.Rows){
            $key="$($row.OrderID)/$($row.ProductID)"
            if(-not $targetByLine.ContainsKey($key)){$supplierMismatch++;$freightMismatch++;$destinationMismatch++;continue}
            $target=$targetByLine[$key]
            $sourceSupplier=if($row.SupplierID -is [DBNull]){$null}else{[int]$row.SupplierID}
            $targetSupplier=if($target.SupplierID -is [DBNull]){$null}else{[int]$target.SupplierID}
            if($sourceSupplier -ne $targetSupplier){$supplierMismatch++}
            $sourceFreight=if($row.Freight -is [DBNull]){$null}else{[decimal]$row.Freight}
            $targetFreight=if($target.Freight -is [DBNull]){$null}else{[decimal]$target.Freight}
            if($sourceFreight -ne $targetFreight){$freightMismatch++}
            foreach($column in @('ShipAddress','ShipCity','ShipRegion','ShipPostalCode','ShipCountry')){
                $sourceValue=if($row[$column] -is [DBNull]){$null}else{[string]$row[$column]}
                $targetValue=if($target[$column] -is [DBNull]){$null}else{[string]$target[$column]}
                if($sourceValue -cne $targetValue){$destinationMismatch++;break}
            }
        }
        foreach($check in @(
            [pscustomobject]@{Name='SupplierMismatches';Value=$supplierMismatch},
            [pscustomobject]@{Name='FreightSourceMismatches';Value=$freightMismatch},
            [pscustomobject]@{Name='DestinationMismatches';Value=$destinationMismatch}
        )){
            [pscustomobject]@{Comprobacion=$check.Name;Origen=0;DW=$check.Value;Coincide=($check.Value -eq 0)}
        }
    } finally {
        $source.Dispose()
        if($ownWarehouse -and $null -ne $WarehouseConnection){$WarehouseConnection.Dispose()}
    }
}

Export-ModuleMember -Function Get-NorthwindWarehouseComparison
