[CmdletBinding()]
param(
    [string]$Server='localhost',
    [ValidateSet('NorthWind','Northwind_Test')]
    [string]$SourceDatabase='NorthWind',
    [string]$EvidenceDirectory=(Join-Path $PSScriptRoot '../docs/evidencias/extractores')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$names=@('RowVersionToBigInt','BigIntToRowVersion','GetDatabaseRowVersion',
    'GetCustomerChangesByRowVersion','GetEmployeeChangesByRowVersion','GetProductChangesByRowVersion',
    'GetShipperChangesByRowVersion','GetSupplierChangesByRowVersion','GetSalesChangesByRowVersion')
$builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$Server;$builder['Initial Catalog']=$SourceDatabase
$builder['Integrated Security']=$true;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$true
$connection=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$transaction=$null
try{
    $connection.Open();$command=$connection.CreateCommand()
    $command.CommandText=@'
IF DB_NAME()<>@database THROW 51002,'Destino inesperado.',1;
DECLARE @marker nvarchar(128)=(SELECT CONVERT(nvarchar(128),value) FROM sys.extended_properties
 WHERE class=0 AND name=N'NorthwindPracticeTestDatabase');
IF (DB_NAME()=N'Northwind_Test' AND (@marker IS NULL OR @marker<>N'NorthWind'))
 OR (DB_NAME()=N'NorthWind' AND @marker IS NOT NULL)
 THROW 51002,'La marca de origen no corresponde al destino.',1;
IF (SELECT COUNT(*) FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id
 WHERE t.schema_id=SCHEMA_ID(N'dbo') AND t.name IN
 (N'Customers',N'Employees',N'Products',N'Categories',N'Suppliers',N'Shippers',N'Orders',N'OrderDetails')
 AND c.name=N'rowversion' AND c.system_type_id=189)<>8
 THROW 51005,'Publique primero Northwind.OLTP: faltan las columnas rowversion.',1;
SELECT name,OBJECT_DEFINITION(object_id) AS Definition FROM sys.procedures
 WHERE schema_id=SCHEMA_ID(N'dbo') AND name IN
 (N'RowVersionToBigInt',N'BigIntToRowVersion',N'GetDatabaseRowVersion',N'GetCustomerChangesByRowVersion',
 N'GetEmployeeChangesByRowVersion',N'GetProductChangesByRowVersion',N'GetShipperChangesByRowVersion',
 N'GetSupplierChangesByRowVersion',N'GetSalesChangesByRowVersion');
'@
    [void]$command.Parameters.AddWithValue('@database',$SourceDatabase)
    $adapter=[Data.SqlClient.SqlDataAdapter]::new($command);$before=[Data.DataSet]::new()
    try{[void]$adapter.Fill($before)}finally{$adapter.Dispose()}
    New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
    $before.WriteXml((Join-Path $EvidenceDirectory ('procedimientos-antes-'+[guid]::NewGuid().ToString('N')+'.xml')))
    $command.Parameters.Clear();$transaction=$connection.BeginTransaction();$command.Transaction=$transaction
    foreach($name in $names){
        $sql=Get-Content -LiteralPath (Join-Path $PSScriptRoot "../Northwind.OLTP/dbo/Stored Procedures/$name.sql") -Raw
        $command.CommandText=[regex]::Replace($sql,'(?i)CREATE\s+PROCEDURE','CREATE OR ALTER PROCEDURE')
        [void]$command.ExecuteNonQuery()
    }
    $transaction.Commit();$transaction.Dispose();$transaction=$null
    $command.Dispose()
    Write-Output "Nueve procedimientos publicados en $SourceDatabase; datos y rowversions conservados."
}finally{
    if($null -ne $transaction){$transaction.Rollback();$transaction.Dispose()}
    $connection.Dispose()
}
