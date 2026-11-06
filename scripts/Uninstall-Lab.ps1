#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$LabConfirmed)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost -LabConfirmed:$LabConfirmed -ReadOnly:$WhatIfPreference
$paths = Get-PocPaths
if ($null -eq (Get-PocService) -and -not (Test-Path -LiteralPath $paths.BinaryRoot) -and
    -not (Test-Path -LiteralPath $paths.DataRoot)) { Write-Host 'Already absent; nothing to clean.'; return }
$service = Assert-OwnedPoc $paths
if (-not $PSCmdlet.ShouldProcess($script:PocName, "Stop/delete ONLY this lab service and remove $($paths.BinaryRoot) and $($paths.DataRoot), INCLUDING logs")) { return }
Initialize-PocNative
if ($null -ne $service) {
    $controller = New-Object ServiceProcess.ServiceController($script:PocName)
    try {
        $dependents = @($controller.DependentServices)
        try { if ($dependents.Count -ne 0) { throw 'Unexpected dependent service; refusing cascading stop.' } }
        finally { foreach ($dependent in $dependents) { $dependent.Dispose() } }
    } finally { $controller.Dispose() }
    if ($service.State -ne 'Stopped') {
        [ServiceLatchPoc1ANative]::StopOwn($script:PocName)
        $null = Wait-PocState 'Stopped'
    }
    # Revalidate after stop, before delete. No registry fallback or force-kill.
    $null = Assert-OwnedPoc $paths
    [ServiceLatchPoc1ANative]::DeleteOwn($script:PocName)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($null -ne (Get-PocService)) {
        if ($clock.Elapsed.TotalSeconds -ge 20) { throw 'Service remains marked for deletion. Close Services/other handles, then retry; files preserved.' }
        Start-Sleep -Milliseconds 250
    }
}
Assert-NoReparseTree $paths.BinaryRoot
Assert-NoReparseTree $paths.DataRoot
foreach ($root in @($paths.BinaryRoot, $paths.DataRoot)) {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($null -ne (Get-PocService) -or (Test-Path -LiteralPath $paths.BinaryRoot) -or
    (Test-Path -LiteralPath $paths.DataRoot)) { throw 'Cleanup incomplete.' }
Write-Host 'PoC service and both owned directories are absent.'
