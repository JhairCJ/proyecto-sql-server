[CmdletBinding()]
param(
    [string]$MSBuildPath='C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $MSBuildPath)){throw 'No se encontró MSBuild de SSDT.'}
$source=Join-Path $PSScriptRoot '../Northwind.DW'
$buildRoot=Join-Path ([IO.Path]::GetTempPath()) ('NorthwindDWBuild-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildRoot | Out-Null
# SSDT puede conservar objetos retirados en la caché del proyecto abierto en VS.
# Compilar solo las fuentes evita publicar un DACPAC que recree el modelo anterior.
Copy-Item -LiteralPath (Join-Path $source 'Northwind.DW.sqlproj') -Destination $buildRoot
foreach($directory in 'dbo','std','Deployment','Properties'){
    Copy-Item -LiteralPath (Join-Path $source $directory) -Destination $buildRoot -Recurse
}
& $MSBuildPath (Join-Path $buildRoot 'Northwind.DW.sqlproj') /t:Rebuild /p:VisualStudioVersion=18.0 /nologo /v:quiet
if($LASTEXITCODE -ne 0){throw "Falló la compilación limpia del DW: $buildRoot"}
$artifact=Join-Path $buildRoot 'bin/Debug/Northwind.DW.dacpac'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($artifact)
try{
    $reader=[IO.StreamReader]::new($zip.GetEntry('model.xml').Open())
    try{$model=$reader.ReadToEnd()}finally{$reader.Dispose()}
    $tables=@([regex]::Matches($model,'<Element Type="SqlTable" Name="([^"]+)"') | ForEach-Object {$_.Groups[1].Value})
    foreach($name in 'Dim_Cliente','Dim_Empleado','Dim_Producto','Dim_Tiempo','Dim_Transportista','Fact_Ventas'){
        if($tables -contains "[dbo].[$name]"){throw "El DACPAC contiene el objeto retirado $name."}
    }
    foreach($name in 'DimCustomer','DimEmployee','DimProduct','DimDate','DimShipper','DimSupplier','DimGeography','FactSales'){
        if($tables -notcontains "[dbo].[$name]"){throw "El DACPAC no contiene $name."}
    }
}finally{$zip.Dispose()}
$output=Join-Path $source 'bin/Debug'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Copy-Item -LiteralPath $artifact -Destination (Join-Path $output 'Northwind.DW.dacpac') -Force
Write-Output "DW compilado desde fuentes limpias; ocho tablas finales verificadas. Fuentes de compilación: $buildRoot"
