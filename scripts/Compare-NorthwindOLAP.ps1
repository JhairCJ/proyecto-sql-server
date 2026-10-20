[CmdletBinding()]
param(
    [string]$SqlServer='localhost',
    [ValidatePattern('^(Northwind_DW|Northwind_DW_(?:[A-Za-z0-9]+_)*Test)$')]
    [string]$WarehouseDatabase='Northwind_DW_Test',
    [string]$AnalysisServer='localhost',
    [ValidateSet('NorthwindOLAP','NorthwindOLAP_Test')]
    [string]$ModelDatabase='NorthwindOLAP_Test',
    [string]$CustomerId='ALFKI',
    [string]$EvidenceDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$expectedModel=if($WarehouseDatabase -eq 'Northwind_DW'){'NorthwindOLAP'}else{'NorthwindOLAP_Test'}
if($ModelDatabase -ne $expectedModel){throw 'Use Northwind_DW/NorthwindOLAP together or a marked test DW/NorthwindOLAP_Test.'}
if([string]::IsNullOrWhiteSpace($EvidenceDirectory)){$EvidenceDirectory=Join-Path $PSScriptRoot '../docs/evidencias/olap'}
New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
& (Join-Path $PSScriptRoot 'Import-NorthwindAnalysisServices.ps1') -Adomd

function Invoke-DaxRow([string]$Query) {
    $connection=[Microsoft.AnalysisServices.AdomdClient.AdomdConnection]::new("Data Source=$AnalysisServer;Initial Catalog=$ModelDatabase")
    try{
        $connection.Open();$command=$connection.CreateCommand();$command.CommandText=$Query
        $reader=$command.ExecuteReader()
        try{
            if(-not $reader.Read()){throw 'La consulta DAX no devolvió fila.'}
            $row=[ordered]@{}
            for($i=0;$i -lt $reader.FieldCount;$i++){
                $value=$reader.GetValue($i);if($value -is [DBNull]){$value=$null}
                $row[$reader.GetName($i).TrimStart('[').TrimEnd(']')]=$value
            }
            return [pscustomobject]$row
        }finally{$reader.Dispose();$command.Dispose()}
    }finally{$connection.Dispose()}
}

function Invoke-SqlRow([string]$Sql,[hashtable]$Parameters=@{}) {
    $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$SqlServer;$builder['Initial Catalog']=$WarehouseDatabase
    $builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
    $connection=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try{
        $connection.Open();$command=$connection.CreateCommand();$command.CommandTimeout=120;$command.CommandText=$Sql
        foreach($name in $Parameters.Keys){[void]$command.Parameters.AddWithValue($name,$Parameters[$name])}
        $reader=$command.ExecuteReader()
        try{
            if(-not $reader.Read()){throw 'La consulta SQL no devolvió fila.'}
            $row=[ordered]@{}
            for($i=0;$i -lt $reader.FieldCount;$i++){
                $value=$reader.GetValue($i);if($value -is [DBNull]){$value=$null};$row[$reader.GetName($i)]=$value
            }
            return [pscustomobject]$row
        }finally{$reader.Dispose();$command.Dispose()}
    }finally{$connection.Dispose()}
}

function Assert-Equal($Actual,$Expected,[string]$Name,[int]$Scale=0) {
    if($null -eq $Actual -or $null -eq $Expected){if($null -ne $Actual -or $null -ne $Expected){throw "${Name}: modelo='$Actual', DW='$Expected'."};return}
    $actualValue=if($Scale){[decimal]::Round([decimal]$Actual,$Scale)}else{[decimal]$Actual}
    $expectedValue=if($Scale){[decimal]::Round([decimal]$Expected,$Scale)}else{[decimal]$Expected}
    if($actualValue -ne $expectedValue){throw "${Name}: modelo='$actualValue', DW='$expectedValue'."}
}

$preflight=Invoke-SqlRow @'
SELECT (SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID(N'dbo') AND name IN
 (N'DimDate',N'DimProduct',N'DimCustomer',N'DimEmployee',N'DimShipper',N'DimSupplier',N'DimGeography',N'FactSales')) AS ModelTables,
 (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.FactSales')) AS FactRelationships,
 (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.FactSales') AND name=N'FreightAmount') AS FreightAmountColumns,
 (SELECT COUNT(*) FROM (SELECT OrderID FROM dbo.FactSales GROUP BY OrderID
   HAVING MIN(Freight)<>MAX(Freight) OR (COUNT(Freight)>0 AND COUNT(Freight)<COUNT_BIG(*))) AS x) AS InconsistentFreight;
'@
if($preflight.ModelTables -ne 8 -or $preflight.FactRelationships -ne 9 -or $preflight.FreightAmountColumns -ne 0 -or $preflight.InconsistentFreight -ne 0){
    throw 'DW no tiene las ocho tablas/nueve relaciones esperadas, contiene Freight inconsistente o tiene FreightAmount.'
}

$sqlOverall=Invoke-SqlRow @'
WITH OrderFreight AS (SELECT OrderID,MAX(Freight) Freight FROM dbo.FactSales GROUP BY OrderID)
SELECT COUNT(DISTINCT f.OrderID) Orders,SUM(CONVERT(bigint,f.Quantity)) Units,
 SUM(f.GrossAmount) GrossAmount,SUM(f.DiscountAmount) DiscountAmount,SUM(f.NetAmount) NetAmount,
 (SELECT COALESCE(SUM(Freight),0) FROM OrderFreight) Freight,
 (SELECT COUNT_BIG(*) FROM OrderFreight WHERE Freight IS NULL) MissingFreightOrders
FROM dbo.FactSales AS f;
'@
$daxOverall=Invoke-DaxRow @'
EVALUATE ROW(
 "Orders",[Pedidos distintos],"Units",[Unidades],"GrossAmount",[Ventas brutas],
 "DiscountAmount",[Descuentos aplicados],"NetAmount",[Ventas netas],
 "Freight",[Flete total],"MissingFreightOrders",[Pedidos sin flete informado])
'@
foreach($name in @('Orders','Units','GrossAmount','DiscountAmount','NetAmount','Freight','MissingFreightOrders')){
    $scale=if($name -in @('GrossAmount','DiscountAmount','NetAmount')){2}elseif($name -eq 'Freight'){4}else{0}
    Assert-Equal $daxOverall.$name $sqlOverall.$name "Total $name" $scale
}

$orderSql=Invoke-SqlRow @'
SELECT COUNT(DISTINCT OrderID) Orders,SUM(CONVERT(bigint,Quantity)) Units,
 SUM(GrossAmount) GrossAmount,SUM(DiscountAmount) DiscountAmount,SUM(NetAmount) NetAmount,
 MAX(Freight) Freight
FROM dbo.FactSales WHERE OrderID=10248;
'@
$orderDax=Invoke-DaxRow @'
EVALUATE CALCULATETABLE(ROW(
 "Orders",[Pedidos distintos],"Units",[Unidades],"GrossAmount",[Ventas brutas],
 "DiscountAmount",[Descuentos aplicados],"NetAmount",[Ventas netas],"Freight",[Flete total]),
 FactSales[OrderID]=10248)
'@
foreach($name in @('Orders','Units','GrossAmount','DiscountAmount','NetAmount','Freight')){
    $scale=if($name -in @('GrossAmount','DiscountAmount','NetAmount')){2}elseif($name -eq 'Freight'){4}else{0}
    Assert-Equal $orderDax.$name $orderSql.$name "Order 10248 $name" $scale
}

$customer=Invoke-SqlRow @'
SELECT TOP(1) CustomerID,Country FROM dbo.DimCustomer WHERE CustomerID=@CustomerId;
'@ @{ '@CustomerId'=$CustomerId }
if($null -eq $customer.Country){throw "Customer '$CustomerId' has no country for the location filter."}
$customerSql=Invoke-SqlRow @'
SELECT COUNT(DISTINCT f.OrderID) Orders,SUM(CONVERT(bigint,f.Quantity)) Units,SUM(f.NetAmount) NetAmount
FROM dbo.FactSales AS f JOIN dbo.DimCustomer AS c ON c.CustomerKey=f.CustomerKey
WHERE c.CustomerID=@CustomerId AND c.Country=@Country;
'@ @{ '@CustomerId'=$CustomerId;'@Country'=$customer.Country }
$escapedCustomer=([string]$CustomerId).Replace('"','""');$escapedCountry=([string]$customer.Country).Replace('"','""')
$customerDax=Invoke-DaxRow @"
EVALUATE CALCULATETABLE(ROW("Orders",[Pedidos distintos],"Units",[Unidades],"NetAmount",[Ventas netas]),
 DimCustomer[CustomerID]="$escapedCustomer",DimCustomer[Country]="$escapedCountry")
"@
foreach($name in @('Orders','Units','NetAmount')){Assert-Equal $customerDax.$name $customerSql.$name "Customer location $name" $(if($name -eq 'NetAmount'){2}else{0})}

$destination=Invoke-SqlRow @'
SELECT TOP(1) g.GeographyKey,g.ShipCountry FROM dbo.FactSales AS f
JOIN dbo.DimGeography AS g ON g.GeographyKey=f.GeographyKey
WHERE f.OrderID=10248 ORDER BY g.GeographyKey;
'@
$destinationSql=Invoke-SqlRow @'
SELECT COUNT(DISTINCT f.OrderID) Orders,SUM(CONVERT(bigint,f.Quantity)) Units,SUM(f.NetAmount) NetAmount
FROM dbo.FactSales AS f JOIN dbo.DimGeography AS g ON g.GeographyKey=f.GeographyKey
WHERE f.OrderID=10248 AND g.GeographyKey=@GeographyKey;
'@ @{ '@GeographyKey'=$destination.GeographyKey }
$destinationDax=Invoke-DaxRow "EVALUATE CALCULATETABLE(ROW(`"Orders`",[Pedidos distintos],`"Units`",[Unidades],`"NetAmount`",[Ventas netas]),FactSales[OrderID]=10248,DimGeography[GeographyKey]=$($destination.GeographyKey))"
foreach($name in @('Orders','Units','NetAmount')){Assert-Equal $destinationDax.$name $destinationSql.$name "Order destination $name" $(if($name -eq 'NetAmount'){2}else{0})}

$supplier=Invoke-SqlRow @'
SELECT TOP(1) s.SupplierID,s.SupplierKey FROM dbo.FactSales AS f
JOIN dbo.DimSupplier AS s ON s.SupplierKey=f.SupplierKey
WHERE f.OrderID=10248 ORDER BY s.SupplierKey;
'@
$supplierSql=Invoke-SqlRow @'
SELECT COUNT(DISTINCT f.OrderID) Orders,SUM(CONVERT(bigint,f.Quantity)) Units,SUM(f.NetAmount) NetAmount
FROM dbo.FactSales AS f JOIN dbo.DimSupplier AS s ON s.SupplierKey=f.SupplierKey
WHERE f.OrderID=10248 AND s.SupplierKey=@SupplierKey;
'@ @{ '@SupplierKey'=$supplier.SupplierKey }
$supplierDax=Invoke-DaxRow "EVALUATE CALCULATETABLE(ROW(`"Orders`",[Pedidos distintos],`"Units`",[Unidades],`"NetAmount`",[Ventas netas]),FactSales[OrderID]=10248,DimSupplier[SupplierKey]=$($supplier.SupplierKey))"
foreach($name in @('Orders','Units','NetAmount')){Assert-Equal $supplierDax.$name $supplierSql.$name "Current supplier $name" $(if($name -eq 'NetAmount'){2}else{0})}

$unknown=Invoke-DaxRow @'
EVALUATE ROW(
 "Customer",CALCULATE(SELECTEDVALUE(DimCustomer[CompanyName]),DimCustomer[CustomerKey]=0),
 "Employee",CALCULATE(SELECTEDVALUE(DimEmployee[FullName]),DimEmployee[EmployeeKey]=0),
 "Shipper",CALCULATE(SELECTEDVALUE(DimShipper[CompanyName]),DimShipper[ShipperKey]=0),
 "Supplier",CALCULATE(SELECTEDVALUE(DimSupplier[CompanyName]),DimSupplier[SupplierKey]=0),
 "UnknownDateRows",COUNTROWS(FILTER(DimDate,DimDate[DateKey]=0 && DimDate[IsUnknown]=TRUE())),
 "UnknownDestination",CALCULATE(SELECTEDVALUE(DimGeography[DestinationName]),DimGeography[GeographyKey]=0))
'@
if($unknown.Customer -ne 'Desconocido' -or $unknown.Employee -ne 'Desconocido' -or $unknown.Shipper -ne 'Desconocido' -or $unknown.Supplier -ne 'Desconocido' -or $unknown.UnknownDateRows -ne 1 -or $unknown.UnknownDestination -ne 'Desconocido'){
    throw 'El modelo no muestra de manera clara los miembros desconocidos.'
}

$report=[ordered]@{
    Result='PASS';Server=$AnalysisServer;Model=$ModelDatabase;Warehouse="$SqlServer/$WarehouseDatabase"
    Totals=$daxOverall;Order10248=$orderDax
    CustomerLocation=@{Customer=$CustomerId;Country=$customer.Country;Measures=$customerDax}
    OrderDestination=@{Order=10248;Country=$destination.ShipCountry;Measures=$destinationDax}
    CurrentSupplier=@{SupplierID=$supplier.SupplierID;Measures=$supplierDax}
    UnknownMembers=$unknown;FreightScale=4;FreightConsistency='PASS'
}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$path=Join-Path $EvidenceDirectory "comparacion-olap-$stamp.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
Write-Output "PASS: medidas, fechas, cliente, destino, proveedor actual y flete coinciden con el DW. Evidencia: $path"
