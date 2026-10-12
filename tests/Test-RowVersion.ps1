[CmdletBinding()]
param([string]$Server = 'localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force

function Get-TestRows {
    param([System.Data.SqlClient.SqlConnection]$Connection,[string]$Sql)
    $command=$Connection.CreateCommand()
    $command.CommandText=$Sql
    $command.CommandTimeout=2
    $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($command)
    $table=[System.Data.DataTable]::new()
    try { [void]$adapter.Fill($table); return ,$table }
    finally { $adapter.Dispose();$command.Dispose() }
}

function Get-CustomerChanges {
    param([System.Data.SqlClient.SqlConnection]$Connection,[long]$Start,[long]$End)
    $command=$Connection.CreateCommand()
    $command.CommandText='dbo.GetCustomerChangesByRowVersion'
    $command.CommandType=[System.Data.CommandType]::StoredProcedure
    $command.CommandTimeout=1
    [void]$command.Parameters.Add('@startRow',[System.Data.SqlDbType]::BigInt)
    $command.Parameters['@startRow'].Value=$Start
    [void]$command.Parameters.Add('@endRow',[System.Data.SqlDbType]::BigInt)
    $command.Parameters['@endRow'].Value=$End
    $adapter=[System.Data.SqlClient.SqlDataAdapter]::new($command)
    $table=[System.Data.DataTable]::new()
    try { [void]$adapter.Fill($table); return ,$table }
    finally { $adapter.Dispose();$command.Dispose() }
}

$connections=@()
$writerA=$null
$writerB=$null
$reader=$null
$originals=$null
try {
    $writerA=New-NorthwindTestConnection -Server $Server -Database Northwind_Test
    $connections+= $writerA
    $writerB=New-NorthwindTestConnection -Server $Server -Database Northwind_Test
    $connections+= $writerB
    $reader=New-NorthwindTestConnection -Server $Server -Database Northwind_Test
    $connections+= $reader
    [void](Get-TestRows $reader 'SET TRANSACTION ISOLATION LEVEL READ COMMITTED;')
    $initial=[long](Get-TestRows $reader 'EXEC dbo.GetDatabaseRowVersion;').Rows[0].DBTS
    $options=Get-TestRows $reader 'DBCC USEROPTIONS WITH NO_INFOMSGS;'
    $isolation=@($options.Rows | Where-Object { $_[0] -eq 'isolation level' })[0][1]
    if ($isolation -notin @('read committed','read committed snapshot')) { throw 'GetDatabaseRowVersion cambió el aislamiento de la sesión RC.' }
    Write-Output 'PASS: conexión reutilizada conserva READ COMMITTED después del corte.'

    # Parámetros reales ADO.NET de tipo Int64 y Binary(8), sin float/Double.
    foreach($value in @([long]0,[long]1,[long]9007199254740993,[long]::MaxValue)) {
        $command=$reader.CreateCommand()
        $command.CommandType=[System.Data.CommandType]::StoredProcedure
        $command.CommandText='dbo.BigIntToRowVersion'
        [void]$command.Parameters.Add('@Value',[System.Data.SqlDbType]::BigInt)
        $command.Parameters['@Value'].Value=$value
        $output=$command.Parameters.Add('@RowVersion',[System.Data.SqlDbType]::Binary,8)
        $output.Direction=[System.Data.ParameterDirection]::Output
        [void]$command.ExecuteNonQuery()
        $binary=[byte[]]$output.Value
        $command.Dispose()
        $command=$reader.CreateCommand()
        $command.CommandType=[System.Data.CommandType]::StoredProcedure
        $command.CommandText='dbo.RowVersionToBigInt'
        [void]$command.Parameters.Add('@RowVersion',[System.Data.SqlDbType]::Binary,8)
        $command.Parameters['@RowVersion'].Value=$binary
        $output=$command.Parameters.Add('@Value',[System.Data.SqlDbType]::BigInt)
        $output.Direction=[System.Data.ParameterDirection]::Output
        [void]$command.ExecuteNonQuery()
        if ([long]$output.Value -ne $value) { throw 'Parámetros ADO.NET perdieron precisión.' }
        $command.Dispose()
    }
    Write-Output 'PASS: parámetros ADO.NET Binary(8)/Int64 conservan todos los bits representables.'
    $originals=Get-TestRows $reader "SELECT CustomerID,CompanyName FROM dbo.Customers WHERE CustomerID IN(N'VINET',N'ALFKI');"
    if ($originals.Rows.Count -ne 2) { throw 'Faltan clientes de referencia.' }

    $a=Get-TestRows $writerA @'
BEGIN TRANSACTION;
UPDATE dbo.Customers SET CompanyName=N'Prueba pendiente A'
OUTPUT CONVERT(bigint,inserted.[rowversion]) AS RV WHERE CustomerID=N'VINET';
'@
    $b=Get-TestRows $writerB @'
UPDATE dbo.Customers SET CompanyName=N'Prueba confirmada B'
OUTPUT CONVERT(bigint,inserted.[rowversion]) AS RV WHERE CustomerID=N'ALFKI';
'@
    $pendingCut=[long](Get-TestRows $reader 'EXEC dbo.GetDatabaseRowVersion;').Rows[0].DBTS
    if ($pendingCut -ge [long]$a.Rows[0].RV -or $pendingCut -ge [long]$b.Rows[0].RV) {
        throw 'El corte avanzó sobre la transacción pendiente.'
    }
    Write-Output 'PASS: corte anterior a escritura A pendiente y a escritura B posterior ya confirmada.'

    # Intentar extracción completa desde un llamador RU: el procedimiento exige RC.
    [void](Get-TestRows $reader 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;')
    $blocked=$false
    try {
        $during=Get-CustomerChanges $reader $initial ([long]::MaxValue)
        if (@($during.Rows | Where-Object { $_.CustomerID.Trim() -eq 'VINET' }).Count) {
            throw 'Se leyó el valor no confirmado de VINET.'
        }
        Write-Output 'PASS: lectura RC con versionado no publica el valor pendiente.'
    } catch {
        $exception=$_.Exception
        while ($exception -isnot [System.Data.SqlClient.SqlException] -and $exception.InnerException) {
            $exception=$exception.InnerException
        }
        if ($exception -isnot [System.Data.SqlClient.SqlException] -or $exception.Number -ne -2) { throw }
        $blocked=$true
        Write-Output 'PASS: lectura RC bloqueada por escritura pendiente; no entrega datos sucios.'
    }
    [void](Get-TestRows $writerA 'COMMIT TRANSACTION;')
    [void](Get-TestRows $reader 'SET TRANSACTION ISOLATION LEVEL READ COMMITTED;')
    $before=Get-CustomerChanges $reader $initial $pendingCut
    if ($before.Rows.Count -ne 0) { throw 'El intervalo anterior al corte incluyó filas posteriores.' }
    $nextCut=[long](Get-TestRows $reader 'EXEC dbo.GetDatabaseRowVersion;').Rows[0].DBTS
    $after=Get-CustomerChanges $reader $pendingCut $nextCut
    if ($after.Rows.Count -ne 2 -or
        @($after.Rows | Where-Object { $_.CustomerID.Trim() -in @('VINET','ALFKI') }).Count -ne 2) {
        throw 'Cambios confirmados no reaparecieron una vez en el siguiente intervalo.'
    }
    $repeat=Get-CustomerChanges $reader $nextCut $nextCut
    if ($repeat.Rows.Count) { throw 'Intervalo vacío repitió filas.' }
    Write-Output 'PASS: commit libera el corte; A y B aparecen una vez en el siguiente intervalo.'
    $options=Get-TestRows $reader 'DBCC USEROPTIONS WITH NO_INFOMSGS;'
    $isolation=@($options.Rows | Where-Object { $_[0] -eq 'isolation level' })[0][1]
    if ($isolation -notin @('read committed','read committed snapshot')) { throw 'Extracción dejó READ UNCOMMITTED en la conexión RC.' }
    Write-Output "PASS: sesión final RC; prueba de bloqueo=$blocked."
} finally {
    if ($writerA) {
        try { [void](Get-TestRows $writerA 'IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;') }
        finally { $writerA.Dispose() }
    }
    if ($writerB -and $originals) {
        try {
            foreach($row in $originals.Rows) {
                $command=$writerB.CreateCommand()
                $command.CommandText='UPDATE dbo.Customers SET CompanyName=@name WHERE CustomerID=@id;'
                [void]$command.Parameters.AddWithValue('@name',$row.CompanyName)
                [void]$command.Parameters.AddWithValue('@id',$row.CustomerID)
                try { [void]$command.ExecuteNonQuery() } finally { $command.Dispose() }
            }
        } finally { $writerB.Dispose() }
    }
    foreach($connection in $connections) { $connection.Dispose() }
}
