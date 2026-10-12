<# Crea copias nuevas; una repetición reutiliza las copias marcadas, nunca las restaura encima.
   No hay DROP DATABASE, REPLACE ni reinicio de datos/marcas. #>
[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '..\docs\evidencias\segmento-02')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PreparationSql {
    param([string]$Sql, [string]$Database = 'master')
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 120
        $command.CommandText = $Sql
        $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($command)
        $table = [System.Data.DataTable]::new()
        try { [void]$adapter.Fill($table) } finally { $adapter.Dispose(); $command.Dispose() }
        return ,$table
    } finally { $connection.Dispose() }
}

function ConvertTo-SqlLiteral([string]$Value) { return "N'" + $Value.Replace("'", "''") + "'" }

$paths = Invoke-PreparationSql @'
SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultBackupPath')) AS BackupPath,
       CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultDataPath')) AS DataPath,
       CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultLogPath')) AS LogPath;
'@
foreach ($column in @('BackupPath', 'DataPath', 'LogPath')) {
    if ([string]::IsNullOrWhiteSpace([string]$paths.Rows[0][$column])) {
        throw "Falta la ruta del servidor: $column"
    }
}
$report = @()
# Pares fijos: ningún parámetro permite elegir una base original como destino.
foreach ($pair in @(@('NorthWind', 'Northwind_Test'), @('Northwind_DW', 'Northwind_DW_Test'))) {
    $source = $pair[0]
    $target = $pair[1]
    $existing = Invoke-PreparationSql "SELECT DB_ID(N'$target') AS DatabaseId;"
    if ($existing.Rows[0].DatabaseId -isnot [DBNull]) {
        $check = Invoke-PreparationSql @"
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
    WHERE class=0 AND name=N'NorthwindPracticeTestDatabase'
      AND CONVERT(nvarchar(128),value)=N'$source')
    THROW 51002, 'Base existente sin marca: no se reemplaza ni modifica.', 1;
IF USER_ID(N'NorthwindFixture') IS NULL
    THROW 51004, 'Copia incompleta: falta NorthwindFixture; revisar preparación.', 1;
SELECT name,is_trustworthy_on,is_db_chaining_on FROM sys.databases WHERE name=DB_NAME();
"@ $target
        if ($check.Rows[0].is_trustworthy_on -or $check.Rows[0].is_db_chaining_on) {
            throw "Copia $target con aislamiento desactivado; no se modifica automáticamente."
        }
        $report += [ordered]@{ Source=$source; Target=$target; Action='Reused'; Backup=$null }
        continue
    }

    $suffix = [guid]::NewGuid().ToString('N')
    $backup = Join-Path ([string]$paths.Rows[0].BackupPath) "${target}_${suffix}.bak"
    $backupLiteral = ConvertTo-SqlLiteral $backup
    [void](Invoke-PreparationSql "BACKUP DATABASE [$source] TO DISK=$backupLiteral WITH COPY_ONLY,CHECKSUM,COMPRESSION;")
    $files = Invoke-PreparationSql "RESTORE FILELISTONLY FROM DISK=$backupLiteral;"
    $moves = @()
    $fileIndex = 0
    foreach ($file in $files.Rows) {
        $fileIndex++
        if ($file.Type -notin @('D', 'L')) { throw 'Tipo de archivo no soportado; no se restaura.' }
        $directory = if ($file.Type -eq 'L') { $paths.Rows[0].LogPath } else { $paths.Rows[0].DataPath }
        $extension = if ($file.Type -eq 'L') { 'ldf' } else { 'mdf' }
        $newPath = Join-Path ([string]$directory) "${target}_${suffix}_${fileIndex}.$extension"
        $moves += 'MOVE ' + (ConvertTo-SqlLiteral $file.LogicalName) + ' TO ' + (ConvertTo-SqlLiteral $newPath)
    }
    $moveSql = $moves -join ', '
    [void](Invoke-PreparationSql "RESTORE VERIFYONLY FROM DISK=$backupLiteral WITH CHECKSUM, $moveSql;")
    [void](Invoke-PreparationSql @"
IF DB_ID(N'$target') IS NOT NULL
    THROW 51005, 'El destino apareció durante la preparación; no se reemplaza.', 1;
RESTORE DATABASE [$target] FROM DISK=$backupLiteral WITH CHECKSUM, RECOVERY, $moveSql;
ALTER DATABASE [$target] SET TRUSTWORTHY OFF;
ALTER DATABASE [$target] SET DB_CHAINING OFF;
"@)
    [void](Invoke-PreparationSql @"
SET XACT_ABORT ON;
BEGIN TRANSACTION;
EXEC sys.sp_addextendedproperty @name=N'NorthwindPracticeTestDatabase', @value=N'$source';
CREATE USER [NorthwindFixture] WITHOUT LOGIN;
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE TO [NorthwindFixture];
COMMIT TRANSACTION;
"@ $target)
    $report += [ordered]@{ Source=$source; Target=$target; Action='Created'; Backup=$backup }
}
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$report | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $EvidenceDirectory "preparacion-$stamp.json") -Encoding utf8
$report | ForEach-Object { Write-Output "$($_.Action): $($_.Source) -> $($_.Target)" }
