[CmdletBinding()]
param([string]$Server = 'localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Solo publica cuatro procedimientos en el origen de prueba; no ejecuta un dacpac completo.
$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$Server
$builder['Initial Catalog']='Northwind_Test'
$builder['Integrated Security']=$true
$builder['Encrypt']=$true
$builder['TrustServerCertificate']=$true
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try {
    $connection.Open()
    $command=$connection.CreateCommand()
    $command.CommandText=@'
IF DB_NAME()<>N'Northwind_Test' OR NOT EXISTS
    (SELECT 1 FROM sys.extended_properties WHERE class=0
     AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'NorthWind')
    THROW 51002,'Despliegue rechazado: destino no es la copia de origen.',1;
'@
    [void]$command.ExecuteNonQuery()
    foreach($name in @('RowVersionToBigInt','BigIntToRowVersion','GetDatabaseRowVersion','GetCustomerChangesByRowVersion')) {
        $file=Join-Path $PSScriptRoot "..\Northwind.OLTP\dbo\Stored Procedures\$name.sql"
        $sql=Get-Content -LiteralPath $file -Raw
        $command.CommandText=[regex]::Replace($sql,'(?i)CREATE\s+PROCEDURE','CREATE OR ALTER PROCEDURE')
        [void]$command.ExecuteNonQuery()
        Write-Output "Publicado en Northwind_Test: dbo.$name"
    }
    $command.Dispose()
} finally { $connection.Dispose() }
