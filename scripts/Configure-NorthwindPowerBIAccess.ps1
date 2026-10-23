[CmdletBinding()]
param(
    [string]$AnalysisServer='localhost',
    [ValidateSet('NorthwindOLAP','NorthwindOLAP_Test')]
    [string]$ModelDatabase='NorthwindOLAP',
    [string]$MemberName=([Security.Principal.WindowsIdentity]::GetCurrent().Name)
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Import-NorthwindAnalysisServices.ps1') -Tabular
$sid=([Security.Principal.NTAccount]::new($MemberName)).Translate([Security.Principal.SecurityIdentifier]).Value
$server=[Microsoft.AnalysisServices.Server]::new()
try{
    $server.Connect($AnalysisServer)
    $database=$server.Databases.FindByName($ModelDatabase)
    if(-not $database){throw "No existe $ModelDatabase en $AnalysisServer."}
    if(-not @($database.Model.Annotations | Where-Object {$_.Name -eq 'NorthwindPracticeModel' -and $_.Value -eq 'Northwind.OLAP'}).Count){
        throw 'El modelo no pertenece a la práctica Northwind.'
    }
    $marker='Northwind practice read role managed by Configure-NorthwindPowerBIAccess.ps1.'
    $role=$database.Model.Roles.Find('NorthwindPowerBIReader')
    if($role -and $role.Description -ne $marker){throw 'El rol de lectura existente no pertenece a este script.'}
    if(-not $role){
        $role=[Microsoft.AnalysisServices.Tabular.ModelRole]::new()
        $role.Name='NorthwindPowerBIReader';$role.Description=$marker
        [void]$database.Model.Roles.Add($role)
    }
    $role.ModelPermission=[Microsoft.AnalysisServices.Tabular.ModelPermission]::Read
    if(-not @($role.Members | Where-Object {$_.MemberId -eq $sid}).Count){
        $member=[Microsoft.AnalysisServices.Tabular.WindowsModelRoleMember]::new()
        $member.MemberName=$MemberName;$member.MemberId=$sid
        [void]$role.Members.Add($member)
    }
    [void]$database.Model.SaveChanges()
    Write-Output "Lectura del modelo $ModelDatabase concedida a $MemberName mediante NorthwindPowerBIReader."
}finally{$server.Dispose()}
