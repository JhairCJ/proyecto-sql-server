[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [string]$AnalysisServer = 'localhost',
    [string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $PSScriptRoot '../docs/evidencias/despliegue' }
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force
$job = 'NorthwindBIJob_Test'
$model = 'NorthwindOLAP_Test'
$warehouse = 'Northwind_DW_Test'
$create = Join-Path $PSScriptRoot '../scripts/Create-NorthwindBIJob.ps1'
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

function Sql([string]$Database, [string]$Query, [hashtable]$Parameters = @{}, [switch]$Fixture) {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open()
        if ($Fixture) {
            if ($Database -ne $warehouse) { throw 'Fixture fuera del almacén de prueba.' }
            $guard = $connection.CreateCommand()
            $guard.CommandText = @'
IF DB_NAME() <> N'Northwind_DW_Test' OR NOT EXISTS (
 SELECT 1 FROM sys.extended_properties WHERE class=0
 AND name=N'NorthwindPracticeTestDatabase' AND CONVERT(nvarchar(128),value)=N'Northwind_DW')
 THROW 51401,'La base no es la copia marcada del DW.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE name=DB_NAME() AND (is_trustworthy_on=1 OR is_db_chaining_on=1))
 THROW 51402,'Aislamiento de la copia desactivado.',1;
'@
            try { [void]$guard.ExecuteNonQuery() } finally { $guard.Dispose() }
        }
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 120
        $command.CommandText = $Query
        foreach ($name in $Parameters.Keys) { [void]$command.Parameters.AddWithValue($name, $Parameters[$name]) }
        $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($command)
        $data = [System.Data.DataSet]::new()
        try { [void]$adapter.Fill($data); return ,$data } finally { $adapter.Dispose(); $command.Dispose() }
    }
    finally { $connection.Dispose() }
}

& (Join-Path $PSScriptRoot '../scripts/Import-NorthwindAnalysisServices.ps1') -Adomd
function Dax([int]$Order) {
    $connection = [Microsoft.AnalysisServices.AdomdClient.AdomdConnection]::new("Data Source=$AnalysisServer;Initial Catalog=$model")
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = "EVALUATE ROW(`"Neto`",CALCULATE([Ventas netas],Fact_Ventas[OrderID]=$Order))"
        try {
            $reader = $command.ExecuteReader()
            try {
                if (-not $reader.Read()) { return $null }
                $value = $reader.GetValue(0)
            }
            finally { $reader.Dispose() }
            if ($value -is [DBNull]) { return $null }
            return $value
        }
        finally { $command.Dispose() }
    }
    finally { $connection.Dispose() }
}

function Run-Job([string]$Scenario, [int]$ExpectedStatus) {
    $prior = (Sql 'msdb' 'SELECT ISNULL(MAX(instance_id),0) LastId FROM dbo.sysjobhistory WHERE job_id=(SELECT job_id FROM dbo.sysjobs WHERE name=@job);' @{ '@job'=$job }).Tables[0].Rows[0].LastId
    [void](Sql 'msdb' 'EXEC dbo.sp_start_job @job_name=@job;' @{ '@job'=$job })
    $deadline = (Get-Date).AddSeconds(180)
    do {
        Start-Sleep -Milliseconds 500
        $history = (Sql 'msdb' @'
SELECT step_id,run_status,message,instance_id FROM dbo.sysjobhistory
WHERE job_id=(SELECT job_id FROM dbo.sysjobs WHERE name=@job) AND instance_id>@prior
ORDER BY instance_id;
'@ @{ '@job'=$job; '@prior'=$prior }).Tables[0]
        $outcome = @($history.Rows | Where-Object step_id -eq 0)
    } while ($outcome.Count -eq 0 -and (Get-Date) -lt $deadline)
    if ($outcome.Count -ne 1) { throw "El job no terminó dentro del plazo: $Scenario." }
    if ($outcome[0].run_status -ne $ExpectedStatus) {
        throw "Resultado inesperado en '$Scenario': $($outcome[0].message)"
    }
    $steps = @($history.Rows | Where-Object step_id -ne 0 | ForEach-Object {
        [pscustomobject]@{ Step=$_.step_id; Status=$_.run_status; Message=$_.message; HistoryId=$_.instance_id }
    })
    return [pscustomobject]@{ Scenario=$Scenario; Status=$ExpectedStatus; Steps=$steps; Outcome=$outcome[0].message }
}

function Original-Snapshot {
    return (Sql 'Northwind_DW' 'SELECT * FROM dbo.PackageConfig ORDER BY PackageName; SELECT * FROM dbo.Fact_Ventas ORDER BY Venta_SK;').GetXml() +
        (Sql 'NorthWind' 'SELECT COUNT_BIG(*) Clientes FROM dbo.Customers;SELECT COUNT_BIG(*) Pedidos FROM dbo.Orders;SELECT COUNT_BIG(*) Lineas FROM dbo.OrderDetails;').GetXml()
}
function Marks([switch]$Dates) {
    $date = if ($Dates) { ',LastSuccessfulLoad' } else { '' }
    return (Sql $warehouse "SELECT PackageName,LastRowVersion$date FROM dbo.PackageConfig ORDER BY PackageName;").GetXml()
}
function Add-Fixture([int]$Order) {
    [void](Invoke-NorthwindTestSql -Server $Server -Database $warehouse -Commit -Sql @"
IF EXISTS(SELECT 1 FROM dbo.Fact_Ventas WHERE OrderID=$Order) THROW 51403,'ID de fixture ocupado.',1;
INSERT dbo.Fact_Ventas(Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,
 OrderID,ProductID,Cantidad,PrecioUnitario,Descuento,ImporteBruto,ImporteDescuento,ImporteNeto)
SELECT TOP(1) Cliente_SK,Empleado_SK,Producto_SK,Transportista_SK,FechaPedido_SK,FechaRequerida_SK,FechaEnvio_SK,
 $Order,ProductID,2,20,0.1,40,4,36 FROM dbo.Fact_Ventas ORDER BY Venta_SK;
IF @@ROWCOUNT<>1 THROW 51404,'Falta la fila de referencia del fixture.',1;
"@)
}

$original = Original-Snapshot
$fixtureOne = 2100000000 + (Get-Random -Minimum 0 -Maximum 9000000)
$fixtureTwo = $fixtureOne + 1
$fixtures = [System.Collections.Generic.List[int]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$triggerCreated = $false
$stepCommand = $null
$testError = $null
$cleanupError = $null
try {
    & $create -Server $Server -AnalysisServer $AnalysisServer -JobName $job -StartTime '03:15:00' -EveryNDays 2
    $firstId = (Sql 'msdb' 'SELECT job_id FROM dbo.sysjobs WHERE name=@job;' @{ '@job'=$job }).Tables[0].Rows[0].job_id
    & $create -Server $Server -AnalysisServer $AnalysisServer -JobName $job -StartTime '03:15:00' -EveryNDays 2
    $definition = (Sql 'msdb' @'
SELECT job_id,enabled FROM dbo.sysjobs WHERE name=@job;
SELECT step_id,subsystem,on_success_action,on_fail_action FROM dbo.sysjobsteps WHERE job_id=(SELECT job_id FROM dbo.sysjobs WHERE name=@job) ORDER BY step_id;
SELECT s.enabled,s.freq_interval,s.active_start_time FROM dbo.sysschedules s JOIN dbo.sysjobschedules j ON s.schedule_id=j.schedule_id WHERE j.job_id=(SELECT job_id FROM dbo.sysjobs WHERE name=@job);
'@ @{ '@job'=$job })
    if ($definition.Tables[0].Rows.Count -ne 1 -or $definition.Tables[0].Rows[0].job_id -ne $firstId -or $definition.Tables[0].Rows[0].enabled -ne 0) { throw 'Creación duplicada o job habilitado.' }
    if ($definition.Tables[1].Rows.Count -ne 2 -or $definition.Tables[1].Rows[0].subsystem -ne 'SSIS' -or $definition.Tables[1].Rows[1].subsystem -ne 'ANALYSISCOMMAND') { throw 'Etapas nativas incompletas.' }
    if ($definition.Tables[2].Rows.Count -ne 1 -or $definition.Tables[2].Rows[0].enabled -ne 0 -or $definition.Tables[2].Rows[0].freq_interval -ne 2 -or $definition.Tables[2].Rows[0].active_start_time -ne 31500) { throw 'Programación duplicada o no configurable.' }
    'PASS: creación repetible, dos etapas nativas, horario configurable y job deshabilitado'

    Add-Fixture $fixtureOne
    $fixtures.Add($fixtureOne)
    if ($null -ne (Dax $fixtureOne)) { throw 'El modelo refleja un fixture sin procesarlo.' }
    $results.Add((Run-Job 'Carga y procesamiento nativos' 1))
    if ([decimal](Dax $fixtureOne) -ne 36) { throw 'El job reportó éxito sin actualizar el modelo.' }
    'PASS: carga desde SSISDB y procesamiento efectivo de datos nuevos'

    Add-Fixture $fixtureTwo
    $fixtures.Add($fixtureTwo)
    [void](Sql $warehouse "CREATE TRIGGER dbo.NorthwindJobFailMark ON dbo.PackageConfig AFTER UPDATE AS IF EXISTS(SELECT 1 FROM inserted WHERE PackageName=N'Cliente') THROW 51405,'Fallo de confirmación inyectado por prueba del job.',1;" -Fixture)
    $triggerCreated = $true
    $beforeFailure = Marks -Dates
    $failedETL = Run-Job 'Fallo ETL detiene procesamiento' 0
    $results.Add($failedETL)
    if ($failedETL.Steps.Count -ne 1 -or $failedETL.Steps[0].Step -ne 1 -or $failedETL.Steps[0].Status -ne 0) { throw 'El fallo ETL ejecutó etapas dependientes.' }
    if ((Marks -Dates) -cne $beforeFailure -or $null -ne (Dax $fixtureTwo)) { throw 'El fallo ETL confirmó avance o procesó el segundo fixture.' }
    [void](Sql $warehouse 'DROP TRIGGER dbo.NorthwindJobFailMark;' -Fixture)
    $triggerCreated = $false
    $results.Add((Run-Job 'Reintento tras fallo ETL' 1))
    if ([decimal](Dax $fixtureTwo) -ne 36) { throw 'El reintento no incorporó el segundo fixture.' }
    'PASS: fallo ETL conserva marcas/fechas, omite procesamiento y permite reintento'

    $stepCommand = (Sql 'msdb' 'SELECT command FROM dbo.sysjobsteps WHERE job_id=(SELECT job_id FROM dbo.sysjobs WHERE name=@job) AND step_id=2;' @{ '@job'=$job }).Tables[0].Rows[0].command
    $badCommand = '{"refresh":{"type":"full","objects":[{"database":"NorthwindOLAP_MissingJobFixture"}]}}'
    [void](Sql 'msdb' 'EXEC dbo.sp_update_jobstep @job_name=@job,@step_id=2,@command=@command;' @{ '@job'=$job; '@command'=$badCommand })
    $beforeAnalyticFailure = Marks
    $failedAS = Run-Job 'Fallo analítico deja ciclo fallido' 0
    $results.Add($failedAS)
    if ($failedAS.Steps.Count -ne 2 -or $failedAS.Steps[0].Status -ne 1 -or $failedAS.Steps[1].Status -ne 0 -or (Marks) -cne $beforeAnalyticFailure) { throw 'Fallo analítico no conserva el avance de la carga.' }
    [void](Sql 'msdb' 'EXEC dbo.sp_update_jobstep @job_name=@job,@step_id=2,@command=@command;' @{ '@job'=$job; '@command'=$stepCommand })
    $stepCommand = $null
    $results.Add((Run-Job 'Recuperación del procesamiento' 1))
    'PASS: fallo analítico observable, marcas conservadas y recuperación correcta'
}
catch { $testError = $_.Exception.Message }
finally {
    try {
        if ($triggerCreated) { [void](Sql $warehouse 'DROP TRIGGER dbo.NorthwindJobFailMark;' -Fixture) }
        if ($stepCommand) { [void](Sql 'msdb' 'EXEC dbo.sp_update_jobstep @job_name=@job,@step_id=2,@command=@command;' @{ '@job'=$job; '@command'=$stepCommand }) }
        if ($fixtures.Count -gt 0) {
            $ids = $fixtures -join ','
            [void](Invoke-NorthwindTestSql -Server $Server -Database $warehouse -Commit -Sql "DELETE dbo.Fact_Ventas WHERE OrderID IN($ids); IF @@ROWCOUNT<>$($fixtures.Count) THROW 51406,'No se limpiaron los fixtures del job.',1;")
            & (Join-Path $PSScriptRoot '../scripts/Process-NorthwindOLAP.ps1') -AnalysisServer $AnalysisServer -WarehouseServer $Server -LogDirectory $EvidenceDirectory
        }
        [void](Sql 'msdb' @'
IF EXISTS(SELECT 1 FROM dbo.sysjobs WHERE name=@job AND description=N'Northwind practice job managed by Create-NorthwindBIJob.ps1.')
 EXEC dbo.sp_delete_job @job_name=@job,@delete_unused_schedule=1;
'@ @{ '@job'=$job })
    }
    catch { $cleanupError = $_.Exception.Message }
}

if ((Original-Snapshot) -cne $original) { $cleanupError = 'Las bases originales cambiaron durante la prueba.' }
$report = [ordered]@{ Result=if($testError -or $cleanupError){'FAILED'}else{'PASS'}; Job=$job; Scenarios=$results; TestError=$testError; CleanupError=$cleanupError; OriginalDatabases='UNCHANGED' }
$path = Join-Path $EvidenceDirectory ("job-" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
if ($testError -or $cleanupError) { throw "Prueba: $testError. Limpieza: $cleanupError. Evidencia: $path" }
& (Join-Path $PSScriptRoot '../scripts/Compare-NorthwindOLAP.ps1') -SqlServer $Server -AnalysisServer $AnalysisServer -EvidenceDirectory $EvidenceDirectory
Write-Output "PASS: integración real del job, fallos/reintentos, limpieza y originales conservados. Evidencia: $path"
