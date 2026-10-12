[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$AnalysisServer = 'localhost',
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '../docs/evidencias/olap')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$warehouse = 'Northwind_DW_Test'
$model = 'NorthwindOLAP_Test'
$tools = Join-Path $PSScriptRoot 'Northwind.TestTools.psm1'
Import-Module $tools -Force

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installations = & $vswhere -all -products '*' -property installationPath
$installation = $installations | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ 'MSBuild/Business Intelligence Semantic Model/1.0/Microsoft.AnalysisServices.VSHostBuilder.targets')
} | Select-Object -First 1
if (-not $installation) {
    throw 'Instala Visual Studio con la extensión Analysis Services Projects.'
}
$assemblyDirectory = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/SSAS'
if (-not ('Microsoft.AnalysisServices.AdomdClient.AdomdConnection' -as [type])) {
    Add-Type -Path (Join-Path $assemblyDirectory 'Microsoft.AnalysisServices.AdomdClient.dll')
}

function Invoke-DaxRow([string]$Query) {
    $connection = [Microsoft.AnalysisServices.AdomdClient.AdomdConnection]::new(
        "Data Source=$AnalysisServer;Initial Catalog=$model"
    )
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read()) { throw 'La consulta DAX no devolvió una fila.' }
            $row = [ordered]@{}
            for ($index = 0; $index -lt $reader.FieldCount; $index++) {
                $value = $reader.GetValue($index)
                if ($value -is [System.DBNull]) { $value = $null }
                $name = $reader.GetName($index).TrimStart('[').TrimEnd(']')
                $row[$name] = $value
            }
            return [pscustomobject]$row
        }
        finally { $reader.Dispose(); $command.Dispose() }
    }
    finally { $connection.Dispose() }
}

function Invoke-SqlRow([string]$Database, [string]$Sql) {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Sql
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read()) { throw 'La consulta SQL no devolvió una fila.' }
            $row = [ordered]@{}
            for ($index = 0; $index -lt $reader.FieldCount; $index++) {
                $value = $reader.GetValue($index)
                if ($value -is [System.DBNull]) { $value = $null }
                $row[$reader.GetName($index)] = $value
            }
            return [pscustomobject]$row
        }
        finally { $reader.Dispose(); $command.Dispose() }
    }
    finally { $connection.Dispose() }
}

function Assert-Equal($Actual, $Expected, [string]$Name, [int]$Scale = 0) {
    if ($null -eq $Actual -or $null -eq $Expected) {
        if ($null -ne $Actual -or $null -ne $Expected) {
            throw "$Name no coincide: '$Actual' frente a '$Expected'."
        }
        return
    }
    $actualValue = if ($Scale -gt 0) { [decimal]::Round([decimal]$Actual, $Scale) } else { [decimal]$Actual }
    $expectedValue = if ($Scale -gt 0) { [decimal]::Round([decimal]$Expected, $Scale) } else { [decimal]$Expected }
    if ($actualValue -ne $expectedValue) {
        throw "$Name no coincide: '$actualValue' frente a '$expectedValue'."
    }
}

$deploy = Join-Path $PSScriptRoot '../scripts/Deploy-NorthwindOLAP.ps1'
$process = Join-Path $PSScriptRoot '../scripts/Process-NorthwindOLAP.ps1'
$compare = Join-Path $PSScriptRoot '../scripts/Compare-NorthwindOLAP.ps1'
$scriptLogDirectory = Join-Path $EvidenceDirectory 'procesamientos'
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

$beforeOriginal = Invoke-SqlRow 'Northwind_DW' @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.Fact_Ventas) AS FactRows,
       (SELECT COUNT_BIG(*) FROM dbo.PackageConfig) AS ControlRows;
'@
$fixtureBase = 2100000000 + (Get-Random -Minimum 0 -Maximum 10000000)
$orderIdOne = $fixtureBase
$orderIdTwo = $fixtureBase + 1
$fixturesCommitted = $false
$testError = $null
$cleanupError = $null
$result = [ordered]@{Result='PASS';Model=$model;Warehouse=$warehouse;Fixtures=@($orderIdOne,$orderIdTwo)}

try {
    & $deploy -AnalysisServer $AnalysisServer -WarehouseServer $Server -WarehouseDatabase $warehouse -ModelDatabase $model
    & $process -AnalysisServer $AnalysisServer -ModelDatabase $model -WarehouseServer $Server -WarehouseDatabase $warehouse -LogDirectory $scriptLogDirectory
    & $compare -SqlServer $Server -WarehouseDatabase $warehouse -AnalysisServer $AnalysisServer -ModelDatabase $model -EvidenceDirectory $EvidenceDirectory

    $before = Invoke-DaxRow @'
EVALUATE ROW(
    "Pedidos", [Pedidos distintos],
    "Unidades", [Unidades],
    "Bruto", [Ventas brutas],
    "Descuento", [Descuentos aplicados],
    "Neto", [Ventas netas]
)
'@
    $result.Before = $before

    $sqlFixture = @"
DECLARE @ClienteSK int = (SELECT Cliente_SK FROM dbo.Dim_Cliente WHERE CustomerID=N'ALFKI');
DECLARE @EmpleadoSK int = (SELECT Empleado_SK FROM dbo.Dim_Empleado WHERE EmployeeID=5);
DECLARE @ProductoOnceSK int = (SELECT Producto_SK FROM dbo.Dim_Producto WHERE ProductID=11);
DECLARE @ProductoDosSK int = (SELECT Producto_SK FROM dbo.Dim_Producto WHERE ProductID=72);
DECLARE @TransportistaSK int = (SELECT Transportista_SK FROM dbo.Dim_Transportista WHERE ShipperID=3);
DECLARE @FechaPedido int = (SELECT Tiempo_SK FROM dbo.Dim_Tiempo WHERE Fecha='19960704');
DECLARE @FechaRequerida int = (SELECT Tiempo_SK FROM dbo.Dim_Tiempo WHERE Fecha='19960804');
DECLARE @FechaEnvio int = (SELECT Tiempo_SK FROM dbo.Dim_Tiempo WHERE Fecha='19960904');
IF @ClienteSK IS NULL OR @EmpleadoSK IS NULL OR @ProductoOnceSK IS NULL OR @ProductoDosSK IS NULL
   OR @TransportistaSK IS NULL OR @FechaPedido IS NULL OR @FechaRequerida IS NULL OR @FechaEnvio IS NULL
    THROW 51301, 'No se pudieron resolver las claves del fixture OLAP.', 1;
IF EXISTS (SELECT 1 FROM dbo.Fact_Ventas WHERE OrderID IN($orderIdOne,$orderIdTwo))
    THROW 51302, 'Las identidades aleatorias del fixture ya existen.', 1;

INSERT dbo.Fact_Ventas
    (Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,
     OrderID,ProductID,Cantidad,PrecioUnitario,Descuento,ImporteBruto,ImporteDescuento,ImporteNeto)
VALUES
    (@ClienteSK,@EmpleadoSK,@ProductoOnceSK,@TransportistaSK,@FechaPedido,@FechaRequerida,@FechaEnvio,
     $orderIdOne,11,5,20.0000,0.100000,100.00,10.00,90.00),
    (@ClienteSK,@EmpleadoSK,@ProductoDosSK,NULL,@FechaPedido,@FechaRequerida,NULL,
     $orderIdTwo,72,5,10.0000,0.000000,50.00,0.00,50.00);
"@
    [void](Invoke-NorthwindTestSql -Server $Server -Database $warehouse -Sql $sqlFixture -Commit)
    $fixturesCommitted = $true

    & $process -AnalysisServer $AnalysisServer -ModelDatabase $model -WarehouseServer $Server -WarehouseDatabase $warehouse -LogDirectory $scriptLogDirectory
    $after = Invoke-DaxRow @'
EVALUATE ROW(
    "Pedidos", [Pedidos distintos],
    "Unidades", [Unidades],
    "Bruto", [Ventas brutas],
    "Descuento", [Descuentos aplicados],
    "Neto", [Ventas netas]
)
'@
    Assert-Equal $after.Pedidos ([decimal]$before.Pedidos + 2) 'Pedidos luego del procesamiento'
    Assert-Equal $after.Unidades ([decimal]$before.Unidades + 10) 'Unidades luego del procesamiento'
    Assert-Equal $after.Bruto ([decimal]$before.Bruto + 150) 'Bruto luego del procesamiento' 2
    Assert-Equal $after.Descuento ([decimal]$before.Descuento + 10) 'Descuento luego del procesamiento' 2
    Assert-Equal $after.Neto ([decimal]$before.Neto + 140) 'Neto luego del procesamiento' 2

    $dates = Invoke-DaxRow @"
EVALUATE ROW(
    "PedidoJulio", CALCULATE([Ventas netas], Dim_Tiempo[Anio]=1996, Dim_Tiempo[Mes]=7, Fact_Ventas[OrderID]=$orderIdOne),
    "RequeridaAgosto", CALCULATE([Ventas netas por fecha requerida], Dim_Tiempo[Anio]=1996, Dim_Tiempo[Mes]=8, Fact_Ventas[OrderID]=$orderIdOne),
    "EnvioSeptiembre", CALCULATE([Ventas netas por fecha de envío], Dim_Tiempo[Anio]=1996, Dim_Tiempo[Mes]=9, Fact_Ventas[OrderID]=$orderIdOne),
    "EnvioSinFechaSeptiembre", CALCULATE([Ventas netas por fecha de envío], Dim_Tiempo[Anio]=1996, Dim_Tiempo[Mes]=9, Fact_Ventas[OrderID]=$orderIdTwo)
)
"@
    Assert-Equal $dates.PedidoJulio 90 'Fecha activa de pedido' 2
    Assert-Equal $dates.RequeridaAgosto 90 'Fecha requerida' 2
    Assert-Equal $dates.EnvioSeptiembre 90 'Fecha de envío' 2
    Assert-Equal $dates.EnvioSinFechaSeptiembre $null 'Pedido sin fecha de envío' 2
    $result.AfterFixture = $after
    $result.DateRoles = $dates

    & $compare -SqlServer $Server -WarehouseDatabase $warehouse -AnalysisServer $AnalysisServer -ModelDatabase $model -EvidenceDirectory $EvidenceDirectory

    $forcedFailure = $false
    try {
        & $process -AnalysisServer $AnalysisServer -ModelDatabase $model -WarehouseServer $Server -WarehouseDatabase 'Northwind_OLAP_Missing' -LogDirectory $scriptLogDirectory
    }
    catch {
        $forcedFailure = $true
    }
    if (-not $forcedFailure) {
        throw 'El procesamiento con una fuente inexistente no devolvió error.'
    }
    $failureLog = Get-ChildItem -LiteralPath $scriptLogDirectory -Filter 'NorthwindOLAP-*.log' -File |
        Sort-Object LastWriteTime -Descending | Where-Object {
            (Get-Content -LiteralPath $_.FullName -Raw).Contains('WarehouseDatabase=Northwind_OLAP_Missing')
        } | Select-Object -First 1
    if (-not $failureLog) {
        throw 'No se guardó el registro del fallo de procesamiento.'
    }
    $failureText = Get-Content -LiteralPath $failureLog.FullName -Raw
    if (-not $failureText.Contains('Result=FAILED') -or -not $failureText.Contains('SourceRestored=True')) {
        throw 'El registro no identifica el fallo o la restauración de la conexión.'
    }
    $result.FailedProcessingLog = $failureLog.Name

    & $process -AnalysisServer $AnalysisServer -ModelDatabase $model -WarehouseServer $Server -WarehouseDatabase $warehouse -LogDirectory $scriptLogDirectory
    $result.Recovery = 'PASS'
}
catch {
    $testError = $_.Exception.Message
}
finally {
    if ($fixturesCommitted) {
        try {
            $cleanup = "DELETE FROM dbo.Fact_Ventas WHERE OrderID IN($orderIdOne,$orderIdTwo); IF @@ROWCOUNT<>2 THROW 51303, 'No se limpiaron los dos fixtures OLAP.', 1;"
            [void](Invoke-NorthwindTestSql -Server $Server -Database $warehouse -Sql $cleanup -Commit)
            & $process -AnalysisServer $AnalysisServer -ModelDatabase $model -WarehouseServer $Server -WarehouseDatabase $warehouse -LogDirectory $scriptLogDirectory
            & $compare -SqlServer $Server -WarehouseDatabase $warehouse -AnalysisServer $AnalysisServer -ModelDatabase $model -EvidenceDirectory $EvidenceDirectory
            $result.Cleanup = 'PASS'
        }
        catch {
            $cleanupError = $_.Exception.Message
        }
    }
}

$afterOriginal = Invoke-SqlRow 'Northwind_DW' @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.Fact_Ventas) AS FactRows,
       (SELECT COUNT_BIG(*) FROM dbo.PackageConfig) AS ControlRows;
'@
if ($beforeOriginal.FactRows -ne $afterOriginal.FactRows -or $beforeOriginal.ControlRows -ne $afterOriginal.ControlRows) {
    $cleanupError = 'Northwind_DW cambió durante la prueba aislada.'
}
$result.OriginalWarehouse = 'UNCHANGED'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$reportPath = Join-Path (Resolve-Path -LiteralPath $EvidenceDirectory).Path "integracion-$stamp.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
if ($cleanupError) {
    throw "No se pudo completar la limpieza/restauración del modelo: $cleanupError. Evidencia: $reportPath"
}
if ($testError) {
    throw "Falló la integración OLAP: $testError. Los fixtures se limpiaron. Evidencia: $reportPath"
}

Write-Output "PASS: modelo procesado, fechas y filtros reconciliados, venta nueva visible, error registrado y recuperado; Northwind_DW sin cambios. Evidencia: $reportPath"
