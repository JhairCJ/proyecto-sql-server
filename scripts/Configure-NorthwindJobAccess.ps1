[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$AnalysisServer = 'localhost',
    [string]$WarehouseServer = 'localhost',
    [ValidateSet('Northwind_DW_Test')]
    [string]$WarehouseDatabase = 'Northwind_DW_Test',
    [ValidateSet('NorthwindOLAP_Test')]
    [string]$ModelDatabase = 'NorthwindOLAP_Test',
    [string]$LogDirectory = 'C:\ProgramData\NorthwindBI\Logs',
    [switch]$SkipCatalogCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$roleName = 'NorthwindBIJobProcessor'
$roleMarker = 'Northwind practice processing role managed by Configure-NorthwindJobAccess.ps1.'

function New-SqlConnection([string]$Database, [string]$DataSource) {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $DataSource
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    return [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Invoke-Sql([string]$Database, [string]$DataSource, [string]$Text, [hashtable]$Parameters = @{}) {
    $connection = New-SqlConnection $Database $DataSource
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Text
        $command.CommandTimeout = 120
        foreach ($name in $Parameters.Keys) { [void]$command.Parameters.AddWithValue($name, $Parameters[$name]) }
        [void]$command.ExecuteNonQuery()
    }
    finally {
        if ($command) { $command.Dispose() }
        $connection.Dispose()
    }
}

$agentService = Get-CimInstance Win32_Service -Filter "Name='SQLSERVERAGENT'"
if (-not $agentService -or $agentService.State -ne 'Running') {
    throw 'Inicie SQL Server Agent antes de configurar los permisos del job.'
}
$agentPrincipal = [string]$agentService.StartName
if ([string]::IsNullOrWhiteSpace($agentPrincipal)) { throw 'No se pudo determinar la cuenta del servicio SQL Server Agent.' }

$accessCheck = New-SqlConnection 'master' $Server
try {
    $accessCheck.Open()
    $command = $accessCheck.CreateCommand()
    $command.CommandText = @'
SELECT CONVERT(bit, CASE WHEN SUSER_ID(@Principal) IS NOT NULL THEN 1 ELSE 0 END) AS HasLogin,
       ISNULL(IS_SRVROLEMEMBER(N'sysadmin', @Principal), 0) AS IsSysadmin;
'@
    [void]$command.Parameters.AddWithValue('@Principal', $agentPrincipal)
    $reader = $command.ExecuteReader()
    try {
        if (-not $reader.Read() -or -not [bool]$reader['HasLogin']) {
            throw "La cuenta '$agentPrincipal' no tiene login en '$Server'; no se otorgaron permisos automáticamente."
        }
        if (-not [bool]$reader['IsSysadmin']) {
            throw "El job se ejecuta con '$agentPrincipal', que no tiene los permisos de SQL Server requeridos por SSISDB. No se agregó sysadmin."
        }
    }
    finally { $reader.Dispose(); $command.Dispose() }
}
finally { $accessCheck.Dispose() }

$databaseCheck = @'
DECLARE @targetDatabase sysname = @Database;
IF DB_ID(@targetDatabase) IS NULL THROW 51311, 'No existe el almacén de prueba.', 1;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @targetDatabase AND (is_trustworthy_on = 1 OR is_db_chaining_on = 1))
    THROW 51312, 'El almacén de prueba no conserva su aislamiento.', 1;
DECLARE @marker nvarchar(128);
DECLARE @sql nvarchar(max) = N'SELECT @marker = CONVERT(nvarchar(128), value) FROM '
    + QUOTENAME(@targetDatabase) + N'.sys.extended_properties WHERE class = 0 AND name = N''NorthwindPracticeTestDatabase'';';
EXEC sys.sp_executesql @sql, N'@marker nvarchar(128) OUTPUT', @marker OUTPUT;
IF @marker IS NULL OR @marker <> N'Northwind_DW'
    THROW 51313, 'El almacén no es la copia marcada de práctica.', 1;
'@
Invoke-Sql 'master' $WarehouseServer $databaseCheck @{ '@Database' = $WarehouseDatabase }

if (-not $SkipCatalogCheck) {
    $ssisCatalogCheck = New-SqlConnection 'master' $Server
    $command = $null
    try {
        $ssisCatalogCheck.Open()
        $command = $ssisCatalogCheck.CreateCommand()
        $command.CommandText = "IF DB_ID(N'SSISDB') IS NULL THROW 51314, 'No existe el catálogo SSISDB.', 1;"
        [void]$command.ExecuteNonQuery()
    }
    finally { if ($command) { $command.Dispose() }; $ssisCatalogCheck.Dispose() }
}

& (Join-Path $PSScriptRoot 'Import-NorthwindAnalysisServices.ps1') -Tabular
if ([Enum]::GetNames([Microsoft.AnalysisServices.Tabular.ModelPermission]) -notcontains 'Refresh') {
    throw 'La biblioteca TOM instalada no ofrece permisos de modelo Refresh.'
}

$analysis = [Microsoft.AnalysisServices.Server]::new()
try {
    $analysis.Connect($AnalysisServer)
    $database = $analysis.Databases.FindByName($ModelDatabase)
    if (-not $database) { throw "No existe el modelo '$ModelDatabase' en '$AnalysisServer'." }
    $ownedModel = @($database.Model.Annotations | Where-Object {
        $_.Name -eq 'NorthwindPracticeModel' -and $_.Value -eq 'Northwind.OLAP'
    }).Count -gt 0
    if (-not $ownedModel) { throw "El modelo '$ModelDatabase' no tiene el marcador Northwind.OLAP; no se modificó." }

    $role = $database.Model.Roles.Find($roleName)
    if ($role -and [string]$role.Description -cne $roleMarker) {
        throw "El rol SSAS '$roleName' existe y no pertenece a este job; no se cambió."
    }
    if (-not $role) {
        $role = [Microsoft.AnalysisServices.Tabular.ModelRole]::new()
        $role.Name = $roleName
        $role.Description = $roleMarker
        [void]$database.Model.Roles.Add($role)
    }
    $role.ModelPermission = [Microsoft.AnalysisServices.Tabular.ModelPermission]::Refresh
    $role.Members.Clear()
    $principalSid = ([Security.Principal.NTAccount]::new($agentPrincipal)).Translate([Security.Principal.SecurityIdentifier]).Value
    $member = [Microsoft.AnalysisServices.Tabular.WindowsModelRoleMember]::new()
    $member.MemberName = $agentPrincipal
    $member.MemberId = $principalSid
    [void]$role.Members.Add($member)
    $database.Model.SaveChanges()
}
finally {
    if ($analysis.Connected) { $analysis.Disconnect() }
}

& (Join-Path $PSScriptRoot 'Configure-NorthwindOLAPAccess.ps1') -Server $WarehouseServer -WarehouseDatabase $WarehouseDatabase

if ([string]::IsNullOrWhiteSpace($LogDirectory) -or -not [IO.Path]::IsPathRooted($LogDirectory)) {
    throw 'LogDirectory debe ser una ruta local absoluta.'
}
if (Test-Path -LiteralPath $LogDirectory -PathType Leaf) { throw "LogDirectory apunta a un archivo: '$LogDirectory'." }
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$acl = Get-Acl -LiteralPath $LogDirectory
$engineService = Get-CimInstance Win32_Service -Filter "Name='MSSQLSERVER'"
if (-not $engineService -or $engineService.State -ne 'Running') { throw 'Inicie el servicio del motor SQL Server antes de configurar los logs.' }
$logPrincipals = @($agentPrincipal, [string]$engineService.StartName) | Where-Object { $_ } | Select-Object -Unique
foreach ($principal in $logPrincipals) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $principal,
        [Security.AccessControl.FileSystemRights]::Modify,
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit,
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $LogDirectory -AclObject $acl

Write-Output "Permiso Refresh '$roleName' configurado para '$agentPrincipal' en '$ModelDatabase'; lectura DW y logs acotados a '$LogDirectory'."
