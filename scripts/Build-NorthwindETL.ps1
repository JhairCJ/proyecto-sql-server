[CmdletBinding()]
param([string]$ProjectDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $ProjectDirectory){$ProjectDirectory=Join-Path $PSScriptRoot '../Northwind.ETL'}
if($PSVersionTable.PSEdition -ne 'Desktop'){
 & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ProjectDirectory $ProjectDirectory
 if($LASTEXITCODE -ne 0){throw 'No se pudo compilar Northwind.ETL.'};return
}
$assembly=Join-Path $env:SystemRoot 'Microsoft.NET/assembly/GAC_MSIL/Microsoft.SqlServer.ManagedDTS/v4.0_17.0.0.0__89845dcd8080cc91/Microsoft.SqlServer.ManagedDTS.dll'
if(-not(Test-Path -LiteralPath $assembly)){throw 'Instala Integration Services de SQL Server 2025 (64 bits).'}
[void][Reflection.Assembly]::LoadFrom($assembly)
$folder=(Resolve-Path -LiteralPath $ProjectDirectory).Path
$project=[Microsoft.SqlServer.Dts.Runtime.Project]::CreateProject()
try{
 $project.Name='Northwind.ETL'
 $project.ProtectionLevel=[Microsoft.SqlServer.Dts.Runtime.DTSProtectionLevel]::DontSaveSensitive
 $project.TargetServerVersion=[Microsoft.SqlServer.Dts.Runtime.DTSTargetServerVersion]::SQLServer2025
 $ns=[Xml.XmlNamespaceManager]::new([Xml.NameTable]::new());$ns.AddNamespace('s','www.microsoft.com/SqlServer/SSIS')
 $parameters=[xml](Get-Content (Join-Path $folder 'Project.params') -Raw)
 foreach($node in $parameters.SelectNodes('//s:Parameter',$ns)){
  $name=$node.GetAttribute('Name','www.microsoft.com/SqlServer/SSIS')
  $value=$node.SelectSingleNode('s:Properties/s:Property[@s:Name="Value"]',$ns).InnerText
  $project.Parameters.Add($name,[TypeCode]::String).Value=$value
 }
 $dtproj=[xml](Get-Content (Join-Path $folder 'Northwind.ETL.dtproj') -Raw)
 foreach($node in $dtproj.SelectNodes('//s:ConnectionManagers/s:ConnectionManager',$ns)){
  $name=$node.GetAttribute('Name','www.microsoft.com/SqlServer/SSIS')
  $xml=[xml](Get-Content (Join-Path $folder $name) -Raw)
  $cm=$project.ConnectionManagerItems.Add('OLEDB',$name).ConnectionManager
  $cm.LoadFromXML($xml.DocumentElement,$null)
 }
 $app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
 foreach($node in $dtproj.SelectNodes('//s:Packages/s:Package',$ns)){
  $name=$node.GetAttribute('Name','www.microsoft.com/SqlServer/SSIS')
  $package=$app.LoadPackage((Join-Path $folder $name),$null)
  [void]$project.PackageItems.Add($package,$name)
 }
 $out=Join-Path $folder 'bin/Development/Northwind.ETL.ispac'
 New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
 $project.SaveTo($out)
 Write-Host "Proyecto compilado: $out"
}finally{$project.Dispose()}
