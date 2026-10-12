[CmdletBinding()]
param([string]$Server='localhost')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\tests\Northwind.WarehouseChecks.psm1') -Force
$comparison=@(Get-NorthwindWarehouseComparison -Server $Server)
$comparison | Format-Table -AutoSize
if($comparison.Where({-not $_.Coincide}).Count){throw 'El DW no coincide con el origen; revise las comprobaciones indicadas.'}
