/*
    Creates or updates the Northwind practice SQL Server Agent job.

    Run the whole script in SSMS while connected to the SQL Server instance
    that hosts SSISDB and SQL Server Agent. Edit the values in the configuration
    block before execution. The job and its daily schedule are disabled by
    default. This script only manages the job and schedule whose names and
    ownership marker match this practice; it does not create SSISDB, publish a
    project, grant permissions, or change Analysis Services roles.
*/
USE [msdb];
SET NOCOUNT ON;

DECLARE @SqlServer nvarchar(128) = N'localhost';
DECLARE @AnalysisServer nvarchar(128) = N'localhost';
DECLARE @JobName sysname = N'NorthwindBIJob'; -- NorthwindBIJob or NorthwindBIJob_Test
DECLARE @Folder sysname = N'Northwind';
DECLARE @Project sysname = N'Northwind.ETL';
DECLARE @Environment sysname = N'Northwind';
DECLARE @Package sysname = N'CargarNorthwind.dtsx';
DECLARE @ModelDatabase sysname = N'NorthwindOLAP';
DECLARE @EveryNDays int = 1;
DECLARE @StartTime char(8) = '02:00:00'; -- HH:mm:ss, local SQL Server Agent time
DECLARE @EnableJob bit = 0;
DECLARE @EnableSchedule bit = 0;

DECLARE @JobMarker nvarchar(512) = N'Northwind practice job managed by Create-NorthwindBIJob.ps1.';
DECLARE @ScheduleName sysname = @JobName + N' Schedule';
DECLARE @JobOwner sysname = SUSER_SNAME();
DECLARE @JobId uniqueidentifier;
DECLARE @EnvironmentReferenceId bigint;
DECLARE @ExpectedSourceDatabase sysname = CASE WHEN @JobName = N'NorthwindBIJob_Test' THEN N'Northwind_Test' ELSE N'NorthWind' END;
DECLARE @ExpectedWarehouseDatabase sysname = CASE WHEN @JobName = N'NorthwindBIJob_Test' THEN N'Northwind_DW_Test' ELSE N'Northwind_DW' END;
DECLARE @ConfiguredSourceDatabase sysname;
DECLARE @ConfiguredWarehouseDatabase sysname;
DECLARE @ReferenceCount int;
DECLARE @ScheduleId int;
DECLARE @ScheduleCount int;
DECLARE @LinkedScheduleCount int;
DECLARE @ForeignScheduleLinks int;
DECLARE @StepCount int;
DECLARE @StartDate int = CONVERT(int, CONVERT(char(8), GETDATE(), 112));
DECLARE @ActiveStartTime int;
DECLARE @SsisCommand nvarchar(max);
DECLARE @AnalysisCommand nvarchar(max);
DECLARE @Command nvarchar(max);
DECLARE @ExistingDescription nvarchar(512);

IF NOT (
       (@JobName = N'NorthwindBIJob' AND @Environment = N'Northwind' AND @ModelDatabase = N'NorthwindOLAP')
    OR (@JobName = N'NorthwindBIJob_Test' AND @Environment = N'Northwind_Test' AND @ModelDatabase = N'NorthwindOLAP_Test')
)
    THROW 51000, 'Use NorthwindBIJob with Northwind/NorthwindOLAP, or NorthwindBIJob_Test with Northwind_Test/NorthwindOLAP_Test.', 1;
IF @EveryNDays NOT BETWEEN 1 AND 365
    THROW 51000, 'EveryNDays must be between 1 and 365.', 1;
IF TRY_CONVERT(time(0), @StartTime) IS NULL
    THROW 51000, 'StartTime must use HH:mm:ss.', 1;
SET @ActiveStartTime = CONVERT(int, REPLACE(@StartTime, ':', ''));

IF DB_ID(N'SSISDB') IS NULL
    THROW 51000, 'SSISDB does not exist. Create the catalog and publish Northwind.ETL first.', 1;

/* Resolve and verify the published project, environment reference, and package. */
SELECT
    @ReferenceCount = COUNT(DISTINCT r.reference_id),
    @EnvironmentReferenceId = MAX(r.reference_id)
FROM [SSISDB].[catalog].[folders] AS f
JOIN [SSISDB].[catalog].[projects] AS p
  ON p.folder_id = f.folder_id
JOIN [SSISDB].[catalog].[environment_references] AS r
  ON r.project_id = p.project_id
JOIN [SSISDB].[catalog].[environments] AS e
  ON e.name = r.environment_name
 AND e.folder_id = CASE
        WHEN r.environment_folder_name IS NULL THEN p.folder_id
        ELSE (SELECT ef.folder_id
              FROM [SSISDB].[catalog].[folders] AS ef
              WHERE ef.name = r.environment_folder_name)
     END
WHERE f.name = @Folder
  AND p.name = @Project
  AND r.environment_name = @Environment
  AND (r.environment_folder_name = @Folder OR r.environment_folder_name IS NULL)
  AND r.reference_type = 'R'
  AND COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM f.description), N'')
      = N'Northwind practice folder managed by Publish-NorthwindETL.ps1.'
  AND COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM p.description), N'')
      = N'Northwind practice project managed by Publish-NorthwindETL.ps1.'
  AND COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM e.description), N'')
      = N'Northwind practice environment managed by Publish-NorthwindETL.ps1.'
  AND EXISTS (
      SELECT 1
      FROM [SSISDB].[catalog].[packages] AS k
      WHERE k.project_id = p.project_id
        AND k.name = @Package
  );

IF @ReferenceCount <> 1 OR @EnvironmentReferenceId IS NULL
    THROW 51000, 'No unique owned SSIS project/environment/package reference was found. Publish Northwind.ETL first.', 1;

SELECT
    @ConfiguredSourceDatabase = MAX(CASE WHEN v.name = N'SourceDatabase' THEN CONVERT(nvarchar(128), v.value) END),
    @ConfiguredWarehouseDatabase = MAX(CASE WHEN v.name = N'WarehouseDatabase' THEN CONVERT(nvarchar(128), v.value) END)
FROM [SSISDB].[catalog].[environment_variables] AS v
JOIN [SSISDB].[catalog].[environments] AS e ON e.environment_id = v.environment_id
JOIN [SSISDB].[catalog].[folders] AS f ON f.folder_id = e.folder_id
WHERE f.name = @Folder AND e.name = @Environment
  AND v.name IN (N'SourceDatabase', N'WarehouseDatabase');

IF ISNULL(@ConfiguredSourceDatabase, N'') <> @ExpectedSourceDatabase
   OR ISNULL(@ConfiguredWarehouseDatabase, N'') <> @ExpectedWarehouseDatabase
    THROW 51000, 'The SSIS environment database values do not match the selected production or test job.', 1;

IF (SELECT COUNT(DISTINCT subsystem)
    FROM [msdb].[dbo].[syssubsystems]
    WHERE subsystem IN (N'SSIS', N'ANALYSISCOMMAND')) <> 2
    THROW 51000, 'SQL Server Agent must provide the SSIS and ANALYSISCOMMAND subsystems.', 1;

SELECT @JobId = job_id, @ExistingDescription = description
FROM [msdb].[dbo].[sysjobs]
WHERE name = @JobName;

IF @JobId IS NOT NULL AND COALESCE(@ExistingDescription, N'') <> @JobMarker
    THROW 51000, 'A job with this name exists but is not marked as owned by the Northwind practice.', 1;

IF @JobId IS NOT NULL
BEGIN
    IF EXISTS (
        SELECT 1 FROM [msdb].[dbo].[sysjobsteps]
        WHERE job_id = @JobId AND step_id > 2
    )
        THROW 51000, 'The owned job contains additional steps; review it before updating.', 1;

    SELECT @LinkedScheduleCount = COUNT(*)
    FROM [msdb].[dbo].[sysjobschedules]
    WHERE job_id = @JobId;

    IF @LinkedScheduleCount > 1
        THROW 51000, 'The owned job has more than one schedule attached; review it before updating.', 1;

    IF @LinkedScheduleCount = 1
       AND NOT EXISTS (
           SELECT 1
           FROM [msdb].[dbo].[sysjobschedules] AS js
           JOIN [msdb].[dbo].[sysschedules] AS s ON s.schedule_id = js.schedule_id
           WHERE js.job_id = @JobId AND s.name = @ScheduleName
       )
        THROW 51000, 'The owned job is attached to a different schedule; review it before updating.', 1;
END;

SELECT @ScheduleCount = COUNT(*), @ScheduleId = MAX(schedule_id)
FROM [msdb].[dbo].[sysschedules]
WHERE name = @ScheduleName;

IF @ScheduleCount > 1
    THROW 51000, 'Duplicate schedules use the expected Northwind schedule name.', 1;

IF @ScheduleCount = 1
BEGIN
    IF @JobId IS NULL OR @LinkedScheduleCount <> 1
       OR NOT EXISTS (
           SELECT 1
           FROM [msdb].[dbo].[sysjobschedules] AS js
           WHERE js.job_id = @JobId AND js.schedule_id = @ScheduleId
       )
       OR NOT EXISTS (
           SELECT 1
           FROM [msdb].[dbo].[sysschedules] AS s
           WHERE s.schedule_id = @ScheduleId
             AND s.owner_sid = SUSER_SID(@JobOwner)
       )
        THROW 51000, 'The expected schedule is not owned and linked solely by this practice job.', 1;

    SELECT @ForeignScheduleLinks = COUNT(*)
    FROM [msdb].[dbo].[sysjobschedules]
    WHERE schedule_id = @ScheduleId AND job_id <> @JobId;

    IF @ForeignScheduleLinks > 0
        THROW 51000, 'The expected schedule is shared with another job.', 1;
END;

/* Prepare the native Agent commands. The synchronized SSIS step must finish
   successfully before Agent advances to the TMSL full refresh step. */
SET @SsisCommand =
      N'/ISSERVER "\"\SSISDB\' + @Folder + N'\' + @Project + N'\' + @Package
    + N'\"" /SERVER ' + @SqlServer
    + N' /ENVREFERENCE ' + CONVERT(nvarchar(20), @EnvironmentReferenceId)
    + N' /Par "\"$ServerOption::LOGGING_LEVEL(Int16)\"";1'
    + N' /Par "\"$ServerOption::SYNCHRONIZED(Boolean)\"";True'
    + N' /CALLERINFO SQLAGENT /REPORTING E';

SET @AnalysisCommand =
    N'{"refresh":{"type":"full","objects":[{"database":"'
    + @ModelDatabase + N'"}]}}';

/* Create or update only the job with this exact name and ownership marker. */
IF @JobId IS NULL
BEGIN
    EXEC [msdb].[dbo].[sp_add_job]
        @job_name = @JobName,
        @enabled = 0,
        @description = @JobMarker,
        @start_step_id = 1,
        @owner_login_name = @JobOwner,
        @job_id = @JobId OUTPUT;

    EXEC [msdb].[dbo].[sp_add_jobserver]
        @job_id = @JobId,
        @server_name = N'(LOCAL)';
END
ELSE
BEGIN
    EXEC [msdb].[dbo].[sp_update_job]
        @job_id = @JobId,
        @enabled = 0,
        @description = @JobMarker;
END;

SELECT @StepCount = COUNT(*)
FROM [msdb].[dbo].[sysjobsteps]
WHERE job_id = @JobId AND step_id = 1;

IF @StepCount = 0
    EXEC [msdb].[dbo].[sp_add_jobstep]
        @job_id = @JobId,
        @step_id = 1,
        @step_name = N'Load Northwind ETL',
        @subsystem = N'SSIS',
        @command = @SsisCommand,
        @database_name = N'SSISDB',
        @on_success_action = 3,
        @on_fail_action = 2,
        @retry_attempts = 0;
ELSE
    EXEC [msdb].[dbo].[sp_update_jobstep]
        @job_id = @JobId,
        @step_id = 1,
        @step_name = N'Load Northwind ETL',
        @subsystem = N'SSIS',
        @command = @SsisCommand,
        @database_name = N'SSISDB',
        @on_success_action = 3,
        @on_fail_action = 2,
        @retry_attempts = 0;

SELECT @StepCount = COUNT(*)
FROM [msdb].[dbo].[sysjobsteps]
WHERE job_id = @JobId AND step_id = 2;

IF @StepCount = 0
    EXEC [msdb].[dbo].[sp_add_jobstep]
        @job_id = @JobId,
        @step_id = 2,
        @step_name = N'Process Northwind OLAP',
        @subsystem = N'ANALYSISCOMMAND',
        @server = @AnalysisServer,
        @command = @AnalysisCommand,
        @on_success_action = 1,
        @on_fail_action = 2,
        @retry_attempts = 0;
ELSE
    EXEC [msdb].[dbo].[sp_update_jobstep]
        @job_id = @JobId,
        @step_id = 2,
        @step_name = N'Process Northwind OLAP',
        @subsystem = N'ANALYSISCOMMAND',
        @server = @AnalysisServer,
        @command = @AnalysisCommand,
        @on_success_action = 1,
        @on_fail_action = 2,
        @retry_attempts = 0;

IF @ScheduleCount = 0
BEGIN
    EXEC [msdb].[dbo].[sp_add_schedule]
        @schedule_name = @ScheduleName,
        @enabled = @EnableSchedule,
        @freq_type = 4,
        @freq_interval = @EveryNDays,
        @freq_recurrence_factor = 1,
        @active_start_date = @StartDate,
        @active_start_time = @ActiveStartTime,
        @owner_login_name = @JobOwner,
        @schedule_id = @ScheduleId OUTPUT;

    EXEC [msdb].[dbo].[sp_attach_schedule]
        @job_id = @JobId,
        @schedule_id = @ScheduleId;
END
ELSE
BEGIN
    EXEC [msdb].[dbo].[sp_update_schedule]
        @schedule_id = @ScheduleId,
        @enabled = @EnableSchedule,
        @freq_type = 4,
        @freq_interval = @EveryNDays,
        @freq_recurrence_factor = 1,
        @active_start_date = @StartDate,
        @active_start_time = @ActiveStartTime;
END;

EXEC [msdb].[dbo].[sp_update_job]
    @job_id = @JobId,
    @enabled = @EnableJob;

SELECT @JobId AS job_id,
       @JobName AS job_name,
       @ScheduleName AS schedule_name,
       @EnableJob AS job_enabled,
       @EnableSchedule AS schedule_enabled,
       @EnvironmentReferenceId AS environment_reference_id,
       @JobMarker AS ownership_marker;
