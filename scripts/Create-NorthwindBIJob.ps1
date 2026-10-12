[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$AnalysisServer = 'localhost',
    [ValidateSet('NorthwindBIJob', 'NorthwindBIJob_Test')]
    [string]$JobName = 'NorthwindBIJob',
    [string]$Folder = 'Northwind',
    [string]$Project = 'Northwind.ETL',
    [ValidateSet('Northwind', 'Northwind_Test')]
    [string]$Environment,
    [string]$Package = 'CargarNorthwind.dtsx',
    [ValidateSet('NorthwindOLAP', 'NorthwindOLAP_Test')]
    [string]$ModelDatabase,
    [ValidateRange(1, 365)]
    [int]$EveryNDays = 1,
    [ValidatePattern('^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$')]
    [string]$StartTime = '02:00:00',
    [switch]$EnableJob,
    [switch]$EnableSchedule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Environment)) {
    $Environment = if ($JobName -eq 'NorthwindBIJob_Test') { 'Northwind_Test' } else { 'Northwind' }
}
if ([string]::IsNullOrWhiteSpace($ModelDatabase)) {
    $ModelDatabase = if ($JobName -eq 'NorthwindBIJob_Test') { 'NorthwindOLAP_Test' } else { 'NorthwindOLAP' }
}
if (-not (
    ($JobName -eq 'NorthwindBIJob' -and $Environment -eq 'Northwind' -and $ModelDatabase -eq 'NorthwindOLAP') -or
    ($JobName -eq 'NorthwindBIJob_Test' -and $Environment -eq 'Northwind_Test' -and $ModelDatabase -eq 'NorthwindOLAP_Test')
)) {
    throw 'Use NorthwindBIJob with Northwind/NorthwindOLAP, or NorthwindBIJob_Test with Northwind_Test/NorthwindOLAP_Test.'
}
$jobMarker = 'Northwind practice job managed by Create-NorthwindBIJob.ps1.'
$scheduleName = "$JobName Schedule"
$startDate = [int](Get-Date -Format 'yyyyMMdd')
$time = [DateTime]::ParseExact($StartTime, 'HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
$activeStartTime = [int]$time.ToString('HHmmss')

function New-SqlConnection([string]$Database) {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    return [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Get-SqlTable([string]$Database, [string]$Text, [hashtable]$Parameters = @{}) {
    $connection = New-SqlConnection $Database
    $command = $null
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 120
        $command.CommandText = $Text
        foreach ($name in $Parameters.Keys) { [void]$command.Parameters.AddWithValue($name, $Parameters[$name]) }
        $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($command)
        $table = [System.Data.DataTable]::new()
        try { [void]$adapter.Fill($table); return ,$table }
        finally { $adapter.Dispose() }
    }
    finally {
        if ($command) { $command.Dispose() }
        $connection.Dispose()
    }
}

function Invoke-Msdb([string]$Text, [hashtable]$Parameters = @{}) {
    $connection = New-SqlConnection 'msdb'
    $command = $null
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 120
        $command.CommandText = $Text
        foreach ($name in $Parameters.Keys) { [void]$command.Parameters.AddWithValue($name, $Parameters[$name]) }
        [void]$command.ExecuteNonQuery()
    }
    finally {
        if ($command) { $command.Dispose() }
        $connection.Dispose()
    }
}

$catalogState = Get-SqlTable 'SSISDB' @'
SELECT f.description AS folder_description,
       p.description AS project_description,
       e.description AS environment_description,
       r.reference_id,
       r.reference_type,
       r.environment_folder_name,
       r.environment_name,
       COUNT(k.name) AS package_count
FROM catalog.folders AS f
JOIN catalog.projects AS p ON p.folder_id = f.folder_id
JOIN catalog.environment_references AS r ON r.project_id = p.project_id
LEFT JOIN catalog.environments AS e
  ON e.name = r.environment_name
 AND e.folder_id = CASE WHEN r.environment_folder_name IS NULL THEN p.folder_id
                         ELSE (SELECT folder_id FROM catalog.folders WHERE name = r.environment_folder_name) END
LEFT JOIN catalog.packages AS k ON k.project_id = p.project_id AND k.name = @Package
WHERE f.name = @Folder AND p.name = @Project
  AND (r.environment_folder_name = @Folder OR r.environment_folder_name IS NULL)
  AND r.environment_name = @Environment
GROUP BY f.description, p.description, e.description, r.reference_id,
         r.reference_type, r.environment_folder_name, r.environment_name;
'@ @{ '@Folder' = $Folder; '@Project' = $Project; '@Environment' = $Environment; '@Package' = $Package }
if ($catalogState.Rows.Count -ne 1) {
    throw "No se encontró una única referencia de entorno para SSISDB/$Folder/$Project/$Environment. Publique primero Northwind.ETL."
}
$catalogRow = $catalogState.Rows[0]
if (([string]$catalogRow.folder_description).Trim() -cne 'Northwind practice folder managed by Publish-NorthwindETL.ps1.' -or
    ([string]$catalogRow.project_description).Trim() -cne 'Northwind practice project managed by Publish-NorthwindETL.ps1.' -or
    ([string]$catalogRow.environment_description).Trim() -cne 'Northwind practice environment managed by Publish-NorthwindETL.ps1.' -or
    [string]$catalogRow.reference_type -cne 'R' -or [long]$catalogRow.package_count -ne 1) {
    throw 'Folder, proyecto, entorno o paquete SSIS no coincide con los objetos propios esperados; no se creó el job.'
}

$expectedSourceDatabase = if ($JobName -eq 'NorthwindBIJob_Test') { 'Northwind_Test' } else { 'NorthWind' }
$expectedWarehouseDatabase = if ($JobName -eq 'NorthwindBIJob_Test') { 'Northwind_DW_Test' } else { 'Northwind_DW' }
$environmentValues = Get-SqlTable 'SSISDB' @'
SELECT v.name, CONVERT(nvarchar(4000), v.value) AS value
FROM catalog.environment_variables AS v
JOIN catalog.environments AS e ON e.environment_id = v.environment_id
JOIN catalog.folders AS f ON f.folder_id = e.folder_id
WHERE f.name = @Folder AND e.name = @Environment
  AND v.name IN (N'SourceDatabase', N'WarehouseDatabase');
'@ @{ '@Folder' = $Folder; '@Environment' = $Environment }
$sourceValue = @($environmentValues.Rows | Where-Object { [string]$_.name -ceq 'SourceDatabase' })
$warehouseValue = @($environmentValues.Rows | Where-Object { [string]$_.name -ceq 'WarehouseDatabase' })
if ($sourceValue.Count -ne 1 -or $warehouseValue.Count -ne 1 -or
    [string]$sourceValue[0].value -cne $expectedSourceDatabase -or
    [string]$warehouseValue[0].value -cne $expectedWarehouseDatabase) {
    throw "El entorno '$Environment' no apunta a '$expectedSourceDatabase' y '$expectedWarehouseDatabase'; no se creó el job."
}

$subsystems = Get-SqlTable 'msdb' @'
SELECT subsystem, agent_exe FROM dbo.syssubsystems WHERE subsystem IN (N'SSIS', N'ANALYSISCOMMAND');
'@
if (@($subsystems.Rows | Select-Object -ExpandProperty subsystem -Unique).Count -ne 2) {
    throw 'SQL Server Agent no ofrece los subsistemas SSIS y ANALYSISCOMMAND requeridos.'
}
$owner = [string](Get-SqlTable 'master' 'SELECT SUSER_SNAME() AS owner_name;' @{}).Rows[0].owner_name

$jobState = Get-SqlTable 'msdb' @'
SELECT job_id, description FROM dbo.sysjobs WHERE name = @JobName;
'@ @{ '@JobName' = $JobName }
if ($jobState.Rows.Count -gt 0 -and [string]$jobState.Rows[0].description -cne $jobMarker) {
    throw "Ya existe el job '$JobName' y no tiene el marcador de propiedad de esta práctica; no se modificó."
}
$jobId = if ($jobState.Rows.Count -eq 1) { [Guid]$jobState.Rows[0].job_id } else { [Guid]::Empty }
if ($jobId -ne [Guid]::Empty) {
    $steps = Get-SqlTable 'msdb' 'SELECT step_id FROM dbo.sysjobsteps WHERE job_id = @JobId ORDER BY step_id;' @{ '@JobId' = $jobId }
    if (@($steps.Rows | Where-Object { [int]$_.step_id -gt 2 }).Count -gt 0) {
        throw "El job propio '$JobName' contiene etapas adicionales; revíselas antes de actualizarlo."
    }
    $linkedSchedules = Get-SqlTable 'msdb' @'
SELECT s.schedule_id, s.name
FROM dbo.sysjobschedules AS js
JOIN dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
WHERE js.job_id = @JobId;
'@ @{ '@JobId' = $jobId }
    if ($linkedSchedules.Rows.Count -gt 1) { throw "El job '$JobName' tiene más de un horario adjunto; no se modificó." }
    if ($linkedSchedules.Rows.Count -eq 1 -and [string]$linkedSchedules.Rows[0].name -cne $scheduleName) {
        throw "El job '$JobName' tiene un horario distinto al administrado por este script; no se modificó."
    }
}

$scheduleState = Get-SqlTable 'msdb' @'
SELECT schedule_id, name,
       CASE WHEN owner_sid = SUSER_SID(@Owner) THEN 1 ELSE 0 END AS is_owner
FROM dbo.sysschedules WHERE name = @ScheduleName;
'@ @{ '@ScheduleName' = $scheduleName; '@Owner' = $owner }
if ($scheduleState.Rows.Count -gt 1) { throw "Hay horarios duplicados con el nombre '$scheduleName'." }
if ($scheduleState.Rows.Count -eq 1) {
    if ($jobId -eq [Guid]::Empty -or $linkedSchedules.Rows.Count -ne 1 -or
        [int]$linkedSchedules.Rows[0].schedule_id -ne [int]$scheduleState.Rows[0].schedule_id -or
        [int]$scheduleState.Rows[0].is_owner -ne 1) {
        throw "El horario '$scheduleName' no está vinculado exclusivamente al job propio y al operador actual; no se modificó."
    }
    $foreignLink = Get-SqlTable 'msdb' @'
SELECT COUNT(*) AS links
FROM dbo.sysjobschedules
WHERE schedule_id = @ScheduleId AND job_id <> (SELECT job_id FROM dbo.sysjobs WHERE name = @JobName);
'@ @{ '@ScheduleId' = [int]$scheduleState.Rows[0].schedule_id; '@JobName' = $JobName }
    if ([int]$foreignLink.Rows[0].links -gt 0) { throw "El horario '$scheduleName' se comparte con otro job; no se modificó." }
}

$packagePath = "\SSISDB\$Folder\$Project\$Package"
$referenceId = [long]$catalogRow.reference_id
$ssisCommand = '/ISSERVER "\"' + $packagePath + '\"" /SERVER ' + $Server + ' /ENVREFERENCE ' + $referenceId + ' /Par "\"$ServerOption::LOGGING_LEVEL(Int16)\"";1 /Par "\"$ServerOption::SYNCHRONIZED(Boolean)\"";True /CALLERINFO SQLAGENT /REPORTING E'
$analysisCommand = [ordered]@{
    refresh = [ordered]@{
        type = 'full'
        objects = @(@{ database = $ModelDatabase })
    }
} | ConvertTo-Json -Depth 8 -Compress
$enabledJob = [int][bool]$EnableJob
$enabledSchedule = [int][bool]$EnableSchedule

if ($jobId -eq [Guid]::Empty) {
    Invoke-Msdb @'
EXEC dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 0,
    @description = @Description,
    @start_step_id = 1,
    @owner_login_name = @Owner;
EXEC dbo.sp_add_jobserver @job_name = @JobName, @server_name = N'(LOCAL)';
'@ @{ '@JobName' = $JobName; '@Description' = $jobMarker; '@Owner' = $owner }
}
else {
    Invoke-Msdb @'
EXEC dbo.sp_update_job @job_name = @JobName, @enabled = 0, @description = @Description;
'@ @{ '@JobName' = $JobName; '@Description' = $jobMarker }
}

$stepOne = Get-SqlTable 'msdb' 'SELECT COUNT(*) AS step_count FROM dbo.sysjobsteps WHERE job_id = (SELECT job_id FROM dbo.sysjobs WHERE name = @JobName) AND step_id = 1;' @{ '@JobName' = $JobName }
if ([int]$stepOne.Rows[0].step_count -eq 0) {
    Invoke-Msdb @'
EXEC dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_id = 1,
    @step_name = N'Load Northwind ETL',
    @subsystem = N'SSIS',
    @command = @Command,
    @database_name = N'SSISDB',
    @on_success_action = 3,
    @on_fail_action = 2,
    @retry_attempts = 0;
'@ @{ '@JobName' = $JobName; '@Command' = $ssisCommand }
}
else {
    Invoke-Msdb @'
EXEC dbo.sp_update_jobstep
    @job_name = @JobName,
    @step_id = 1,
    @step_name = N'Load Northwind ETL',
    @subsystem = N'SSIS',
    @command = @Command,
    @database_name = N'SSISDB',
    @on_success_action = 3,
    @on_fail_action = 2,
    @retry_attempts = 0;
'@ @{ '@JobName' = $JobName; '@Command' = $ssisCommand }
}

$stepTwo = Get-SqlTable 'msdb' 'SELECT COUNT(*) AS step_count FROM dbo.sysjobsteps WHERE job_id = (SELECT job_id FROM dbo.sysjobs WHERE name = @JobName) AND step_id = 2;' @{ '@JobName' = $JobName }
if ([int]$stepTwo.Rows[0].step_count -eq 0) {
    Invoke-Msdb @'
EXEC dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_id = 2,
    @step_name = N'Process Northwind OLAP',
    @subsystem = N'ANALYSISCOMMAND',
    @server = @AnalysisServer,
    @command = @Command,
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 0;
'@ @{ '@JobName' = $JobName; '@AnalysisServer' = $AnalysisServer; '@Command' = $analysisCommand }
}
else {
    Invoke-Msdb @'
EXEC dbo.sp_update_jobstep
    @job_name = @JobName,
    @step_id = 2,
    @step_name = N'Process Northwind OLAP',
    @subsystem = N'ANALYSISCOMMAND',
    @server = @AnalysisServer,
    @command = @Command,
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 0;
'@ @{ '@JobName' = $JobName; '@AnalysisServer' = $AnalysisServer; '@Command' = $analysisCommand }
}

if ($scheduleState.Rows.Count -eq 0) {
    Invoke-Msdb @'
DECLARE @scheduleId int;
EXEC dbo.sp_add_schedule
    @schedule_name = @ScheduleName,
    @enabled = @Enabled,
    @freq_type = 4,
    @freq_interval = @EveryNDays,
    @freq_recurrence_factor = 1,
    @active_start_date = @StartDate,
    @active_start_time = @StartTime,
    @owner_login_name = @Owner,
    @schedule_id = @scheduleId OUTPUT;
EXEC dbo.sp_attach_schedule @job_name = @JobName, @schedule_id = @scheduleId;
'@ @{ '@ScheduleName' = $scheduleName; '@Enabled' = $enabledSchedule; '@EveryNDays' = $EveryNDays; '@StartDate' = $startDate; '@StartTime' = $activeStartTime; '@Owner' = $owner; '@JobName' = $JobName }
}
else {
    $scheduleId = [int]$scheduleState.Rows[0].schedule_id
    $jobLink = Get-SqlTable 'msdb' @'
SELECT COUNT(*) AS linked FROM dbo.sysjobschedules
WHERE job_id = (SELECT job_id FROM dbo.sysjobs WHERE name = @JobName) AND schedule_id = @ScheduleId;
'@ @{ '@JobName' = $JobName; '@ScheduleId' = $scheduleId }
    Invoke-Msdb @'
EXEC dbo.sp_update_schedule
    @schedule_id = @ScheduleId,
    @enabled = @Enabled,
    @freq_type = 4,
    @freq_interval = @EveryNDays,
    @freq_recurrence_factor = 1,
    @active_start_date = @StartDate,
    @active_start_time = @StartTime;
'@ @{ '@ScheduleId' = $scheduleId; '@Enabled' = $enabledSchedule; '@EveryNDays' = $EveryNDays; '@StartDate' = $startDate; '@StartTime' = $activeStartTime }
    if ([int]$jobLink.Rows[0].linked -eq 0) {
        Invoke-Msdb 'EXEC dbo.sp_attach_schedule @job_name = @JobName, @schedule_id = @ScheduleId;' @{ '@JobName' = $JobName; '@ScheduleId' = $scheduleId }
    }
}

Invoke-Msdb 'EXEC dbo.sp_update_job @job_name = @JobName, @enabled = @Enabled;' @{ '@JobName' = $JobName; '@Enabled' = $enabledJob }
Write-Output "Job '$JobName' configurado (SSIS y ANALYSISCOMMAND). Horario '$scheduleName'; descripción: $jobMarker"
