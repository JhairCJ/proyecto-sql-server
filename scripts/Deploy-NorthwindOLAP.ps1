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

& (Join-Path $PSScriptRoot 'Import-NorthwindAnalysisServices.ps1') -Tabular

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

        # createOrReplace treats omitted role properties as deletions. TOM's serializer
        # preserves all supported role fields, including members, filters and annotations.
        $roleDefinitions = [Collections.Generic.List[object]]::new()
        foreach ($role in $existing.Model.Roles) {
            $roleJson = [Microsoft.AnalysisServices.Tabular.JsonSerializer]::SerializeObject($role)
            $roleDefinitions.Add(($roleJson | ConvertFrom-Json))
        }
        $databaseDefinition.model | Add-Member -MemberType NoteProperty -Name roles -Value $roleDefinitions.ToArray() -Force
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
