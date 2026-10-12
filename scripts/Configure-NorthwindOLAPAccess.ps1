[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [ValidateSet('Northwind_DW', 'Northwind_DW_Test')]
    [string]$WarehouseDatabase = 'Northwind_DW_Test'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$service = Get-CimInstance Win32_Service -Filter "Name='MSSQLServerOLAPService'"
if (-not $service -or $service.State -ne 'Running') {
    throw 'Inicia el servicio SQL Server Analysis Services (MSSQLSERVER) antes de configurar el acceso.'
}

$principal = [string]$service.StartName
if ([string]::IsNullOrWhiteSpace($principal)) {
    throw 'No se pudo determinar la cuenta del servicio de Analysis Services.'
}

$connectionString = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionString['Data Source'] = $Server
$connectionString['Initial Catalog'] = 'master'
$connectionString['Integrated Security'] = $true
$connectionString['Encrypt'] = $true
$connectionString['TrustServerCertificate'] = $true

$connection = [System.Data.SqlClient.SqlConnection]::new($connectionString.ConnectionString)
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @'
DECLARE @database sysname = @WarehouseDatabase;
DECLARE @principal sysname = @ServicePrincipal;
DECLARE @databaseId int = DB_ID(@database);
IF @databaseId IS NULL
    THROW 51201, 'No existe la base de datos de prueba indicada.', 1;

DECLARE @isMarkedTest bit = 0;
DECLARE @sql nvarchar(max) = N'
SELECT @isMarkedTest = 1
FROM ' + QUOTENAME(@database) + N'.sys.extended_properties
WHERE class = 0
  AND name = N''NorthwindPracticeTestDatabase''
  AND CONVERT(nvarchar(128), value) = N''Northwind_DW'';';
EXEC sys.sp_executesql @sql, N'@isMarkedTest bit OUTPUT', @isMarkedTest OUTPUT;
IF @database = N'Northwind_DW_Test' AND @isMarkedTest = 0
    THROW 51202, 'Northwind_DW_Test debe estar marcada como copia aislada.', 1;
IF @database = N'Northwind_DW' AND @isMarkedTest = 1
    THROW 51203, 'Northwind_DW está marcada como copia de prueba; se rechazó el acceso.', 1;

IF SUSER_ID(@principal) IS NULL
BEGIN
    SET @sql = N'CREATE LOGIN ' + QUOTENAME(@principal) + N' FROM WINDOWS;';
    EXEC sys.sp_executesql @sql;
END;

SET @sql = N'
USE ' + QUOTENAME(@database) + N';
IF USER_ID(@principal) IS NULL
    CREATE USER ' + QUOTENAME(@principal) + N' FOR LOGIN ' + QUOTENAME(@principal) + N';
GRANT SELECT ON OBJECT::dbo.Dim_Cliente TO ' + QUOTENAME(@principal) + N';
GRANT SELECT ON OBJECT::dbo.Dim_Empleado TO ' + QUOTENAME(@principal) + N';
GRANT SELECT ON OBJECT::dbo.Dim_Producto TO ' + QUOTENAME(@principal) + N';
GRANT SELECT ON OBJECT::dbo.Dim_Transportista TO ' + QUOTENAME(@principal) + N';
GRANT SELECT ON OBJECT::dbo.Dim_Tiempo TO ' + QUOTENAME(@principal) + N';
GRANT SELECT ON OBJECT::dbo.Fact_Ventas TO ' + QUOTENAME(@principal) + N';';
EXEC sys.sp_executesql @sql, N'@principal sysname', @principal;
'@
    [void]$command.Parameters.AddWithValue('@WarehouseDatabase', $WarehouseDatabase)
    [void]$command.Parameters.AddWithValue('@ServicePrincipal', $principal)
    [void]$command.ExecuteNonQuery()
    $command.Dispose()
}
finally {
    $connection.Dispose()
}

Write-Output "Acceso de lectura configurado para '$principal' en '$WarehouseDatabase' ($Server)."
