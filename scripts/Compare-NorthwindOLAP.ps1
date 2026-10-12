[CmdletBinding()]
param(
    [string]$SqlServer = 'localhost',
    [ValidateSet('Northwind_DW_Test')]
    [string]$WarehouseDatabase = 'Northwind_DW_Test',
    [string]$AnalysisServer = 'localhost',
    [ValidateSet('NorthwindOLAP_Test')]
    [string]$ModelDatabase = 'NorthwindOLAP_Test',
    [string]$Category = 'Beverages',
    [int]$Year = 1996,
    [string]$CustomerId = 'ALFKI',
    [string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $PSScriptRoot '../docs/evidencias/olap'
}

& (Join-Path $PSScriptRoot 'Import-NorthwindAnalysisServices.ps1') -Adomd

function Invoke-DaxRow([string]$Query) {
    $connection = [Microsoft.AnalysisServices.AdomdClient.AdomdConnection]::new(
        "Data Source=$AnalysisServer;Initial Catalog=$ModelDatabase"
    )
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read()) {
                throw 'La consulta DAX no devolvió una fila.'
            }
            $row = [ordered]@{}
            for ($index = 0; $index -lt $reader.FieldCount; $index++) {
                $value = $reader.GetValue($index)
                if ($value -is [System.DBNull]) { $value = $null }
                $name = $reader.GetName($index).TrimStart('[').TrimEnd(']')
                $row[$name] = $value
            }
            return [pscustomobject]$row
        }
        finally {
            $reader.Dispose()
            $command.Dispose()
        }
    }
    finally {
        $connection.Dispose()
    }
}

function Invoke-SqlRow([string]$Database, [string]$Sql, [hashtable]$Parameters = @{}) {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $SqlServer
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Sql
        foreach ($name in $Parameters.Keys) {
            [void]$command.Parameters.AddWithValue($name, $Parameters[$name])
        }
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read()) {
                throw 'La consulta SQL no devolvió una fila.'
            }
            $row = [ordered]@{}
            for ($index = 0; $index -lt $reader.FieldCount; $index++) {
                $value = $reader.GetValue($index)
                if ($value -is [System.DBNull]) { $value = $null }
                $row[$reader.GetName($index)] = $value
            }
            return [pscustomobject]$row
        }
        finally {
            $reader.Dispose()
            $command.Dispose()
        }
    }
    finally {
        $connection.Dispose()
    }
}

function Assert-Equal($Actual, $Expected, [string]$Name, [int]$Scale = 0) {
    if ($null -eq $Actual -or $null -eq $Expected) {
        if ($null -ne $Actual -or $null -ne $Expected) {
            throw "$Name no coincide: modelo='$Actual', DW='$Expected'."
        }
        return
    }
    $actualValue = if ($Scale -gt 0) { [decimal]::Round([decimal]$Actual, $Scale) } else { [decimal]$Actual }
    $expectedValue = if ($Scale -gt 0) { [decimal]::Round([decimal]$Expected, $Scale) } else { [decimal]$Expected }
    if ($actualValue -ne $expectedValue) {
        throw "$Name no coincide: modelo='$actualValue', DW='$expectedValue'."
    }
}

$overallSql = Invoke-SqlRow $WarehouseDatabase @'
SELECT COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint, Cantidad)) AS Unidades,
       SUM(ImporteBruto) AS Bruto,
       SUM(ImporteDescuento) AS Descuento,
       SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas;
'@
$overallDax = Invoke-DaxRow @'
EVALUATE ROW(
    "Pedidos", [Pedidos distintos],
    "Unidades", [Unidades],
    "Bruto", [Ventas brutas],
    "Descuento", [Descuentos aplicados],
    "Neto", [Ventas netas]
)
'@
foreach ($measure in @('Pedidos', 'Unidades', 'Bruto', 'Descuento', 'Neto')) {
    $scale = if ($measure -in @('Bruto', 'Descuento', 'Neto')) { 2 } else { 0 }
    Assert-Equal $overallDax.$measure $overallSql.$measure "Total $measure" $scale
}

$orderSql = Invoke-SqlRow $WarehouseDatabase @'
SELECT COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint, Cantidad)) AS Unidades,
       SUM(ImporteBruto) AS Bruto,
       SUM(ImporteDescuento) AS Descuento,
       SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas WHERE OrderID = 10248;
'@
$orderDax = Invoke-DaxRow @'
EVALUATE ROW(
    "Pedidos", CALCULATE([Pedidos distintos], Fact_Ventas[OrderID] = 10248),
    "Unidades", CALCULATE([Unidades], Fact_Ventas[OrderID] = 10248),
    "Bruto", CALCULATE([Ventas brutas], Fact_Ventas[OrderID] = 10248),
    "Descuento", CALCULATE([Descuentos aplicados], Fact_Ventas[OrderID] = 10248),
    "Neto", CALCULATE([Ventas netas], Fact_Ventas[OrderID] = 10248)
)
'@
foreach ($measure in @('Pedidos', 'Unidades', 'Bruto', 'Descuento', 'Neto')) {
    $scale = if ($measure -in @('Bruto', 'Descuento', 'Neto')) { 2 } else { 0 }
    Assert-Equal $orderDax.$measure $orderSql.$measure "Pedido 10248: $measure" $scale
}

$categorySql = Invoke-SqlRow $WarehouseDatabase @'
SELECT SUM(f.ImporteNeto) AS Neto
FROM dbo.Fact_Ventas AS f
JOIN dbo.Dim_Tiempo AS t ON t.Tiempo_SK = f.FechaPedido_SK
JOIN dbo.Dim_Producto AS p ON p.Producto_SK = f.Producto_SK
WHERE t.Anio = @Year AND p.Categoria = @Category;
'@ @{ '@Year' = $Year; '@Category' = $Category }
$escapedCategory = $Category.Replace('"', '""')
$categoryDax = Invoke-DaxRow @"
EVALUATE ROW(
    "Neto",
    CALCULATE([Ventas netas], Dim_Tiempo[Anio] = $Year, Dim_Producto[Categoria] = "$escapedCategory")
)
"@
Assert-Equal $categoryDax.Neto $categorySql.Neto "Categoría $Category / año $Year" 2

$customerSql = Invoke-SqlRow $WarehouseDatabase @'
SELECT COUNT(DISTINCT f.OrderID) AS Pedidos,
       SUM(CONVERT(bigint, f.Cantidad)) AS Unidades,
       SUM(f.ImporteBruto) AS Bruto,
       SUM(f.ImporteDescuento) AS Descuento,
       SUM(f.ImporteNeto) AS Neto
FROM dbo.Fact_Ventas AS f
JOIN dbo.Dim_Cliente AS c ON c.Cliente_SK = f.Cliente_SK
WHERE c.CustomerID = @CustomerId;
'@ @{ '@CustomerId' = $CustomerId }
$customerCountry = (Invoke-SqlRow $WarehouseDatabase @'
SELECT Pais FROM dbo.Dim_Cliente WHERE CustomerID = @CustomerId;
'@ @{ '@CustomerId' = $CustomerId }).Pais
if ($null -eq $customerCountry) {
    throw "No se encontró el país del cliente '$CustomerId'."
}
$escapedCustomer = $CustomerId.Replace('"', '""')
$escapedCountry = ([string]$customerCountry).Replace('"', '""')
$customerDax = Invoke-DaxRow @"
EVALUATE ROW(
    "Pedidos", CALCULATE([Pedidos distintos], Dim_Cliente[CustomerID] = "$escapedCustomer", Dim_Cliente[Pais] = "$escapedCountry"),
    "Unidades", CALCULATE([Unidades], Dim_Cliente[CustomerID] = "$escapedCustomer", Dim_Cliente[Pais] = "$escapedCountry"),
    "Bruto", CALCULATE([Ventas brutas], Dim_Cliente[CustomerID] = "$escapedCustomer", Dim_Cliente[Pais] = "$escapedCountry"),
    "Descuento", CALCULATE([Descuentos aplicados], Dim_Cliente[CustomerID] = "$escapedCustomer", Dim_Cliente[Pais] = "$escapedCountry"),
    "Neto", CALCULATE([Ventas netas], Dim_Cliente[CustomerID] = "$escapedCustomer", Dim_Cliente[Pais] = "$escapedCountry")
)
"@
foreach ($measure in @('Pedidos', 'Unidades', 'Bruto', 'Descuento', 'Neto')) {
    $scale = if ($measure -in @('Bruto', 'Descuento', 'Neto')) { 2 } else { 0 }
    Assert-Equal $customerDax.$measure $customerSql.$measure "Cliente $CustomerId / ${customerCountry}: $measure" $scale
}

$unknownCustomer = Invoke-DaxRow 'EVALUATE SELECTCOLUMNS(FILTER(Dim_Cliente, Dim_Cliente[Cliente_SK] = 0), "Etiqueta", Dim_Cliente[NombreEmpresa])'
$unknownEmployee = Invoke-DaxRow 'EVALUATE SELECTCOLUMNS(FILTER(Dim_Empleado, Dim_Empleado[Empleado_SK] = 0), "Etiqueta", Dim_Empleado[NombreCompleto])'
$unknownTime = Invoke-DaxRow 'EVALUATE SELECTCOLUMNS(FILTER(Dim_Tiempo, Dim_Tiempo[Tiempo_SK] = 0), "Tipo", Dim_Tiempo[TipoFecha])'
if ($unknownCustomer.Etiqueta -ne 'Desconocido' -or $unknownEmployee.Etiqueta -ne 'Desconocido' -or $unknownTime.Tipo -ne 'Desconocida') {
    throw 'Falta la etiqueta de un miembro desconocido o la distinción entre fecha real y fila técnica.'
}

$report = [ordered]@{
    Result = 'PASS'
    Server = $AnalysisServer
    Model = $ModelDatabase
    Warehouse = "$SqlServer/$WarehouseDatabase"
    Totals = $overallDax
    Order10248 = $orderDax
    CategoryYear = @{Category = $Category; Year = $Year; NetSales = $categoryDax.Neto}
    Customer = @{CustomerId = $CustomerId; Country = $customerCountry; Measures = $customerDax}
    UnknownMembers = @{Customer = $unknownCustomer.Etiqueta; Employee = $unknownEmployee.Etiqueta; Time = $unknownTime.Tipo}
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$evidencePath = Join-Path (Resolve-Path -LiteralPath $EvidenceDirectory).Path "comparacion-$stamp.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $evidencePath -Encoding utf8
Write-Output "PASS: modelo y DW coinciden; 10248=$($orderDax.Pedidos) pedido, $($orderDax.Unidades) unidades, neto=$($orderDax.Neto). Evidencia: $evidencePath"
