[CmdletBinding()]
param([string]$Server = 'localhost')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Northwind.TestTools.psm1') -Force

function Assert-Rejected {
    param([string]$Name, [scriptblock]$Action, [string]$ExpectedMessage)
    $rejected = $false
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notmatch $ExpectedMessage) { throw }
        $rejected = $true
        Write-Output "PASS: $Name rechazado: $($_.Exception.Message)"
    }
    if (-not $rejected) { throw "FAIL: $Name fue aceptado." }
}

foreach ($database in @('NorthWind','Northwind_DW','BikeStores','master')) {
    Assert-Rejected "Destino $database" {
        Invoke-NorthwindTestSql -Server $Server -Database $database -Sql 'SELECT 1;'
    } -ExpectedMessage 'Cannot validate argument on parameter'
}
$result = Invoke-NorthwindTestSql -Server $Server -Database Northwind_Test -Sql @'
IF USER_NAME() <> N'NorthwindFixture' THROW 51011,'Identidad incorrecta.',1;
DECLARE @original nvarchar(40)=(SELECT CompanyName FROM dbo.Customers WHERE CustomerID=N'VINET');
UPDATE dbo.Customers SET CompanyName=N'Fixture aislado' WHERE CustomerID=N'VINET';
IF @@ROWCOUNT<>1 THROW 51012,'No se actualizó el cliente de prueba.',1;
SELECT DB_NAME() AS DatabaseName,USER_NAME() AS UserName,CompanyName,@original AS OriginalName FROM dbo.Customers WHERE CustomerID=N'VINET';
'@
if ($result.Tables[0].Rows[0].CompanyName -ne 'Fixture aislado') { throw 'Fixture no visible dentro de transacción.' }
Write-Output 'PASS: fixture ejecutado en Northwind_Test bajo NorthwindFixture y revertido.'
$check = Invoke-NorthwindTestSql -Server $Server -Database Northwind_Test -Sql 'SELECT CompanyName FROM dbo.Customers WHERE CustomerID=N''VINET'';'
if ($check.Tables[0].Rows[0].CompanyName -ne $result.Tables[0].Rows[0].OriginalName) { throw 'La transacción no fue revertida.' }
Write-Output 'PASS: conexión nueva confirma rollback del fixture.'
try {
    [void](Invoke-NorthwindTestSql -Server $Server -Database Northwind_Test -Commit -Sql @'
IF EXISTS (SELECT 1 FROM dbo.CustomerDemographics WHERE CustomerTypeID=N'NT_PROBE')
    THROW 51014,'Fixture previo presente; no se sobrescribe.',1;
INSERT dbo.CustomerDemographics(CustomerTypeID,CustomerDesc) VALUES(N'NT_PROBE',N'Prueba de commit');
'@)
    $inserted = $true
    $committed = Invoke-NorthwindTestSql -Server $Server -Database Northwind_Test -Sql 'SELECT COUNT(*) AS ProbeCount FROM dbo.CustomerDemographics WHERE CustomerTypeID=N''NT_PROBE'';'
    if ($committed.Tables[0].Rows[0].ProbeCount -ne 1) { throw 'Commit no visible desde otra conexión.' }
    Write-Output 'PASS: -Commit persiste un fixture solo en la copia.'
} finally {
    if (Get-Variable inserted -ErrorAction SilentlyContinue) {
        [void](Invoke-NorthwindTestSql -Server $Server -Database Northwind_Test -Commit -Sql 'DELETE dbo.CustomerDemographics WHERE CustomerTypeID=N''NT_PROBE'';')
    }
}
foreach ($sql in @(
    'UPDATE NorthWind.dbo.Customers SET CompanyName=N''NO PERMITIDO'' WHERE CustomerID=N''VINET'';',
    'USE Northwind_DW; UPDATE dbo.PackageConfig SET LastSuccessfulLoad=GETDATE();',
    'REVERT; SELECT USER_NAME();'
)) {
    Assert-Rejected "Escape de sesión: $sql" {
        Invoke-NorthwindTestSql -Server $Server -Database Northwind_Test -Sql $sql
    } -ExpectedMessage 'not able to access the database|non-revertible'
}
$dw = Invoke-NorthwindTestSql -Server $Server -Database Northwind_DW_Test -Sql 'SELECT DB_NAME() AS DatabaseName, COUNT(*) AS Controls FROM dbo.PackageConfig;'
if ($dw.Tables[0].Rows[0].Controls -ne 5) { throw 'Se esperaban cinco controles en la referencia inicial.' }
Write-Output 'PASS: destino DW de prueba accesible con sus cinco controles.'
