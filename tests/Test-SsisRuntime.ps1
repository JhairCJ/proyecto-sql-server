[CmdletBinding()]
param(
 [string]$EvidenceDirectory,
 [switch]$GenerateOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $PSScriptRoot '../docs/evidencias/seccion-ssis'}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$package=Join-Path $EvidenceDirectory 'RuntimeProbe.dtsx'
if($GenerateOnly){
 $assembly='C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.ManagedDTS\v4.0_17.0.0.0__89845dcd8080cc91\Microsoft.SqlServer.ManagedDTS.dll'
 if(-not(Test-Path -LiteralPath $assembly)){throw 'Falta ManagedDTS 17 del runtime SQL Server.'}
 [void][Reflection.Assembly]::LoadFrom($assembly)
 $app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
 $probe=New-Object Microsoft.SqlServer.Dts.Runtime.Package
 $probe.Name='NorthwindRuntimeProbe'
 $probe.ProtectionLevel=[Microsoft.SqlServer.Dts.Runtime.DTSProtectionLevel]::DontSaveSensitive
 $task=$probe.Executables.Add('STOCK:PipelineTask')
 $task.Name='Comprobar runtime de Data Flow'
 $app.SaveToXml($package,$probe,$null)
 return
}
$windowsPowerShell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -GenerateOnly -EvidenceDirectory $EvidenceDirectory
if($LASTEXITCODE -ne 0){throw 'No se pudo generar el paquete de comprobacion.'}
$executors=@(
 @('SQLServer','C:\Program Files\Microsoft SQL Server\170\DTS\Binn\DTExec.exe'),
 @('VisualStudio','C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\SSIS\170\Binn\DTExec.exe'))
$failed=$false
foreach($executor in $executors){
 $path=$executor[1];$exitCode=-1
 if(Test-Path -LiteralPath $path){
  & $path /FILE $package /REPORTING E *> (Join-Path $EvidenceDirectory "$($executor[0]).txt")
  $exitCode=$LASTEXITCODE
 }
 if($executor[0] -eq 'SQLServer' -and $exitCode -ne 0){$failed=$true}
 Write-Host "$($executor[0]): Codigo=$exitCode; Correcto=$($exitCode -eq 0)"
}
if($failed){throw "El runtime SQL Server no ejecuta SSIS. Consulte $EvidenceDirectory."}
Write-Host 'La utilidad privada de Visual Studio es solo un diagnostico; su fallo no invalida una ejecucion correcta en el diseñador.'
