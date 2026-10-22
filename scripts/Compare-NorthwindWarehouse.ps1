[CmdletBinding()]
param(
    [string]$Server='localhost',
    [ValidatePattern('^(Northwind_DW|Northwind_DW_(?:[A-Za-z0-9]+_)*Test)$')]
    [string]$WarehouseDatabase='Northwind_DW_Test'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\tests\Northwind.WarehouseChecks.psm1') -Force
$comparison=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseDatabase $WarehouseDatabase)
$comparison | Format-Table -AutoSize
if($comparison.Where({-not $_.Coincide}).Count){throw 'El DW no coincide con el origen; revise las comprobaciones indicadas.'}
