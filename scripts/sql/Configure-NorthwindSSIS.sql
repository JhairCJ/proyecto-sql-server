/*
    Configure the Northwind SSISDB folder, environment, variables, and
    project-parameter bindings.

    Run this in SSMS after SSISDB exists. It can be run before native
    Visual Studio publication to prepare the folder/environment, then again
    after publishing Northwind.ETL to create the project reference and bindings.
    Edit only the configuration values below. This script never creates or
    publishes a project and never stores credentials.
*/
USE [SSISDB];
SET NOCOUNT ON;

DECLARE @Folder sysname = N'Northwind';
DECLARE @Environment sysname = N'Northwind_Test';
DECLARE @Project sysname = N'Northwind.ETL';
DECLARE @SourceServer nvarchar(128) = N'localhost';
DECLARE @SourceDatabase sysname = N'Northwind_Test';
DECLARE @WarehouseServer nvarchar(128) = N'localhost';
DECLARE @WarehouseDatabase sysname = N'Northwind_DW_Test';
DECLARE @LogDirectory nvarchar(4000) = N'C:\ProgramData\NorthwindBI\Logs';

DECLARE @FolderMarker nvarchar(256) = N'Northwind practice folder managed by Publish-NorthwindETL.ps1.';
DECLARE @ProjectMarker nvarchar(256) = N'Northwind practice project managed by Publish-NorthwindETL.ps1.';
DECLARE @EnvironmentMarker nvarchar(256) = N'Northwind practice environment managed by Publish-NorthwindETL.ps1.';
DECLARE @VariableMarker nvarchar(256) = N'Northwind practice environment variable managed by Publish-NorthwindETL.ps1.';
DECLARE @ProjectId bigint;
DECLARE @FolderId bigint;
DECLARE @EnvironmentId bigint;
DECLARE @FolderCount int;
DECLARE @EnvironmentCount int;
DECLARE @ProjectCount int;
DECLARE @ProjectParameterCount int;
DECLARE @ReferenceCount int;
DECLARE @ReferenceId bigint;
DECLARE @ExistingDescription nvarchar(4000);
DECLARE @VariableName sysname;
DECLARE @VariableValue nvarchar(4000);
DECLARE @VariableCount int;
DECLARE @VariableType nvarchar(128);
DECLARE @VariableSensitive bit;
DECLARE @VariableDescription nvarchar(4000);
DECLARE @ParameterCount int;

IF @SourceDatabase <> N'Northwind_Test'
   OR @WarehouseDatabase <> N'Northwind_DW_Test'
    THROW 51000, 'Use only the marked Northwind_Test and Northwind_DW_Test copies.', 1;
IF DB_ID(N'Northwind_Test') IS NULL OR DB_ID(N'Northwind_DW_Test') IS NULL
    THROW 51000, 'The marked Northwind test databases must exist before configuring SSISDB.', 1;
IF NOT EXISTS (
    SELECT 1 FROM [Northwind_Test].sys.extended_properties
    WHERE class = 0 AND name = N'NorthwindPracticeTestDatabase'
      AND CONVERT(nvarchar(128), value) = N'NorthWind'
)
    THROW 51000, 'Northwind_Test is not the marked source copy.', 1;
IF NOT EXISTS (
    SELECT 1 FROM [Northwind_DW_Test].sys.extended_properties
    WHERE class = 0 AND name = N'NorthwindPracticeTestDatabase'
      AND CONVERT(nvarchar(128), value) = N'Northwind_DW'
)
    THROW 51000, 'Northwind_DW_Test is not the marked warehouse copy.', 1;

IF EXISTS (SELECT 1 FROM sys.databases
    WHERE name IN (N'Northwind_Test',N'Northwind_DW_Test')
      AND (is_trustworthy_on=1 OR is_db_chaining_on=1))
    THROW 51000, 'The Northwind copies must retain database isolation.', 1;

/* Preflight existing objects before making any changes. */
SELECT @FolderCount = COUNT(*),
       @FolderId = MAX(folder_id),
       @ExistingDescription = MAX(description)
FROM catalog.folders
WHERE name = @Folder;

IF @FolderCount > 1
    THROW 51000, 'Duplicate SSIS folders use the configured name.', 1;
IF @FolderCount = 1
   AND COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM @ExistingDescription), N'') <> @FolderMarker
    THROW 51000, 'The configured SSIS folder exists but is not owned by this practice.', 1;

SELECT @EnvironmentCount = COUNT(*),
       @EnvironmentId = MAX(e.environment_id),
       @ExistingDescription = MAX(e.description)
FROM catalog.environments AS e
JOIN catalog.folders AS f ON f.folder_id = e.folder_id
WHERE f.name = @Folder AND e.name = @Environment;

IF @EnvironmentCount > 1
    THROW 51000, 'Duplicate SSIS environments use the configured folder and name.', 1;
IF @EnvironmentCount = 1
   AND COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM @ExistingDescription), N'') <> @EnvironmentMarker
    THROW 51000, 'The configured SSIS environment exists but is not owned by this practice.', 1;

SELECT @ProjectCount = COUNT(*),
       @ProjectId = MAX(p.project_id),
       @ExistingDescription = MAX(p.description)
FROM catalog.projects AS p
JOIN catalog.folders AS f ON f.folder_id = p.folder_id
WHERE f.name = @Folder AND p.name = @Project;

IF @ProjectCount > 1
    THROW 51000, 'Duplicate Northwind.ETL projects were found in the configured folder.', 1;
IF @ProjectCount = 1
   AND COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM @ExistingDescription), N'') <> @ProjectMarker
    THROW 51000, 'The configured SSIS project exists but its description is not the practice marker.', 1;

DECLARE @EnvironmentVariables TABLE (
    name sysname NOT NULL PRIMARY KEY,
    value nvarchar(4000) NOT NULL
);
INSERT INTO @EnvironmentVariables (name, value)
VALUES
    (N'SourceServer', @SourceServer),
    (N'SourceDatabase', @SourceDatabase),
    (N'WarehouseServer', @WarehouseServer),
    (N'WarehouseDatabase', @WarehouseDatabase),
    (N'LogDirectory', @LogDirectory);

IF @EnvironmentCount = 1
   AND EXISTS (
       SELECT 1
       FROM @EnvironmentVariables AS expected
       JOIN catalog.environment_variables AS actual
         ON actual.environment_id = @EnvironmentId
        AND actual.name = expected.name
       WHERE actual.[type] <> N'String'
          OR actual.sensitive <> 0
          OR COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM actual.description), N'') <> @VariableMarker
   )
    THROW 51000, 'A configured environment variable exists with properties not owned by this practice.', 1;

IF @ProjectCount = 1
BEGIN
    SELECT @ProjectParameterCount = COUNT(DISTINCT parameter_name)
    FROM catalog.object_parameters
    WHERE project_id = @ProjectId
      AND object_type = 20
      AND parameter_name IN (
          N'SourceServer', N'SourceDatabase', N'WarehouseServer',
          N'WarehouseDatabase', N'LogDirectory'
      );

    IF @ProjectParameterCount <> 5
        THROW 51000, 'The published project does not contain all five required project parameters.', 1;

    SELECT @ReferenceCount = COUNT(*),
           @ReferenceId = MAX(reference_id)
    FROM catalog.environment_references
    WHERE project_id = @ProjectId
      AND environment_name = @Environment
      AND (environment_folder_name = @Folder OR environment_folder_name IS NULL);

    IF @ReferenceCount > 1
        THROW 51000, 'The project has duplicate references to the configured environment.', 1;
    IF @ReferenceCount = 1
       AND NOT EXISTS (
           SELECT 1 FROM catalog.environment_references
           WHERE project_id = @ProjectId
             AND reference_id = @ReferenceId
             AND reference_type = 'R'
       )
        THROW 51000, 'The existing environment reference is not a relative reference.', 1;
END;

/* Create only missing owned folder/environment objects. */
IF @FolderCount = 0
BEGIN
    EXEC catalog.create_folder
        @folder_name = @Folder,
        @folder_id = @FolderId OUTPUT;
    EXEC catalog.set_folder_description
        @folder_name = @Folder,
        @folder_description = @FolderMarker;
END;

IF @EnvironmentCount = 0
BEGIN
    EXEC catalog.create_environment
        @folder_name = @Folder,
        @environment_name = @Environment,
        @environment_description = @EnvironmentMarker;
    SELECT @EnvironmentId = e.environment_id
    FROM catalog.environments AS e
    JOIN catalog.folders AS f ON f.folder_id = e.folder_id
    WHERE f.name = @Folder AND e.name = @Environment;
END;

DECLARE environment_variable_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, value FROM @EnvironmentVariables ORDER BY name;
OPEN environment_variable_cursor;
FETCH NEXT FROM environment_variable_cursor INTO @VariableName, @VariableValue;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @VariableCount = COUNT(*),
           @VariableType = MAX(actual.[type]),
           @VariableSensitive = MAX(CONVERT(tinyint, actual.sensitive)),
           @VariableDescription = MAX(actual.description)
    FROM catalog.environment_variables AS actual
    WHERE actual.environment_id = @EnvironmentId
      AND actual.name = @VariableName;

    IF @VariableCount = 0
    BEGIN
        EXEC catalog.create_environment_variable
            @folder_name = @Folder,
            @environment_name = @Environment,
            @variable_name = @VariableName,
            @data_type = N'String',
            @sensitive = 0,
            @value = @VariableValue,
            @description = @VariableMarker;
    END
    ELSE
    BEGIN
        IF @VariableCount <> 1
           OR @VariableType <> N'String'
           OR @VariableSensitive <> 0
           OR COALESCE(TRIM(N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM @VariableDescription), N'') <> @VariableMarker
        BEGIN
            CLOSE environment_variable_cursor;
            DEALLOCATE environment_variable_cursor;
            THROW 51000, 'An environment variable changed ownership or type; no value was overwritten.', 1;
        END;

        EXEC catalog.set_environment_variable_value
            @folder_name = @Folder,
            @environment_name = @Environment,
            @variable_name = @VariableName,
            @value = @VariableValue;
    END;

    FETCH NEXT FROM environment_variable_cursor INTO @VariableName, @VariableValue;
END;
CLOSE environment_variable_cursor;
DEALLOCATE environment_variable_cursor;

IF @ProjectCount = 0
BEGIN
    SELECT @Folder AS folder_name,
           @Environment AS environment_name,
           N'Environment ready. Publish Northwind.ETL in Visual Studio, then rerun this script.' AS next_step;
    RETURN;
END;

IF @ReferenceCount = 0
BEGIN
    EXEC catalog.create_environment_reference
        @folder_name = @Folder,
        @project_name = @Project,
        @environment_name = @Environment,
        @reference_type = 'R',
        @reference_id = @ReferenceId OUTPUT;
END;

DECLARE project_parameter_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM @EnvironmentVariables ORDER BY name;
OPEN project_parameter_cursor;
FETCH NEXT FROM project_parameter_cursor INTO @VariableName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @ParameterCount = COUNT(*)
    FROM catalog.object_parameters
    WHERE project_id = @ProjectId
      AND object_type = 20
      AND parameter_name = @VariableName;

    IF @ParameterCount <> 1
    BEGIN
        CLOSE project_parameter_cursor;
        DEALLOCATE project_parameter_cursor;
        THROW 51000, 'A required project parameter is missing or ambiguous; bindings were not completed.', 1;
    END;

    EXEC catalog.set_object_parameter_value
        @object_type = 20,
        @folder_name = @Folder,
        @project_name = @Project,
        @parameter_name = @VariableName,
        @parameter_value = @VariableName,
        @value_type = 'R';

    FETCH NEXT FROM project_parameter_cursor INTO @VariableName;
END;
CLOSE project_parameter_cursor;
DEALLOCATE project_parameter_cursor;

SELECT @Folder AS folder_name,
       @Project AS project_name,
       @Environment AS environment_name,
       @ReferenceId AS environment_reference_id,
       N'SSIS project parameters are mapped to the environment.' AS result;
