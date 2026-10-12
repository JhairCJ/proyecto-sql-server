[CmdletBinding()]
param(
 [string]$Server='localhost',
 [string]$SourceDatabase='Northwind_Test',
 [string]$WarehouseDatabase='Northwind_DW_Test',
 [ValidateSet('CargarNorthwind','Cliente','Empleado','Producto','Transportista','Ventas')][string]$Package='CargarNorthwind',
 [string]$LogDirectory,
 [string]$ProjectFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $LogDirectory){$LogDirectory=Join-Path $PSScriptRoot '../docs/evidencias/ssis'}
if(-not $ProjectFile){$ProjectFile=Join-Path $PSScriptRoot '../Northwind.ETL/bin/Development/Northwind.ETL.ispac'}
if($PSVersionTable.PSEdition -ne 'Desktop'){
 & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Server $Server -SourceDatabase $SourceDatabase -WarehouseDatabase $WarehouseDatabase -Package $Package -LogDirectory $LogDirectory -ProjectFile $ProjectFile
 if($LASTEXITCODE -ne 0){throw "Fallo SSIS ($Package). Consulta $LogDirectory/Northwind.ETL-*.log"};return
}
$executor=Join-Path $env:ProgramFiles 'Microsoft SQL Server/170/DTS/Binn/DTExec.exe'
if(-not(Test-Path -LiteralPath $executor)){throw 'Instala Integration Services de SQL Server 2025 (64 bits).'}
if(-not(Test-Path -LiteralPath $ProjectFile)){throw 'Primero ejecuta scripts/Build-NorthwindETL.ps1.'}
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$logPath=(Resolve-Path -LiteralPath $LogDirectory).Path
[void][Reflection.Assembly]::LoadFrom((Join-Path $env:SystemRoot 'Microsoft.NET/assembly/GAC_MSIL/Microsoft.SqlServer.ManagedDTS/v4.0_17.0.0.0__89845dcd8080cc91/Microsoft.SqlServer.ManagedDTS.dll'))
$project=[Microsoft.SqlServer.Dts.Runtime.Project]::OpenProject((Resolve-Path -LiteralPath $ProjectFile).Path)
$executionFile=Join-Path $logPath (([Guid]::NewGuid().ToString('N'))+'.ispac')
try{
 $project.Parameters['SourceServer'].Value=$Server
 $project.Parameters['WarehouseServer'].Value=$Server
 $project.Parameters['SourceDatabase'].Value=$SourceDatabase
 $project.Parameters['WarehouseDatabase'].Value=$WarehouseDatabase
 $project.Parameters['LogDirectory'].Value=$logPath
 $project.SaveTo($executionFile)
 $project.Dispose();$project=$null
 & $executor /PROJECT $executionFile /PACKAGE "$Package.dtsx" /REPORTING E
 if($LASTEXITCODE -ne 0){throw "Fallo SSIS ($Package). Registro: $logPath/Northwind.ETL-*.log"}
}finally{
 if($null -ne $project){$project.Dispose()}
 if(Test-Path -LiteralPath $executionFile){Remove-Item -LiteralPath $executionFile}
}
