#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$LabConfirmed)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost -LabConfirmed:$LabConfirmed -ReadOnly:$WhatIfPreference
$paths = Get-PocPaths
$service = Assert-OwnedPoc $paths
if ($null -eq $service -or $service.State -ne 'Stopped') { throw 'Install first; smoke test requires PoC Stopped.' }
if (-not $PSCmdlet.ShouldProcess($script:PocName, 'Start/Stop the PoC, then inject one startup failure and one cleanup failure; no reboot')) { return }
Initialize-PocNative
$results = New-Object 'Collections.Generic.List[object]'
function Add-PocResult { param([string]$Case, $Observed)
    $results.Add([pscustomobject]@{ Case=$Case; Status='PASS'; Utc=[DateTime]::UtcNow.ToString('o')
        State=$Observed.State; Win32Exit=$Observed.ExitCode; SpecificExit=$Observed.ServiceSpecificExitCode })
}
function Start-ExpectedStartupFailure {
    try { [ServiceLatchPoc1ANative]::StartOwn($script:PocName, [string[]]@('--fail-startup')) }
    catch {
        # StartService can observe the service-specific failure before returning.
        $cause = $_.Exception
        while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
        if ($cause -isnot [ComponentModel.Win32Exception] -or $cause.NativeErrorCode -ne 1066) { throw }
    }
    # A native error alone is never a PASS: verify the expected final SCM codes.
    Wait-PocState 'Stopped' -SpecificExit 1001
}
try {
    [ServiceLatchPoc1ANative]::StartOwn($script:PocName, [string[]]@())
    $running = Wait-PocState 'Running'
    Start-Sleep -Seconds 1
    $process = Get-Process -Id $running.ProcessId
    if ($process.SessionId -ne 0) { throw 'Worker is not in service session 0.' }
    Add-PocResult 'manual_start_LocalService_session0' $running
    [ServiceLatchPoc1ANative]::StopOwn($script:PocName)
    $stopped = Wait-PocState 'Stopped'
    if ($stopped.ExitCode -ne 0 -or $stopped.ServiceSpecificExitCode -ne 0) { throw 'Normal stop returned an error.' }
    Add-PocResult 'normal_stop' $stopped
    Add-PocResult 'injected_startup_failure_1001' (Start-ExpectedStartupFailure)
    [ServiceLatchPoc1ANative]::StartOwn($script:PocName, [string[]]@('--fail-cleanup'))
    $null = Wait-PocState 'Running'
    [ServiceLatchPoc1ANative]::StopOwn($script:PocName)
    Add-PocResult 'injected_cleanup_failure_1002' (Wait-PocState 'Stopped' -SpecificExit 1002)
    # Fault arguments are transient. Normal Start must work again without reconfiguration.
    [ServiceLatchPoc1ANative]::StartOwn($script:PocName, [string[]]@())
    $null = Wait-PocState 'Running'
    [ServiceLatchPoc1ANative]::StopOwn($script:PocName)
    $final = Wait-PocState 'Stopped'
    if ($final.ExitCode -ne 0 -or $final.ServiceSpecificExitCode -ne 0) { throw 'Final normal stop did not reset error status.' }
    Add-PocResult 'normal_after_faults' $final
    $results | ConvertTo-Json -Depth 3
} catch {
    $results | ConvertTo-Json -Depth 3
    Write-Error "FAIL smoke: $_. Inspect status/logs. No force-kill or automatic reboot is attempted."
    throw
}
