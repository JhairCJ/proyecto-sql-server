[CmdletBinding()]
param(
    [switch]$Tabular,
    [switch]$Adomd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ($Tabular -or $Adomd)) {
    throw 'Indique -Tabular o -Adomd para cargar las bibliotecas necesarias.'
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'No se encontró Visual Studio Installer (vswhere.exe).'
}

$installations = @(& $vswhere -all -products '*' -property installationPath)
$installation = $installations | Where-Object {
    $directory = Join-Path $_ 'Common7/IDE/CommonExtensions/Microsoft/SSAS'
    if ($Tabular) {
        Test-Path -LiteralPath (Join-Path $directory 'Microsoft.AnalysisServices.Tabular.dll')
    }
    else {
        Test-Path -LiteralPath (Join-Path $directory 'Microsoft.AnalysisServices.AdomdClient.dll')
    }
} | Select-Object -First 1

if (-not $installation) {
    throw 'No se encontró Analysis Services Projects con las bibliotecas solicitadas.'
}

$ssasDirectory = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/SSAS'
$ssisRoot = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/SSIS/170'
$identityClient = @(
    (Join-Path $ssisRoot 'Binn/Microsoft.Identity.Client.dll'),
    (Join-Path $ssisRoot 'Extensions/SQLCommon/Microsoft.Identity.Client.dll'),
    (Join-Path $ssisRoot 'Microsoft.Identity.Client.dll')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $identityClient) {
    throw "No se encontró Microsoft.Identity.Client.dll junto a las extensiones SSIS 170 de '$installation'."
}

$loadedIdentity = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
    $_.GetName().Name -eq 'Microsoft.Identity.Client'
} | Select-Object -First 1
if (-not $loadedIdentity) {
    [void][Reflection.Assembly]::LoadFrom($identityClient)
}

if ($Tabular) {
    if (-not ('Microsoft.AnalysisServices.Tabular.ModelRole' -as [type])) {
        foreach ($assembly in @(
            'Microsoft.AnalysisServices.Core.dll',
            'Microsoft.AnalysisServices.dll',
            'Microsoft.AnalysisServices.Tabular.dll'
        )) {
            $path = Join-Path $ssasDirectory $assembly
            if (-not (Test-Path -LiteralPath $path)) { throw "No se encontró '$path'." }
            Add-Type -Path $path
        }
    }
}

if ($Adomd -and -not ('Microsoft.AnalysisServices.AdomdClient.AdomdConnection' -as [type])) {
    $adomdPath = Join-Path $ssasDirectory 'Microsoft.AnalysisServices.AdomdClient.dll'
    if (-not (Test-Path -LiteralPath $adomdPath)) { throw "No se encontró '$adomdPath'." }
    Add-Type -Path $adomdPath
}
