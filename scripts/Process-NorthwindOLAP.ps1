[CmdletBinding()]
param(
    [string]$AnalysisServer = 'localhost',
    [ValidateSet('NorthwindOLAP_Test')]
    [string]$ModelDatabase = 'NorthwindOLAP_Test',
    [string]$WarehouseServer = 'localhost',
    [string]$WarehouseDatabase = 'Northwind_DW_Test',
    [string]$LogDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path $PSScriptRoot '../docs/evidencias/olap'
}

& (Join-Path $PSScriptRoot 'Import-NorthwindAnalysisServices.ps1') -Tabular

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logPath = Join-Path (Resolve-Path -LiteralPath $LogDirectory).Path "NorthwindOLAP-$stamp.log"
$started = Get-Date
$log = [System.Collections.Generic.List[string]]::new()
$log.Add("Started=$($started.ToString('o'))")
$log.Add("AnalysisServer=$AnalysisServer")
$log.Add("ModelDatabase=$ModelDatabase")
$log.Add("WarehouseServer=$WarehouseServer")
$log.Add("WarehouseDatabase=$WarehouseDatabase")

$server = [Microsoft.AnalysisServices.Server]::new()
$originalSource = $null
$sourceMayHaveChanged = $false
$failure = $null
try {
    $server.Connect($AnalysisServer)
    $database = $server.Databases.FindByName($ModelDatabase)
    if (-not $database) {
        throw "No existe el modelo '$ModelDatabase'. Ejecuta scripts/Deploy-NorthwindOLAP.ps1 primero."
    }
    $owned = $database.Model.Annotations | Where-Object {
        $_.Name -eq 'NorthwindPracticeModel' -and $_.Value -eq 'Northwind.OLAP'
    }
    if (-not $owned) {
        throw "El modelo '$ModelDatabase' no pertenece a esta práctica; no se procesó."
    }

    $dataSource = $database.Model.DataSources.Find('NorthwindDW')
    if (-not $dataSource) {
        throw "No existe la conexión NorthwindDW en '$ModelDatabase'."
    }
    $originalSource = @{
        Server = $dataSource.ConnectionDetails.Address.Server
        Database = $dataSource.ConnectionDetails.Address.Database
    }

    $connectionDetails = @{
        protocol = 'tds'
        address = @{server = $WarehouseServer; database = $WarehouseDatabase}
        authentication = $null
        query = $null
    }
    $credential = @{
        AuthenticationKind = 'ServiceAccount'
        EncryptConnection = $false
    }
    $alterSource = [ordered]@{
        alter = [ordered]@{
            object = @{database = $ModelDatabase; dataSource = 'NorthwindDW'}
            dataSource = @{
                type = 'structured'
                name = 'NorthwindDW'
                connectionDetails = $connectionDetails
                credential = $credential
            }
        }
    } | ConvertTo-Json -Depth 30 -Compress
    $sourceMayHaveChanged = $true
    [void]$server.Execute($alterSource)
    $database.Refresh()

    $operation = $database.Model
    $operation.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Full)
    [void]$operation.SaveChanges()
    $log.Add('Result=SUCCESS')
    $log.Add("Completed=$((Get-Date).ToString('o'))")
}
catch {
    $failure = $_.Exception.Message
    $log.Add('Result=FAILED')
    $log.Add("Error=$failure")
    $log.Add("Failed=$((Get-Date).ToString('o'))")

    if ($sourceMayHaveChanged -and $originalSource -and $server.Connected) {
        try {
            $restore = [ordered]@{
                alter = [ordered]@{
                    object = @{database = $ModelDatabase; dataSource = 'NorthwindDW'}
                    dataSource = @{
                        type = 'structured'
                        name = 'NorthwindDW'
                        connectionDetails = @{
                            protocol = 'tds'
                            address = @{server = $originalSource.Server; database = $originalSource.Database}
                            authentication = $null
                            query = $null
                        }
                        credential = @{AuthenticationKind = 'ServiceAccount'; EncryptConnection = $false}
                    }
                }
            } | ConvertTo-Json -Depth 30 -Compress
            [void]$server.Execute($restore)
            $log.Add('SourceRestored=True')
        }
        catch {
            $log.Add("SourceRestoreError=$($_.Exception.Message)")
        }
    }
}
finally {
    if ($server.Connected) {
        $server.Disconnect()
    }
    Set-Content -LiteralPath $logPath -Value $log -Encoding utf8
}

if ($failure) {
    throw "Falló el procesamiento de '$ModelDatabase'. Registro: $logPath. $failure"
}

Write-Output "Modelo procesado correctamente: $ModelDatabase. Registro: $logPath"
