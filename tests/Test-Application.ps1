[CmdletBinding()]
param([string]$Server='localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.WarehouseChecks.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force

function Get-SourceSnapshot {
    $source=New-NorthwindTestConnection -Database Northwind_Test -Server $Server
    try {
        $cutCommand=$source.CreateCommand()
        $cutCommand.CommandText='EXEC dbo.GetDatabaseRowVersion;'
        $cut=[long]$cutCommand.ExecuteScalar()
        $cutCommand.Dispose()
        $entities=@(
            @('Cliente','Customer'),@('Empleado','Employee'),@('Proveedor','Supplier'),
            @('Producto','Product'),@('Transportista','Shipper'),@('Ventas','Sales')
        )
        $tables=[System.Collections.Generic.List[System.Data.DataTable]]::new()
        foreach($entity in $entities){
            $command=$source.CreateCommand()
            $command.CommandText="EXEC dbo.Get$($entity[1])ChangesByRowVersion @start,@end;"
            [void]$command.Parameters.Add('@start',[Data.SqlDbType]::BigInt)
            [void]$command.Parameters.Add('@end',[Data.SqlDbType]::BigInt)
            $command.Parameters['@start'].Value=[long]0
            $command.Parameters['@end'].Value=$cut
            $adapter=[Data.SqlClient.SqlDataAdapter]::new($command)
            $table=[Data.DataTable]::new()
            try{[void]$adapter.Fill($table)}finally{$adapter.Dispose();$command.Dispose()}
            $tables.Add($table)
        }
        return [pscustomobject]@{Cut=$cut;Tables=$tables;Entities=$entities}
    } finally {$source.Dispose()}
}

function Copy-Staging($Connection,$Transaction,$Snapshot,[string[]]$Only=@()){
    $entities=$Snapshot.Entities
    for($i=0;$i -lt $entities.Count;$i++){
        $name=$entities[$i][0]
        if($Only.Count -and $name -notin $Only){continue}
        $command=$Connection.CreateCommand();$command.Transaction=$Transaction
        $command.CommandText="DELETE FROM std.$name;"
        try{[void]$command.ExecuteNonQuery()}finally{$command.Dispose()}
        $bulk=[Data.SqlClient.SqlBulkCopy]::new(
            $Connection,[Data.SqlClient.SqlBulkCopyOptions]::CheckConstraints,$Transaction)
        try{
            $bulk.DestinationTableName="std.$name"
            $bulk.BulkCopyTimeout=120
            foreach($column in $Snapshot.Tables[$i].Columns){
                [void]$bulk.ColumnMappings.Add($column.ColumnName,$column.ColumnName)
            }
            $bulk.WriteToServer($Snapshot.Tables[$i])
        }finally{$bulk.Dispose()}
    }
}

function Read-TargetState {
    $state=Invoke-NorthwindTestSql -Database Northwind_DW_Test -Server $Server -Sql @'
SELECT * FROM dbo.DimDate ORDER BY DateKey;
SELECT * FROM dbo.DimCustomer ORDER BY CustomerKey;
SELECT * FROM dbo.DimEmployee ORDER BY EmployeeKey;
SELECT * FROM dbo.DimProduct ORDER BY ProductKey;
SELECT * FROM dbo.DimShipper ORDER BY ShipperKey;
SELECT * FROM dbo.DimSupplier ORDER BY SupplierKey;
SELECT * FROM dbo.DimGeography ORDER BY GeographyKey;
SELECT * FROM dbo.FactSales ORDER BY SalesKey;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad FROM dbo.PackageConfig ORDER BY PackageName;
SELECT * FROM std.Cliente ORDER BY CustomerID;
SELECT * FROM std.Empleado ORDER BY EmployeeID;
SELECT * FROM std.Proveedor ORDER BY SupplierID;
SELECT * FROM std.Producto ORDER BY ProductID;
SELECT * FROM std.Transportista ORDER BY ShipperID;
SELECT * FROM std.Ventas ORDER BY OrderID,ProductID;
'@
    return $state.GetXml()
}

function Find-SqlError($ErrorRecord){
    $exception=$ErrorRecord.Exception
    while($null -ne $exception -and $exception -isnot [Data.SqlClient.SqlException]){
        $exception=$exception.InnerException
    }
    return $exception
}

function Invoke-ExpectedFailure {
    param(
        [string]$Package,
        [string]$Sql,
        [int]$ErrorNumber,
        $Snapshot,
        [string[]]$Only
    )
    $before=Read-TargetState
    $warehouse=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
    $transaction=$null
    $caught=$false
    try{
        $transaction=$warehouse.BeginTransaction()
        Copy-Staging $warehouse $transaction $Snapshot $Only
        $markCommand=$warehouse.CreateCommand();$markCommand.Transaction=$transaction
        $markCommand.CommandText='DECLARE @mark binary(8);EXEC dbo.GetLastPackageRowVersion @package,@mark OUTPUT;SELECT CONVERT(bigint,@mark);'
        [void]$markCommand.Parameters.Add('@package',[Data.SqlDbType]::NVarChar,100)
        $markCommand.Parameters['@package'].Value=$Package
        $start=[long]$markCommand.ExecuteScalar()
        $markCommand.Dispose()
        $command=$warehouse.CreateCommand();$command.Transaction=$transaction
        $command.CommandTimeout=120
        $command.CommandText=$Sql
        [void]$command.Parameters.Add('@cut',[Data.SqlDbType]::BigInt)
        $command.Parameters['@cut'].Value=$Snapshot.Cut
        [void]$command.Parameters.Add('@start',[Data.SqlDbType]::BigInt)
        $command.Parameters['@start'].Value=$start
        try{[void]$command.ExecuteNonQuery()}
        catch{
            $sqlError=Find-SqlError $_
            if($null -eq $sqlError -or $sqlError.Number -ne $ErrorNumber){throw}
            $caught=$true
        }finally{$command.Dispose()}
    }finally{
        if($null -ne $transaction){try{$transaction.Rollback()}catch{};$transaction.Dispose()}
        $warehouse.Dispose()
    }
    if(-not $caught){throw "La aplicación aceptó la referencia inválida del proceso $Package."}
    if((Read-TargetState) -cne $before){throw "El fallo del proceso $Package cambió staging, finales o controles."}
    "PASS: $Package rechazó la referencia inválida y revirtió hechos, destinos, dimensiones y marca."
}

$snapshot=Get-SourceSnapshot
$warehouse=New-NorthwindTestConnection -Database Northwind_DW_Test -Server $Server
$transaction=$null
$before=Read-TargetState
try{
    $transaction=$warehouse.BeginTransaction()
    $command=$warehouse.CreateCommand();$command.Transaction=$transaction
    $command.CommandTimeout=120
    $command.CommandText=@'
IF DB_NAME()<>N'Northwind_DW_Test'
 OR NOT EXISTS(SELECT 1 FROM dbo.WarehouseMigrationState
   WHERE MigrationName=N'ReplaceNorthwindStarModel' AND Stage IN(N'Validated',N'SkippedEmpty',N'Cutover'))
    THROW 52520,'La prueba requiere una copia marcada con esquema migrado.',1;
UPDATE dbo.PackageConfig SET LastRowVersion=0x0000000000000000;
'@
    [void]$command.ExecuteNonQuery()
    $command.Dispose()
    Copy-Staging $warehouse $transaction $snapshot

    $command=$warehouse.CreateCommand();$command.Transaction=$transaction
    $command.CommandTimeout=300
    $command.CommandText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-Application.sql') -Raw
    [void]$command.Parameters.Add('@cut',[Data.SqlDbType]::BigInt)
    $command.Parameters['@cut'].Value=$snapshot.Cut
    [void]$command.ExecuteNonQuery()
    $command.Dispose()

    $comparison=@(Get-NorthwindWarehouseComparison -Server $Server -WarehouseConnection $warehouse -WarehouseTransaction $transaction)
    $comparison | Format-Table -AutoSize
    if($comparison.Where({-not $_.Coincide}).Count){throw 'Carga inicial en transacción no concilia con Northwind_Test.'}
    'PASS: primera aplicación y repetición de seis procesos concilian con la referencia'

    $command=$warehouse.CreateCommand();$command.Transaction=$transaction
    $command.CommandTimeout=300
    $command.CommandText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-Application-Scenarios.sql') -Raw
    [void]$command.Parameters.Add('@cut',[Data.SqlDbType]::BigInt)
    $command.Parameters['@cut'].Value=$snapshot.Cut
    [void]$command.ExecuteNonQuery()
    $command.Dispose()
    'PASS: cambios tipo 1, destinos compartidos y parciales, Freight y SupplierKey actual'
}finally{
    if($null -ne $transaction){try{$transaction.Rollback()}catch{};$transaction.Dispose()}
    $warehouse.Dispose()
}
if((Read-TargetState) -cne $before){throw 'El fixture de aplicación no restauró todas las tablas y controles.'}
'PASS: prueba principal revertida; staging, SK, hechos y controles originales siguen intactos'

Invoke-ExpectedFailure -Package 'Ventas' -Only @('Ventas') -Snapshot $snapshot -ErrorNumber 52417 -Sql @'
UPDATE std.Ventas SET ProductID=-902 WHERE OrderID=10248 AND ProductID=11;
EXEC dbo.DW_ApplyPackage N'Ventas',@start,@cut;
'@
Invoke-ExpectedFailure -Package 'Producto' -Only @('Producto') -Snapshot $snapshot -ErrorNumber 52415 -Sql @'
UPDATE std.Producto SET SupplierID=-902 WHERE ProductID=11;
EXEC dbo.DW_ApplyPackage N'Producto',@start,@cut;
'@
Invoke-ExpectedFailure -Package 'Ventas' -Only @('Ventas') -Snapshot $snapshot -ErrorNumber 52416 -Sql @'
UPDATE std.Ventas SET Freight=ISNULL(Freight,0)+1
WHERE OrderID=10248 AND ProductID=11;
EXEC dbo.DW_ApplyPackage N'Ventas',@start,@cut;
'@
'PASS: las pruebas de referencias inválidas y flete inconsistente conservaron el estado previo'
