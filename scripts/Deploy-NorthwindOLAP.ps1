[CmdletBinding()]
param(
    [string]$AnalysisServer = 'localhost',
    [string]$WarehouseServer = 'localhost',
    [ValidateSet('Northwind_DW_Test')]
    [string]$WarehouseDatabase = 'Northwind_DW_Test',
    [ValidateSet('NorthwindOLAP_Test')]
    [string]$ModelDatabase = 'NorthwindOLAP_Test'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..'
& (Join-Path $PSScriptRoot 'Configure-NorthwindOLAPAccess.ps1') -Server $WarehouseServer -WarehouseDatabase $WarehouseDatabase
& (Join-Path $PSScriptRoot 'Build-NorthwindOLAP.ps1')

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installations = & $vswhere -all -products '*' -property installationPath
$installation = $installations | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ 'MSBuild/Business Intelligence Semantic Model/1.0/Microsoft.AnalysisServices.VSHostBuilder.targets')
} | Select-Object -First 1
if (-not $installation) {
    throw 'No se encontró una instalación de Visual Studio con Analysis Services Projects.'
}
$vsPath = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/SSAS'
if (-not (Test-Path -LiteralPath (Join-Path $vsPath 'Microsoft.AnalysisServices.dll'))) {
    throw 'Instala Analysis Services Projects para poder publicar el modelo.'
}

if (-not ('Microsoft.AnalysisServices.Server' -as [type])) {
    Add-Type -Path (Join-Path $vsPath 'Microsoft.AnalysisServices.Core.dll')
    Add-Type -Path (Join-Path $vsPath 'Microsoft.AnalysisServices.dll')
    Add-Type -Path (Join-Path $vsPath 'Microsoft.AnalysisServices.Tabular.dll')
}

$artifact = Join-Path $root 'Northwind.OLAP/bin/Northwind.OLAP.asdatabase'
$databaseDefinition = Get-Content -LiteralPath $artifact -Raw | ConvertFrom-Json
$databaseDefinition.name = $ModelDatabase
$dataSource = $databaseDefinition.model.dataSources | Where-Object name -eq 'NorthwindDW'
if (-not $dataSource) {
    throw 'El modelo compilado no contiene la conexión NorthwindDW.'
}
$dataSource.connectionDetails.address.server = $WarehouseServer
$dataSource.connectionDetails.address.database = $WarehouseDatabase

$server = [Microsoft.AnalysisServices.Server]::new()
try {
    $server.Connect($AnalysisServer)
    $existing = $server.Databases.FindByName($ModelDatabase)
    if ($existing) {
        $owned = $existing.Model.Annotations | Where-Object {
            $_.Name -eq 'NorthwindPracticeModel' -and $_.Value -eq 'Northwind.OLAP'
        }
        if (-not $owned) {
            throw "Ya existe '$ModelDatabase' en Analysis Services y no pertenece a esta práctica; no se reemplazó."
        }
    }

    $command = [ordered]@{
        createOrReplace = [ordered]@{
            object = @{ database = $ModelDatabase }
            database = $databaseDefinition
        }
    } | ConvertTo-Json -Depth 100 -Compress
    [void]$server.Execute($command)
}
finally {
    if ($server.Connected) {
        $server.Disconnect()
    }
}

Write-Output "Modelo publicado: $ModelDatabase en $AnalysisServer; origen: $WarehouseServer/$WarehouseDatabase."
