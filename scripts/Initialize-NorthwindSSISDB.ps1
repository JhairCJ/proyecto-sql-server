[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [switch]$CreateCatalog,
    [Security.SecureString]$CatalogPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    if ($CreateCatalog -and $CatalogPassword) {
        throw 'Para no exponer ni descartar el SecureString, ejecute este paso desde Windows PowerShell 5.1.'
    }
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Server', $Server)
    if ($CreateCatalog) { $arguments += '-CreateCatalog' }
    & $windowsPowerShell @arguments
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar el catálogo SSISDB.' }
    return
}

$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = 'master'
$builder['Integrated Security'] = $true
$builder['Encrypt'] = $true
$builder['TrustServerCertificate'] = $true
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$plainPassword = $null
$passwordPointer = [IntPtr]::Zero

try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = "SELECT CONVERT(bit, CASE WHEN DB_ID(N'SSISDB') IS NULL THEN 0 ELSE 1 END);"
    $exists = [bool]$command.ExecuteScalar()
    $command.Dispose()

    if ($exists) {
        Write-Output "SSISDB ya existe en '$Server'; no se modificó."
        return
    }
    if (-not $CreateCatalog) {
        Write-Output "SSISDB no existe en '$Server'. No se creó; use -CreateCatalog para solicitar la creación explícita."
        return
    }

    if (-not $CatalogPassword) {
        $CatalogPassword = Read-Host 'Elija la contraseña del catálogo SSISDB y guárdela en un almacén seguro' -AsSecureString
    }
    if ($CatalogPassword.Length -lt 1) { throw 'La contraseña de SSISDB no puede estar vacía.' }

    $command = $connection.CreateCommand()
    $command.CommandText = @'
DECLARE @showAdvanced bit = CONVERT(bit, (SELECT value_in_use FROM sys.configurations WHERE name = N'show advanced options'));
IF @showAdvanced = 0
BEGIN
    EXEC sys.sp_configure N'show advanced options', 1;
    RECONFIGURE;
END;
IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = N'clr enabled' AND value_in_use = 0)
BEGIN
    EXEC sys.sp_configure N'clr enabled', 1;
    RECONFIGURE;
END;
IF @showAdvanced = 0
BEGIN
    EXEC sys.sp_configure N'show advanced options', 0;
    RECONFIGURE;
END;
'@
    [void]$command.ExecuteNonQuery()
    $command.Dispose()

    $ssis170Roots = [System.Collections.Generic.List[string]]::new()
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        foreach ($installation in (& $vswhere -all -products '*' -property installationPath)) {
            $ssis170Roots.Add((Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/SSIS/170'))
        }
    }
    foreach ($programRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        foreach ($ssms in Get-ChildItem -LiteralPath $programRoot -Directory -Filter 'Microsoft SQL Server Management Studio*' -ErrorAction SilentlyContinue) {
            $ssis170Roots.Add((Join-Path $ssms.FullName 'Release/Common7/IDE/CommonExtensions/Microsoft/SSIS/170'))
        }
        $ssis170Roots.Add((Join-Path $programRoot 'Microsoft SQL Server/170/DTS'))
    }
    $ssis170Roots = @($ssis170Roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
    if ($ssis170Roots.Count -eq 0) { throw 'No se encontró el runtime SSIS 170 ni sus ensamblados de administración.' }

    $assemblySearchPaths = @($ssis170Roots | ForEach-Object {
        $_
        (Join-Path $_ 'Binn')
        (Join-Path $_ 'Extensions/SQLCommon')
    } | Where-Object { Test-Path -LiteralPath $_ })
    $script:NorthwindSsisAssemblySearchPaths = $assemblySearchPaths
    $assemblyResolver = [ResolveEventHandler] {
        param($sender, $eventArgs)
        $fileName = ([Reflection.AssemblyName]::new($eventArgs.Name)).Name + '.dll'
        foreach ($directory in $script:NorthwindSsisAssemblySearchPaths) {
            $candidate = Join-Path $directory $fileName
            if (Test-Path -LiteralPath $candidate) {
                try { return [Reflection.Assembly]::LoadFrom($candidate) } catch { }
            }
        }
        return $null
    }
    [AppDomain]::CurrentDomain.add_AssemblyResolve($assemblyResolver)
    try {
        foreach ($name in 'Microsoft.SqlServer.Management.Sdk.Sfc.dll', 'Microsoft.SqlServer.ConnectionInfo.dll', 'Microsoft.SqlServer.SqlEnum.dll', 'Microsoft.SqlServer.Smo.dll', 'Microsoft.Data.SqlClient.dll') {
            $dependency = $assemblySearchPaths | ForEach-Object { Join-Path $_ $name } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if ($dependency) { [void][Reflection.Assembly]::LoadFrom($dependency) }
        }
        $integrationServicesDll = $assemblySearchPaths | ForEach-Object { Join-Path $_ 'Microsoft.SqlServer.Management.IntegrationServices.dll' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $integrationServicesDll) { throw 'No se encontró Microsoft.SqlServer.Management.IntegrationServices.dll de SSIS 170.' }
        [void][Reflection.Assembly]::LoadFrom($integrationServicesDll)
        if (-not ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) { throw 'No se pudo cargar Microsoft.Data.SqlClient de SSIS 170.' }

        $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($CatalogPassword)
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
        $catalogConnection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
        try {
            $catalogConnection.Open()
            $integrationServices = [Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices]::new($catalogConnection)
            $catalog = [Microsoft.SqlServer.Management.IntegrationServices.Catalog]::new($integrationServices, 'SSISDB', $plainPassword)
            $catalog.Create()
        }
        finally {
            if ($catalogConnection.State -ne [System.Data.ConnectionState]::Closed) { $catalogConnection.Close() }
            $catalogConnection.Dispose()
        }
    }
    finally {
        [AppDomain]::CurrentDomain.remove_AssemblyResolve($assemblyResolver)
        Remove-Variable -Name NorthwindSsisAssemblySearchPaths -Scope Script -ErrorAction SilentlyContinue
    }
    Write-Output "Catálogo SSISDB creado en '$Server'. Resguarde la contraseña y la clave maestra en un almacén seguro."
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $plainPassword = $null
    if ($connection.State -ne [System.Data.ConnectionState]::Closed) { $connection.Close() }
    $connection.Dispose()
}
