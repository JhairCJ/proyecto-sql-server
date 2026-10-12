[CmdletBinding()]
param([string]$Configuration = 'Development')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = Join-Path $PSScriptRoot '../Northwind.OLAP/Northwind.OLAP.smproj'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'No se encontró Visual Studio Installer (vswhere.exe).'
}

$installations = & $vswhere -all -products '*' -property installationPath
$installation = $installations | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ 'MSBuild/Business Intelligence Semantic Model/1.0/Microsoft.AnalysisServices.VSHostBuilder.targets')
} | Select-Object -First 1
if (-not $installation) {
    throw 'Instala Visual Studio con la extensión Analysis Services Projects.'
}

$msbuild = Join-Path $installation 'MSBuild/Current/Bin/MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) {
    throw "No se encontró MSBuild en '$installation'."
}

& $msbuild $project '/target:Build' "/property:Configuration=$Configuration" '/verbosity:minimal'
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo compilar Northwind.OLAP.'
}

$artifact = Join-Path $PSScriptRoot '../Northwind.OLAP/bin/Northwind.OLAP.asdatabase'
if (-not (Test-Path -LiteralPath $artifact)) {
    throw "La compilación terminó sin generar '$artifact'."
}

Write-Output "Modelo compilado: $((Resolve-Path -LiteralPath $artifact).Path)"
