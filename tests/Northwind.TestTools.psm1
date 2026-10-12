Set-StrictMode -Version Latest

function New-NorthwindTestConnection {
    <# Conexión restringida para pruebas de varias sesiones. El llamador debe Dispose(). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Northwind_Test', 'Northwind_DW_Test')]
        [string]$Database,
        [string]$Server = 'localhost'
    )

    $ErrorActionPreference = 'Stop'
    $expectedSource = if ($Database -eq 'Northwind_Test') { 'NorthWind' } else { 'Northwind_DW' }
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    # NO REVERT no debe dejar una sesión impersonada reutilizable en el pool.
    $builder['Pooling'] = $false
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open()
        $guard = $connection.CreateCommand()
        $guard.CommandText = @'
IF DB_NAME() <> @database
    THROW 51001, 'Base inesperada: fixtures rechazados.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
    WHERE class = 0 AND name = N'NorthwindPracticeTestDatabase'
      AND CONVERT(nvarchar(128), value) = @source)
    THROW 51002, 'La base no es una copia de prueba marcada.', 1;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME()
    AND (is_trustworthy_on = 1 OR is_db_chaining_on = 1))
    THROW 51003, 'Aislamiento de base desactivado: fixtures rechazados.', 1;
IF USER_ID(N'NorthwindFixture') IS NULL
    THROW 51004, 'Falta el usuario restringido de fixtures.', 1;
'@
        [void]$guard.Parameters.AddWithValue('@database', $Database)
        [void]$guard.Parameters.AddWithValue('@source', $expectedSource)
        [void]$guard.ExecuteNonQuery()
        $guard.Dispose()
        # NO REVERT exige un batch ad hoc, separado del comando parametrizado.
        $identity = $connection.CreateCommand()
        $identity.CommandText = "EXECUTE AS USER = N'NorthwindFixture' WITH NO REVERT;"
        [void]$identity.ExecuteNonQuery()
        $identity.Dispose()
        return $connection
    } catch { $connection.Dispose(); throw }
}

function Invoke-NorthwindTestSql {
    <# Un batch sin GO; revierte por defecto, -Commit confirma el fixture. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Northwind_Test', 'Northwind_DW_Test')]
        [string]$Database,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Sql,
        [string]$Server = 'localhost',
        [switch]$Commit
    )
    $ErrorActionPreference = 'Stop'
    $connection = New-NorthwindTestConnection -Database $Database -Server $Server
    try {
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 60
        $finish = if ($Commit) { 'COMMIT TRANSACTION;' } else { 'ROLLBACK TRANSACTION;' }
        $command.CommandText = "SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;`n$Sql`n$finish"
        $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($command)
        $result = [System.Data.DataSet]::new()
        try { [void]$adapter.Fill($result) } finally { $adapter.Dispose(); $command.Dispose() }
        return ,$result
    }
    finally {
        # Una conexión cerrada también revierte la transacción si el batch falla.
        $connection.Dispose()
    }
}

Export-ModuleMember -Function Invoke-NorthwindTestSql, New-NorthwindTestConnection
