[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$SourceServer = 'localhost',
    [string]$WarehouseServer = 'localhost',
    [ValidateSet('NorthWind', 'Northwind_Test')]
    [string]$SourceDatabase = 'NorthWind',
    [ValidateSet('Northwind_DW', 'Northwind_DW_Test')]
    [string]$WarehouseDatabase = 'Northwind_DW',
    [string]$Folder = 'Northwind',
    [ValidateSet('Northwind', 'Northwind_Test')]
    [string]$Environment = 'Northwind',
    [string]$LogDirectory = 'C:\ProgramData\NorthwindBI\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$folderMarker = 'Northwind practice folder managed by Publish-NorthwindETL.ps1.'
$projectMarker = 'Northwind practice project managed by Publish-NorthwindETL.ps1.'
$environmentMarker = 'Northwind practice environment managed by Publish-NorthwindETL.ps1.'
$variableMarker = 'Northwind practice environment variable managed by Publish-NorthwindETL.ps1.'
$project = 'Northwind.ETL'
$package = 'CargarNorthwind.dtsx'

function New-Connection([string]$Database, [string]$TargetServer = $Server) {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $TargetServer
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    return [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Invoke-Sql([string]$Database, [string]$Text, [hashtable]$Parameters = @{}, [switch]$Scalar, [string]$TargetServer = $Server) {
    $command = $null
    $connection = New-Connection $Database $TargetServer
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 180
        $command.CommandText = $Text
        foreach ($name in $Parameters.Keys) { [void]$command.Parameters.AddWithValue($name, $Parameters[$name]) }
        if ($Scalar) {
            return $command.ExecuteScalar()
        }
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

function Assert-TestDatabase([string]$Database, [string]$ExpectedMarker, [string]$TargetServer) {
    $query = @'
DECLARE @targetDatabase sysname = @Database;
IF DB_ID(@targetDatabase) IS NULL THROW 51301, 'No existe la base de datos de práctica requerida.', 1;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @targetDatabase AND (is_trustworthy_on = 1 OR is_db_chaining_on = 1))
    THROW 51302, 'La base de datos marcada no conserva su aislamiento.', 1;
DECLARE @marker nvarchar(128);
DECLARE @sql nvarchar(max) = N'SELECT @marker = CONVERT(nvarchar(128), value) FROM '
    + QUOTENAME(@targetDatabase) + N'.sys.extended_properties WHERE class = 0 AND name = N''NorthwindPracticeTestDatabase'';';
EXEC sys.sp_executesql @sql, N'@marker nvarchar(128) OUTPUT', @marker OUTPUT;
IF @marker IS NULL OR @marker <> @ExpectedMarker
    THROW 51303, 'La base no es la copia aislada esperada; no se publicó el proyecto.', 1;
'@
    [void](Invoke-Sql 'master' $query @{ '@Database' = $Database; '@ExpectedMarker' = $ExpectedMarker } -TargetServer $TargetServer)
}

function Assert-ProductionDatabase([string]$Database, [string]$ExpectedName, [string]$TargetServer) {
    if ($Database -cne $ExpectedName) {
        throw "La ruta de producción solo admite '$ExpectedName'; se recibió '$Database'."
    }
    $query = @'
DECLARE @targetDatabase sysname = @Database;
IF DB_ID(@targetDatabase) IS NULL THROW 51304, 'No existe la base real configurada para la práctica.', 1;
DECLARE @marker nvarchar(128);
DECLARE @sql nvarchar(max) = N'SELECT @marker = CONVERT(nvarchar(128), value) FROM '
    + QUOTENAME(@targetDatabase) + N'.sys.extended_properties WHERE class = 0 AND name = N''NorthwindPracticeTestDatabase'';';
EXEC sys.sp_executesql @sql, N'@marker nvarchar(128) OUTPUT', @marker OUTPUT;
IF @marker IS NOT NULL AND @marker <> @ExpectedMarker
    THROW 51305, 'La base real tiene una marca de copia incompatible; no se publicó el proyecto.', 1;
'@
    [void](Invoke-Sql 'master' $query @{ '@Database' = $Database; '@ExpectedMarker' = $ExpectedName } -TargetServer $TargetServer)
}

function Ensure-Folder {
    $state = Invoke-Sql 'SSISDB' @'
SELECT folder_id, description FROM catalog.folders WHERE name = @Folder;
'@ @{ '@Folder' = $Folder }
    if ($state.Rows.Count -eq 0) {
        [void](Invoke-Sql 'SSISDB' @'
DECLARE @folderId bigint;
EXEC catalog.create_folder @folder_name = @Folder, @folder_id = @folderId OUTPUT;
EXEC catalog.set_folder_description @folder_name = @Folder, @folder_description = @Description;
'@ @{ '@Folder' = $Folder; '@Description' = $folderMarker })
        return
    }
    if (([string]$state.Rows[0].description).Trim() -cne $folderMarker) {
        throw "La carpeta SSISDB '$Folder' ya existe y no tiene el marcador de propiedad de esta práctica."
    }
}

function Ensure-Environment {
    $state = Invoke-Sql 'SSISDB' @'
SELECT e.environment_id, e.description
FROM catalog.environments AS e
JOIN catalog.folders AS f ON f.folder_id = e.folder_id
WHERE f.name = @Folder AND e.name = @Environment;
'@ @{ '@Folder' = $Folder; '@Environment' = $Environment }
    if ($state.Rows.Count -eq 0) {
        [void](Invoke-Sql 'SSISDB' @'
EXEC catalog.create_environment
    @folder_name = @Folder,
    @environment_name = @Environment,
    @environment_description = @Description;
'@ @{ '@Folder' = $Folder; '@Environment' = $Environment; '@Description' = $environmentMarker })
        return
    }
    if (([string]$state.Rows[0].description).Trim() -cne $environmentMarker) {
        throw "El entorno SSISDB '$Folder/$Environment' ya existe y no pertenece a esta práctica."
    }
}

function Set-EnvironmentVariable([string]$Name, [string]$Value) {
    $state = Invoke-Sql 'SSISDB' @'
SELECT v.type AS data_type, v.sensitive, v.description
FROM catalog.environment_variables AS v
JOIN catalog.environments AS e ON e.environment_id = v.environment_id
JOIN catalog.folders AS f ON f.folder_id = e.folder_id
WHERE f.name = @Folder AND e.name = @Environment AND v.name = @Name;
'@ @{ '@Folder' = $Folder; '@Environment' = $Environment; '@Name' = $Name }
    if ($state.Rows.Count -eq 0) {
        [void](Invoke-Sql 'SSISDB' @'
EXEC catalog.create_environment_variable
    @folder_name = @Folder,
    @environment_name = @Environment,
    @variable_name = @Name,
    @data_type = N'String',
    @sensitive = 0,
    @value = @Value,
    @description = @Description;
'@ @{ '@Folder' = $Folder; '@Environment' = $Environment; '@Name' = $Name; '@Value' = $Value; '@Description' = $variableMarker })
        return
    }
    $row = $state.Rows[0]
    if ([string]$row.data_type -cne 'String' -or [bool]$row.sensitive -or ([string]$row.description).Trim() -cne $variableMarker) {
        throw "La variable '$Name' existe con propiedades ajenas a esta publicación; no se cambió."
    }
    [void](Invoke-Sql 'SSISDB' @'
EXEC catalog.set_environment_variable_value
    @folder_name = @Folder,
    @environment_name = @Environment,
    @variable_name = @Name,
    @value = @Value;
'@ @{ '@Folder' = $Folder; '@Environment' = $Environment; '@Name' = $Name; '@Value' = $Value })
}

if ($Folder -notmatch '^[A-Za-z0-9_. -]{1,128}$' -or $Environment -notmatch '^[A-Za-z0-9_. -]{1,128}$') {
    throw 'Folder y Environment deben ser nombres SSIS de hasta 128 caracteres.'
}
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { throw 'LogDirectory no puede estar vacío.' }

$isProduction = $SourceDatabase -ceq 'NorthWind' -and $WarehouseDatabase -ceq 'Northwind_DW' -and $Environment -ceq 'Northwind'
$isTest = $SourceDatabase -ceq 'Northwind_Test' -and $WarehouseDatabase -ceq 'Northwind_DW_Test' -and $Environment -ceq 'Northwind_Test'
if (-not ($isProduction -or $isTest)) {
    throw 'Use the matching production pair NorthWind/Northwind_DW/Northwind or test pair Northwind_Test/Northwind_DW_Test/Northwind_Test.'
}
if ($isProduction) {
    Assert-ProductionDatabase $SourceDatabase 'NorthWind' $SourceServer
    Assert-ProductionDatabase $WarehouseDatabase 'Northwind_DW' $WarehouseServer
} else {
    Assert-TestDatabase $SourceDatabase 'NorthWind' $SourceServer
    Assert-TestDatabase $WarehouseDatabase 'Northwind_DW' $WarehouseServer
}

$catalogExists = Invoke-Sql 'master' "SELECT CONVERT(bit, CASE WHEN DB_ID(N'SSISDB') IS NULL THEN 0 ELSE 1 END);" @{} -Scalar
if (-not [bool]$catalogExists) {
    throw "SSISDB no existe en '$Server'. Ejecute Initialize-NorthwindSSISDB.ps1 -CreateCatalog con su contraseña SecureString."
}

$repository = Split-Path $PSScriptRoot -Parent
$projectDirectory = Join-Path $repository 'Northwind.ETL'
$buildScript = Join-Path $PSScriptRoot 'Build-NorthwindETL.ps1'
& $buildScript -ProjectDirectory $projectDirectory
$ispac = Join-Path $projectDirectory 'bin/Development/Northwind.ETL.ispac'
if (-not (Test-Path -LiteralPath $ispac)) { throw "El build no generó el artefacto esperado '$ispac'." }
$projectBytes = [IO.File]::ReadAllBytes($ispac)

$existingProject = Invoke-Sql 'SSISDB' @'
SELECT p.description
FROM catalog.projects AS p
JOIN catalog.folders AS f ON f.folder_id = p.folder_id
WHERE f.name = @Folder AND p.name = @Project;
'@ @{ '@Folder' = $Folder; '@Project' = $project }
if ($existingProject.Rows.Count -gt 0 -and ([string]$existingProject.Rows[0].description).Trim() -cne $projectMarker) {
    throw "El proyecto SSISDB '$Folder/$project' ya existe y no pertenece a esta práctica."
}

Ensure-Folder
Ensure-Environment

foreach ($entry in @(
    @{ Name = 'SourceServer'; Value = $SourceServer },
    @{ Name = 'SourceDatabase'; Value = $SourceDatabase },
    @{ Name = 'WarehouseServer'; Value = $WarehouseServer },
    @{ Name = 'WarehouseDatabase'; Value = $WarehouseDatabase },
    @{ Name = 'LogDirectory'; Value = $LogDirectory }
)) {
    Set-EnvironmentVariable $entry.Name $entry.Value
}

[void](Invoke-Sql 'SSISDB' @'
DECLARE @operationId bigint;
EXEC catalog.deploy_project
    @folder_name = @Folder,
    @project_name = @Project,
    @project_stream = @ProjectStream,
    @operation_id = @operationId OUTPUT;
SELECT @operationId;
'@ @{ '@Folder' = $Folder; '@Project' = $project; '@ProjectStream' = $projectBytes } -Scalar)

$projectInfo = Invoke-Sql 'SSISDB' @'
SELECT p.project_id, p.description
FROM catalog.projects AS p
JOIN catalog.folders AS f ON f.folder_id = p.folder_id
WHERE f.name = @Folder AND p.name = @Project;
'@ @{ '@Folder' = $Folder; '@Project' = $project }
if ($projectInfo.Rows.Count -ne 1 -or ([string]$projectInfo.Rows[0].description).Trim() -cne $projectMarker) {
    throw 'El proyecto desplegado no conserva el marcador de propiedad esperado.'
}

$packageExists = Invoke-Sql 'SSISDB' @'
SELECT COUNT_BIG(*)
FROM catalog.packages AS k
JOIN catalog.projects AS p ON p.project_id = k.project_id
JOIN catalog.folders AS f ON f.folder_id = p.folder_id
WHERE f.name = @Folder AND p.name = @Project AND k.name = @Package;
'@ @{ '@Folder' = $Folder; '@Project' = $project; '@Package' = $package } -Scalar
if ([long]$packageExists -ne 1) { throw "El proyecto desplegado no contiene el paquete '$package'." }

$parameters = Invoke-Sql 'SSISDB' @'
SELECT parameter_name
FROM catalog.object_parameters
WHERE project_id = @ProjectId AND object_type = 20;
'@ @{ '@ProjectId' = [long]$projectInfo.Rows[0].project_id }
$parameterNames = @($parameters.Rows | ForEach-Object { [string]$_.parameter_name })
foreach ($name in 'SourceServer', 'SourceDatabase', 'WarehouseServer', 'WarehouseDatabase', 'LogDirectory') {
    if ($parameterNames -cnotcontains $name) { throw "El proyecto no contiene el parámetro requerido '$name'." }
}

$reference = Invoke-Sql 'SSISDB' @'
SELECT r.reference_id, r.reference_type, r.environment_folder_name, r.environment_name
FROM catalog.environment_references AS r
JOIN catalog.projects AS p ON p.project_id = r.project_id
JOIN catalog.folders AS pf ON pf.folder_id = p.folder_id
WHERE pf.name = @Folder AND p.name = @Project
  AND (r.environment_folder_name = @Folder OR r.environment_folder_name IS NULL)
  AND r.environment_name = @Environment;
'@ @{ '@Folder' = $Folder; '@Project' = $project; '@Environment' = $Environment }
if ($reference.Rows.Count -eq 0) {
    [void](Invoke-Sql 'SSISDB' @'
DECLARE @referenceId bigint;
EXEC catalog.create_environment_reference
    @folder_name = @Folder,
    @project_name = @Project,
    @environment_name = @Environment,
    @reference_type = 'R',
    @reference_id = @referenceId OUTPUT;
SELECT @referenceId;
'@ @{ '@Folder' = $Folder; '@Project' = $project; '@Environment' = $Environment })
    $reference = Invoke-Sql 'SSISDB' @'
SELECT r.reference_id, r.reference_type, r.environment_folder_name, r.environment_name
FROM catalog.environment_references AS r
JOIN catalog.projects AS p ON p.project_id = r.project_id
JOIN catalog.folders AS pf ON pf.folder_id = p.folder_id
WHERE pf.name = @Folder AND p.name = @Project
  AND (r.environment_folder_name = @Folder OR r.environment_folder_name IS NULL)
  AND r.environment_name = @Environment;
'@ @{ '@Folder' = $Folder; '@Project' = $project; '@Environment' = $Environment }
}
if ($reference.Rows.Count -ne 1 -or [string]$reference.Rows[0].reference_type -cne 'R') {
    throw 'El proyecto tiene una referencia de entorno inesperada; no se cambió.'
}

foreach ($name in 'SourceServer', 'SourceDatabase', 'WarehouseServer', 'WarehouseDatabase', 'LogDirectory') {
    [void](Invoke-Sql 'SSISDB' @'
EXEC catalog.set_object_parameter_value
    @object_type = 20,
    @folder_name = @Folder,
    @project_name = @Project,
    @parameter_name = @Name,
    @parameter_value = @Name,
    @value_type = 'R';
'@ @{ '@Folder' = $Folder; '@Project' = $project; '@Name' = $name })
}

Write-Output "Proyecto SSIS publicado en SSISDB/$Folder/$project; entorno $Environment; referencia relativa $($reference.Rows[0].reference_id)."
