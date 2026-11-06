#Requires -Version 5.1
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost -ReadOnly
$service = Get-PocService
if ($null -eq $service) { Write-Output 'PoC service absent'; return }
$service | Select-Object Name, State, StartMode, StartName, ProcessId, ExitCode, ServiceSpecificExitCode, PathName
if ($service.ProcessId -ne 0) {
    Get-Process -Id $service.ProcessId | Select-Object Id, SessionId,
        @{Name='StartTimeUtc';Expression={$_.StartTime.ToUniversalTime().ToString('o')}},
        CPU, WorkingSet64, PrivateMemorySize64
}
