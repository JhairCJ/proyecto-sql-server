[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'No se encontró Visual Studio Installer (vswhere.exe).' }

$installations = @(& $vswhere -all -products '*' -format json | ConvertFrom-Json)
$selected = $null
foreach ($candidate in $installations) {
    $root = [string]$candidate.installationPath
    $devenv = Join-Path $root 'Common7/IDE/devenv.com'
    $ssdtTargets = Join-Path $root 'MSBuild/Microsoft/VisualStudio/v17.0/SSDT/Microsoft.Data.Tools.Schema.SqlTasks.targets'
    $ssdtFallback = if (Test-Path -LiteralPath (Join-Path $root 'MSBuild')) {
        Get-ChildItem -LiteralPath (Join-Path $root 'MSBuild') -Filter 'Microsoft.Data.Tools.Schema.SqlTasks.targets' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $ssisManifest = Join-Path $root 'Common7/IDE/CommonExtensions/Microsoft/SSIS/170/SSIS.manifest'
    $ssasProjectSystem = Join-Path $root 'MSBuild/Business Intelligence Semantic Model/1.0/Microsoft.AnalysisServices.VSHostBuilder.targets'
    if ((Test-Path -LiteralPath $devenv) -and ($ssdtFallback -or (Test-Path -LiteralPath $ssdtTargets)) -and
        (Test-Path -LiteralPath $ssisManifest) -and (Test-Path -LiteralPath $ssasProjectSystem)) {
        $selected = [pscustomobject]@{ Installation = $root; Devenv = $devenv }
        break
    }
}
if (-not $selected) {
    throw 'Se requiere Visual Studio con SSDT, Integration Services Projects 170 y Analysis Services Projects; no se instaló ningún componente.'
}

$solution = Join-Path $repository 'Northwind.sln'
if (-not (Test-Path -LiteralPath $solution)) { throw "No existe la solución compatible '$solution'." }
$buildLog = Join-Path $env:TEMP ("NorthwindSolutionBuild-{0}.log" -f [guid]::NewGuid().ToString('N'))
if (-not (Test-Path -LiteralPath $selected.Devenv)) { throw "No se encontró devenv.com en '$($selected.Installation)'." }
$buildStartedUtc = [DateTime]::UtcNow
& $selected.Devenv $solution '/Rebuild' ("$Configuration|Any CPU") '/Out' $buildLog
$buildExitCode = $LASTEXITCODE
if ($buildExitCode -ne 0) {
    if (Test-Path -LiteralPath $buildLog) { Get-Content -LiteralPath $buildLog -Tail 80 }
    throw "Falló la compilación de Northwind.sln (devenv.com exit code $buildExitCode). Registro: $buildLog"
}

$buildText = if (Test-Path -LiteralPath $buildLog) { Get-Content -LiteralPath $buildLog -Raw } else { '' }
foreach ($projectName in 'Northwind.OLTP', 'Northwind.DW', 'Northwind.ETL', 'Northwind.OLAP') {
    if ($buildText -notmatch [regex]::Escape($projectName)) {
        throw "El registro de la solución no muestra el proyecto '$projectName'; registro: $buildLog"
    }
}
$summary = [regex]::Match($buildText, '(?im)^=+\s*(?:Rebuild|Build)[^:]*:\s*(\d+)\s+succeeded,\s*(\d+)\s+failed(?:,\s*(\d+)\s+up-to-date)?(?:,\s*(\d+)\s+skipped)?\s*=+$')
if ($summary.Success -and ([int]$summary.Groups[1].Value -ne 4 -or [int]$summary.Groups[2].Value -ne 0)) {
    throw "La solución no compiló exactamente los cuatro proyectos sin errores. Registro: $buildLog"
}

$artifacts = @(
    [pscustomobject]@{ Project = 'Northwind.OLTP'; Path = Join-Path $repository "Northwind.OLTP/bin/$Configuration/Northwind.OLTP.dacpac" },
    [pscustomobject]@{ Project = 'Northwind.DW'; Path = Join-Path $repository "Northwind.DW/bin/$Configuration/Northwind.DW.dacpac" },
    [pscustomobject]@{ Project = 'Northwind.ETL'; Path = Join-Path $repository 'Northwind.ETL/bin/Development/Northwind.ispac' },
    [pscustomobject]@{ Project = 'Northwind.OLAP'; Path = Join-Path $repository 'Northwind.OLAP/bin/Northwind.OLAP.asdatabase' }
)
foreach ($artifact in $artifacts) {
    if (-not (Test-Path -LiteralPath $artifact.Path -PathType Leaf)) {
        throw "La solución no generó el artefacto de $($artifact.Project): '$($artifact.Path)'. Registro: $buildLog"
    }
    $lastWriteUtc = (Get-Item -LiteralPath $artifact.Path).LastWriteTimeUtc
    if ($lastWriteUtc -lt $buildStartedUtc.AddSeconds(-2)) {
        throw "El artefacto de $($artifact.Project) no se generó en esta recompilación: '$($artifact.Path)'. Registro: $buildLog"
    }
    if ((Get-Item -LiteralPath $artifact.Path).Length -eq 0) { throw "El artefacto de $($artifact.Project) está vacío." }
}

$etlDirectory = Join-Path $repository 'Northwind.ETL/bin/Development'
$nativeIspac = Join-Path $etlDirectory 'Northwind.ispac'
$namedIspac = Join-Path $etlDirectory 'Northwind.ETL.ispac'
Copy-Item -LiteralPath $nativeIspac -Destination $namedIspac -Force

foreach ($artifact in $artifacts) {
    if ($artifact.Project -eq 'Northwind.ETL') {
        $artifact.Path = $namedIspac
    }
}

Write-Output "Compilación completada desde Northwind.sln: 4 de 4 proyectos. Registro: $buildLog"
foreach ($artifact in $artifacts) {
    Write-Output ("{0}: {1}" -f $artifact.Project, (Resolve-Path -LiteralPath $artifact.Path).Path)
}
