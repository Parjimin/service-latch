#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][string]$BinaryPath, [switch]$LabConfirmed)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost -LabConfirmed:$LabConfirmed -ReadOnly:$WhatIfPreference
$paths = Get-PocPaths
$source = (Get-Item -LiteralPath $BinaryPath -ErrorAction Stop).FullName
if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or [IO.Path]::GetExtension($source) -ine '.exe') {
    throw 'BinaryPath must be a built Windows .exe file.'
}
Assert-NoReparsePath $source
Assert-WindowsX64Binary $source
Assert-NoReparsePath $paths.BinaryRoot
Assert-NoReparsePath $paths.DataRoot
if ($null -ne (Get-PocService) -or (Test-Path -LiteralPath $paths.BinaryRoot) -or
    (Test-Path -LiteralPath $paths.DataRoot)) {
    throw 'Service name or installation directory already exists. Refusing collision/adoption.'
}
$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
Write-Host "Service: $script:PocName`nAccount: NT AUTHORITY\LocalService`nAutomatic; not started now.`nBinary: $($paths.Binary)`nData: $($paths.DataRoot)`nSHA256: $hash"
if (-not $PSCmdlet.ShouldProcess($script:PocName, 'Create ONLY this lab service and its two owned directories')) { return }
Initialize-PocNative
$createdBinary = $false; $createdData = $false; $createdService = $false
try {
    [ServiceLatchPoc1ANative]::CreateSecureDirectory($paths.BinaryRoot); $createdBinary = $true
    [ServiceLatchPoc1ANative]::CreateSecureDirectory($paths.DataRoot); $createdData = $true
    [ServiceLatchPoc1ANative]::CreateSecureDirectory($paths.Logs)
    Copy-Item -LiteralPath $source -Destination $paths.Binary
    if ((Get-FileHash -LiteralPath $paths.Binary -Algorithm SHA256).Hash -cne $hash) { throw 'Copy hash mismatch.' }
    [ordered]@{ Schema=1; ProjectId=$script:PocId; ServiceName=$script:PocName
        BinaryRoot=$paths.BinaryRoot; DataRoot=$paths.DataRoot; Command=$paths.Command
        BinarySha256=$hash; InstalledUtc=[DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $paths.Marker -Encoding UTF8
    [ServiceLatchPoc1ANative]::CreateOwn($script:PocName, $paths.Command); $createdService = $true
    [ServiceLatchPoc1ANative]::ConfigureOwn($script:PocName)
    # This no-op PoC only writes logs. Use the built-in LocalService SID directly;
    # do not add a service-SID activation/reboot dependency for first-start smoke.
    $sid = New-Object Security.Principal.SecurityIdentifier('S-1-5-19')
    Set-PocDirectoryAcl $paths.BinaryRoot $sid 'ReadAndExecute'
    Set-PocDirectoryAcl $paths.DataRoot $sid 'ReadAndExecute'
    Set-PocDirectoryAcl $paths.Logs $sid 'Modify'
    $service = Assert-OwnedPoc $paths
    if ($service.StartMode -ne 'Auto' -or $service.State -ne 'Stopped') { throw 'Unexpected installed startup/state.' }
    $service | Select-Object Name, State, StartMode, StartName, PathName
} catch {
    $failure = $_
    # Roll back ONLY objects created successfully by THIS invocation.
    # If service removal is uncertain, preserve files/marker for reviewed recovery.
    if ($createdService) {
        try {
            [ServiceLatchPoc1ANative]::DeleteOwn($script:PocName)
            if ($null -ne (Get-PocService)) { throw 'Service still exists/marked for deletion.' }
        } catch { throw "Install failed: $failure. Removal uncertain: $_. Owned files preserved; inspect lab/revert snapshot." }
    }
    if ($createdData) { Assert-NoReparseTree $paths.DataRoot; Remove-Item -LiteralPath $paths.DataRoot -Recurse -Force }
    if ($createdBinary) { Assert-NoReparseTree $paths.BinaryRoot; Remove-Item -LiteralPath $paths.BinaryRoot -Recurse -Force }
    throw $failure
}
