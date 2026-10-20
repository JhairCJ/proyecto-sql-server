[CmdletBinding()]
param(
    [string]$Server='localhost',
    [string]$AnalysisServer='localhost',
    [ValidatePattern('^Northwind_DW_(?:[A-Za-z0-9]+_)*Test$')]
    [string]$WarehouseDatabase='Northwind_DW_Test',
    [string]$EvidenceDirectory=(Join-Path $PSScriptRoot '../docs/evidencias/olap')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ModelDatabase='NorthwindOLAP_Test'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force
& (Join-Path $PSScriptRoot '../scripts/Import-NorthwindAnalysisServices.ps1') -Adomd
New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null

function Read-Data([string]$Database,[string]$Sql,[hashtable]$Parameters=@{},[switch]$Admin) {
    $connection=if($Admin){
        $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
        $builder['Data Source']=$Server;$builder['Initial Catalog']=$Database
        $builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
        $item=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString);$item.Open();$item
    }else{New-NorthwindTestConnection -Database $Database -Server $Server}
    try{
        $command=$connection.CreateCommand();$command.CommandTimeout=120;$command.CommandText=$Sql
        foreach($name in $Parameters.Keys){[void]$command.Parameters.AddWithValue($name,$Parameters[$name])}
        $adapter=[Data.SqlClient.SqlDataAdapter]::new($command);$data=[Data.DataSet]::new()
        try{[void]$adapter.Fill($data);return ,$data}finally{$adapter.Dispose();$command.Dispose()}
    }finally{$connection.Dispose()}
}

function Invoke-DaxRow([string]$Query) {
    $connection=[Microsoft.AnalysisServices.AdomdClient.AdomdConnection]::new("Data Source=$AnalysisServer;Initial Catalog=$ModelDatabase")
    try{
        $connection.Open();$command=$connection.CreateCommand();$command.CommandText=$Query
        $reader=$command.ExecuteReader()
        try{
            if(-not $reader.Read()){throw 'La consulta DAX no devolvió una fila.'}
            $row=[ordered]@{}
            for($i=0;$i -lt $reader.FieldCount;$i++){$value=$reader.GetValue($i);if($value -is [DBNull]){$value=$null};$row[$reader.GetName($i).TrimStart('[').TrimEnd(']')]=$value}
            return [pscustomobject]$row
        }finally{$reader.Dispose();$command.Dispose()}
    }finally{$connection.Dispose()}
}

function Assert-Equal($Actual,$Expected,[string]$Name,[int]$Scale=0) {
    if($null -eq $Actual -or $null -eq $Expected){if($null -ne $Actual -or $null -ne $Expected){throw "${Name}: modelo='$Actual', esperado='$Expected'."};return}
    $a=if($Scale){[decimal]::Round([decimal]$Actual,$Scale)}else{[decimal]$Actual}
    $e=if($Scale){[decimal]::Round([decimal]$Expected,$Scale)}else{[decimal]$Expected}
    if($a -ne $e){throw "${Name}: modelo='$a', esperado='$e'."}
}

$deploy=Join-Path $PSScriptRoot '../scripts/Deploy-NorthwindOLAP.ps1'
$process=Join-Path $PSScriptRoot '../scripts/Process-NorthwindOLAP.ps1'
$compare=Join-Path $PSScriptRoot '../scripts/Compare-NorthwindOLAP.ps1'
$testTools=Join-Path $PSScriptRoot 'Northwind.TestTools.psm1'
$bim=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Northwind.OLAP/Northwind.OLAP.bim') -Raw | ConvertFrom-Json
$expectedTables=@('DimDate','DimProduct','DimCustomer','DimEmployee','DimShipper','DimSupplier','DimGeography','FactSales')
$actualTables=@($bim.model.tables | ForEach-Object name)
if(@($actualTables | Where-Object {$_ -notin $expectedTables}).Count -or @($expectedTables | Where-Object {$_ -notin $actualTables}).Count -or $bim.model.relationships.Count -ne 9){
    throw 'El BIM no declara las ocho tablas finales y sus nueve relaciones.'
}
$factTable=$bim.model.tables | Where-Object name -eq 'FactSales'
if($factTable.measures.Count -ne 21 -or @($factTable.measures | Where-Object name -in @('Flete total','Pedidos sin flete informado')).Count -ne 2){
    throw 'Faltan medidas de flete, por roles de fecha o medidas actuales.'
}
foreach($columnName in @('Freight','GrossAmount','DiscountAmount','NetAmount')){
    $column=$factTable.columns | Where-Object name -eq $columnName
    if(-not $column -or -not $column.isHidden){throw "La columna $columnName debe estar oculta tras medidas explícitas."}
}
if(@($bim.model.relationships | Where-Object { $_.fromTable -eq 'FactSales' -and $_.toTable -eq 'DimDate' -and $_.isActive }).Count -ne 1){
    throw 'La fecha de pedido debe ser la única relación activa de calendario.'
}
$result=[ordered]@{Result='PASS';Model=$ModelDatabase;Warehouse=$WarehouseDatabase;FixtureOrders=@();Checks=[System.Collections.Generic.List[string]]::new()}
$fixturesCreated=$false;$testError=$null;$cleanupError=$null
$baseOrder=2100000000+(Get-Random -Minimum 100000 -Maximum 9000000)
$orderFreight=$baseOrder;$orderNull=$baseOrder+1;$orderZero=$baseOrder+2

try{
    & $deploy -AnalysisServer $AnalysisServer -WarehouseServer $Server -WarehouseDatabase $WarehouseDatabase -ModelDatabase $ModelDatabase
    & $process -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -WarehouseServer $Server -WarehouseDatabase $WarehouseDatabase -LogDirectory (Join-Path $EvidenceDirectory 'procesamientos')
    & $compare -SqlServer $Server -WarehouseDatabase $WarehouseDatabase -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -EvidenceDirectory $EvidenceDirectory
    $result.Checks.Add('Publicación, procesamiento completo y comparación de datos actuales')

    $service=Get-CimInstance Win32_Service -Filter "Name='MSSQLServerOLAPService'"
    $permissionData=Read-Data $WarehouseDatabase @'
DECLARE @principal sysname=@ServicePrincipal;
SELECT o.name TableName,p.permission_name PermissionName,p.state_desc State
FROM sys.database_permissions p
JOIN sys.database_principals u ON u.principal_id=p.grantee_principal_id
JOIN sys.objects o ON o.object_id=p.major_id
WHERE u.name=@principal AND p.class=1 AND p.permission_name=N'SELECT' AND p.state_desc=N'GRANT'
ORDER BY o.name;
'@ @{ '@ServicePrincipal'=[string]$service.StartName } -Admin
    $permissionCommand=$permissionData.Tables[0]
    $permissions=[System.Collections.Generic.List[string]]::new()
    foreach($row in $permissionCommand.Rows){$permissions.Add([string]$row.TableName)}
    if($permissions.Count -ne 8 -or @($permissions | Where-Object {$_ -notin $expectedTables}).Count){
        throw "La cuenta SSAS no tiene exactamente SELECT en las ocho tablas finales: $($permissions -join ', ')."
    }
    $result.Checks.Add('Permisos directos de lectura limitados a las ocho tablas finales')

    $warehouse=New-NorthwindTestConnection -Database $WarehouseDatabase -Server $Server
    try{
        $candidate=$warehouse.CreateCommand()
        $candidate.CommandText=@'
SELECT TOP(30) p.ProductKey,MIN(f.SupplierKey) AS SupplierKey,p.ProductID
FROM dbo.DimProduct AS p JOIN dbo.FactSales AS f ON f.ProductKey=p.ProductKey
WHERE p.ProductID>0 AND f.SupplierKey>0
GROUP BY p.ProductKey,p.ProductID ORDER BY p.ProductID;
'@
        $adapter=[Data.SqlClient.SqlDataAdapter]::new($candidate);$products=[Data.DataTable]::new()
        try{[void]$adapter.Fill($products)}finally{$adapter.Dispose();$candidate.Dispose()}
    }finally{$warehouse.Dispose()}
    $chosen=[System.Collections.Generic.List[object]]::new()
    $supplierGroups=@($products.Rows | Group-Object { [int]$_.SupplierKey })
    $primary=$supplierGroups | Where-Object Count -ge 2 | Select-Object -First 1
    if($null -eq $primary){throw 'No hay dos productos del mismo proveedor para construir el fixture.'}
    $secondary=$supplierGroups | Where-Object {$_.Name -ne $primary.Name} | Select-Object -First 1
    if($null -eq $secondary){throw 'No se encontró un segundo proveedor para probar Freight solapado.'}
    foreach($row in @($primary.Group | Select-Object -First 2)){$chosen.Add([pscustomobject]@{ProductKey=[int]$row.ProductKey;SupplierKey=[int]$row.SupplierKey;ProductID=[int]$row.ProductID})}
    $row=$secondary.Group | Select-Object -First 1
    $chosen.Add([pscustomobject]@{ProductKey=[int]$row.ProductKey;SupplierKey=[int]$row.SupplierKey;ProductID=[int]$row.ProductID})

    $fixtureSql=@"
DECLARE @CustomerKey int=(SELECT CustomerKey FROM dbo.DimCustomer WHERE CustomerID=N'ALFKI'),
        @EmployeeKey int=(SELECT EmployeeKey FROM dbo.DimEmployee WHERE EmployeeID=5),
        @ShipperKey int=(SELECT ShipperKey FROM dbo.DimShipper WHERE ShipperID=3),
        @OrderDateKey int=(SELECT DateKey FROM dbo.DimDate WHERE FullDate='19960704'),
        @RequiredDateKey int=(SELECT DateKey FROM dbo.DimDate WHERE FullDate='19960804'),
        @ShippedDateKey int=(SELECT DateKey FROM dbo.DimDate WHERE FullDate='19960904'),
        @GeographyKey int=(SELECT TOP(1) GeographyKey FROM dbo.FactSales WHERE OrderID=10248 ORDER BY SalesKey);
IF @CustomerKey IS NULL OR @EmployeeKey IS NULL OR @ShipperKey IS NULL OR @OrderDateKey IS NULL
 OR @RequiredDateKey IS NULL OR @ShippedDateKey IS NULL OR @GeographyKey IS NULL
    THROW 52701,'No se pudieron resolver las claves dimensionales del fixture OLAP.',1;
IF EXISTS(SELECT 1 FROM dbo.FactSales WHERE OrderID IN($orderFreight,$orderNull,$orderZero))
    THROW 52702,'Las identidades de fixture ya están ocupadas.',1;
INSERT dbo.FactSales(OrderID,OrderDateKey,RequiredDateKey,ShippedDateKey,ProductKey,CustomerKey,EmployeeKey,
 ShipperKey,SupplierKey,GeographyKey,Quantity,UnitPrice,Discount,Freight,GrossAmount,DiscountAmount,NetAmount)
VALUES
 ($orderFreight,@OrderDateKey,@RequiredDateKey,@ShippedDateKey,$($chosen[0].ProductKey),@CustomerKey,@EmployeeKey,@ShipperKey,$($chosen[0].SupplierKey),@GeographyKey,2,20,0.100000,30.1234,40,4,36),
 ($orderFreight,@OrderDateKey,@RequiredDateKey,@ShippedDateKey,$($chosen[1].ProductKey),@CustomerKey,@EmployeeKey,@ShipperKey,$($chosen[1].SupplierKey),@GeographyKey,4,5,0.050000,30.1234,20,1,19),
 ($orderFreight,@OrderDateKey,@RequiredDateKey,@ShippedDateKey,$($chosen[2].ProductKey),@CustomerKey,@EmployeeKey,@ShipperKey,$($chosen[2].SupplierKey),@GeographyKey,1,10,0.000000,30.1234,10,0,10),
 ($orderNull,@OrderDateKey,@RequiredDateKey,NULL,$($chosen[0].ProductKey),@CustomerKey,@EmployeeKey,@ShipperKey,$($chosen[0].SupplierKey),@GeographyKey,1,10,0.000000,NULL,10,0,10),
 ($orderZero,@OrderDateKey,@RequiredDateKey,@ShippedDateKey,$($chosen[1].ProductKey),@CustomerKey,@EmployeeKey,@ShipperKey,$($chosen[1].SupplierKey),@GeographyKey,1,10,0.000000,0,10,0,10);
"@
    [void](Invoke-NorthwindTestSql -Server $Server -Database $WarehouseDatabase -Sql $fixtureSql -Commit)
    $fixturesCreated=$true;$result.FixtureOrders=@($orderFreight,$orderNull,$orderZero)

    & $process -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -WarehouseServer $Server -WarehouseDatabase $WarehouseDatabase -LogDirectory (Join-Path $EvidenceDirectory 'procesamientos')
    & $compare -SqlServer $Server -WarehouseDatabase $WarehouseDatabase -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -EvidenceDirectory $EvidenceDirectory

    $freight=Invoke-DaxRow "EVALUATE CALCULATETABLE(ROW(""Orders"",[Pedidos distintos],""Units"",[Unidades],""Gross"",[Ventas brutas],""Discount"",[Descuentos aplicados],""Net"",[Ventas netas],""Freight"",[Flete total],""Missing"",[Pedidos sin flete informado],""Required"",[Ventas netas por fecha requerida],""Shipped"",[Ventas netas por fecha de envío]),FactSales[OrderID]=$orderFreight)"
    foreach($pair in @(@('Orders',1,0),@('Units',7,0),@('Gross',70,2),@('Discount',5,2),@('Net',65,2),@('Freight',30.1234,4),@('Missing',0,0),@('Required',65,2),@('Shipped',65,2))){Assert-Equal $freight.($pair[0]) $pair[1] "Flete multi-línea $($pair[0])" $pair[2]}

    $nullFreight=Invoke-DaxRow "EVALUATE CALCULATETABLE(ROW(""Freight"",[Flete total],""Missing"",[Pedidos sin flete informado]),FactSales[OrderID]=$orderNull)"
    Assert-Equal $nullFreight.Freight $null 'Freight NULL';Assert-Equal $nullFreight.Missing 1 'Pedido con Freight NULL'
    $zeroFreight=Invoke-DaxRow "EVALUATE CALCULATETABLE(ROW(""Freight"",[Flete total],""Missing"",[Pedidos sin flete informado]),FactSales[OrderID]=$orderZero)"
    Assert-Equal $zeroFreight.Freight 0 'Freight cero' 4;Assert-Equal $zeroFreight.Missing 0 'Pedido con Freight cero'

    $split=Invoke-DaxRow "EVALUATE ROW(""FirstSupplier"",CALCULATE([Flete total],FactSales[OrderID]=$orderFreight,DimSupplier[SupplierKey]=$($chosen[0].SupplierKey)),""SecondSupplier"",CALCULATE([Flete total],FactSales[OrderID]=$orderFreight,DimSupplier[SupplierKey]=$($chosen[1].SupplierKey)))"
    Assert-Equal $split.FirstSupplier 30.1234 'Subtotal flete primer proveedor' 4
    Assert-Equal $split.SecondSupplier 30.1234 'Subtotal flete segundo proveedor' 4
    if(([decimal]$split.FirstSupplier+[decimal]$split.SecondSupplier) -le [decimal]$freight.Freight){throw 'El fixture no demuestra que los grupos de proveedor se solapan en Freight.'}
    $result.FreightFixture=$freight;$result.NullFreight=$nullFreight;$result.ZeroFreight=$zeroFreight;$result.SupplierSubtotals=$split
    $result.Checks.Add('Flete de 30.1234 en tres líneas se cuenta una vez; los subtotales por proveedor pueden solaparse')
    $result.Checks.Add('Freight NULL y cero se distinguen; las medidas por fecha requerida y envío filtran')

    $processLogDirectory=Join-Path $EvidenceDirectory 'procesamientos'
    $failed=$false
    try{& $process -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -WarehouseServer $Server -WarehouseDatabase 'Northwind_DW_OLAP_Missing_Test' -LogDirectory $processLogDirectory}catch{$failed=$true}
    if(-not $failed){throw 'El procesamiento con una fuente inexistente no falló.'}
    $failureLog=Get-ChildItem -LiteralPath $processLogDirectory -Filter 'NorthwindOLAP-*.log' -File |
        Sort-Object LastWriteTime -Descending | Where-Object {(Get-Content -LiteralPath $_.FullName -Raw).Contains('WarehouseDatabase=Northwind_DW_OLAP_Missing_Test')} | Select-Object -First 1
    if(-not $failureLog){throw 'No se registró el fallo de procesamiento.'}
    $failureText=Get-Content -LiteralPath $failureLog.FullName -Raw
    if(-not $failureText.Contains('Result=FAILED') -or -not $failureText.Contains('SourceRestored=True')){throw 'El error no se registró o el origen no se restauró.'}
    & $process -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -WarehouseServer $Server -WarehouseDatabase $WarehouseDatabase -LogDirectory $processLogDirectory
    $result.Checks.Add('Fallo de procesamiento registrado, origen restaurado y reproceso correcto')
}
catch{$testError=$_.Exception.Message}
finally{
    if($fixturesCreated){
        try{
            [void](Invoke-NorthwindTestSql -Server $Server -Database $WarehouseDatabase -Sql "DELETE dbo.FactSales WHERE OrderID IN($orderFreight,$orderNull,$orderZero); IF @@ROWCOUNT<>5 THROW 52703,'No se limpiaron las cinco líneas del fixture.',1;" -Commit)
            & $process -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -WarehouseServer $Server -WarehouseDatabase $WarehouseDatabase -LogDirectory (Join-Path $EvidenceDirectory 'procesamientos')
            & $compare -SqlServer $Server -WarehouseDatabase $WarehouseDatabase -AnalysisServer $AnalysisServer -ModelDatabase $ModelDatabase -EvidenceDirectory $EvidenceDirectory
            $result.Cleanup='PASS'
        }catch{$cleanupError=$_.Exception.Message}
    }
}

$result.TestError=$testError;$result.CleanupError=$cleanupError
$result.Result=if($testError -or $cleanupError){'FAILED'}else{'PASS'}
$result.OriginalWarehouse='No se utilizó Northwind_DW ni NorthWind como destino de escritura.'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$reportPath=Join-Path (Resolve-Path -LiteralPath $EvidenceDirectory).Path "integracion-olap-$stamp.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
if($cleanupError){throw "No se pudo limpiar/reprocesar OLAP: $cleanupError. Evidencia: $reportPath"}
if($testError){throw "Falló la integración OLAP: $testError. Evidencia: $reportPath"}
Write-Output "PASS: ocho tablas, permisos, relaciones de fechas, filtros, Freight NULL/cero/una vez y limpieza. Evidencia: $reportPath"
