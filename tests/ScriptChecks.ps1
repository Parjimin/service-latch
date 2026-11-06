#Requires -Version 5.1
# Filesystem fixtures and pure ownership checks only. Never creates a service.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$checked = 0
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw ($errors | Out-String) }
    $checked++
}
. (Join-Path $root 'scripts/Common.ps1')
Initialize-PocNative # Compiles declarations. Does not call a native API.
function Assert-Rejected { param([scriptblock]$Action)
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe fixture unexpectedly accepted.' }
}
function New-Fixture {
    $paths = [pscustomobject]@{ BinaryRoot='C:\Program Files\owned'; DataRoot='C:\ProgramData\owned'
        Command='"C:\Program Files\owned\service-latch-poc1a.exe" --service --log-dir "C:\ProgramData\owned\logs"' }
    [pscustomobject]@{
        Paths=$paths
        Marker=[pscustomobject]@{Schema=1; ProjectId=$script:PocId; ServiceName=$script:PocName
            BinaryRoot=$paths.BinaryRoot; DataRoot=$paths.DataRoot; Command=$paths.Command; BinarySha256=('a'*64)}
        Service=[pscustomobject]@{Name=$script:PocName; PathName=$paths.Command; StartName='NT AUTHORITY\LocalService'
            ServiceType='Own Process'; DesktopInteract=$false}
    }
}
$fixture = New-Fixture
Assert-PocFingerprint $fixture.Marker $fixture.Service $fixture.Paths
Assert-PocFingerprint $fixture.Marker $null $fixture.Paths # owned files after deletion
foreach ($change in @('foreign-marker','different-service','binary-command','account','shared-process','interactive','invalid-hash','schema','outside-root')) {
    $f = New-Fixture
    switch ($change) {
        'foreign-marker' { $f.Marker.ProjectId='foreign' }
        'different-service' { $f.Service.Name='wuauserv' }
        'binary-command' { $f.Service.PathName='C:\different.exe' }
        'account' { $f.Service.StartName='LocalSystem' }
        'shared-process' { $f.Service.ServiceType='Share Process' }
        'interactive' { $f.Service.DesktopInteract=$true }
        'invalid-hash' { $f.Marker.BinarySha256='bad' }
        'schema' { $f.Marker.Schema=2 }
        'outside-root' { $f.Marker.DataRoot='C:\Windows' }
    }
    Assert-Rejected { Assert-PocFingerprint $f.Marker $f.Service $f.Paths }
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('sl-poc1a-test-' + [Guid]::NewGuid().ToString('N'))
$outside = Join-Path ([IO.Path]::GetTempPath()) ('sl-poc1a-outside-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
$null = New-Item -ItemType Directory -Path $outside
$link = Join-Path $temporary 'escape'
try {
    Assert-NoReparseTree $temporary
    $fake = Join-Path $temporary 'headers.exe'
    $header = New-Object byte[] 128
    $header[0]=0x4d; $header[1]=0x5a; $header[60]=64
    $header[64]=0x50; $header[65]=0x45; $header[68]=0x64; $header[69]=0x86
    $header[86]=2; $header[88]=0x0b; $header[89]=2
    [IO.File]::WriteAllBytes($fake, $header)
    Assert-WindowsX64Binary $fake # header fixture only, never executed
    $header[68]=0x64; $header[69]=0xaa # ARM64
    [IO.File]::WriteAllBytes($fake, $header)
    Assert-Rejected { Assert-WindowsX64Binary $fake }
    $header[68]=0x64; $header[69]=0x86; $header[87]=0x20 # DLL
    [IO.File]::WriteAllBytes($fake, $header)
    Assert-Rejected { Assert-WindowsX64Binary $fake }
    [IO.File]::WriteAllBytes($fake, (New-Object byte[] 10))
    Assert-Rejected { Assert-WindowsX64Binary $fake }
    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    $null = New-Item -ItemType $kind -Path $link -Target $outside
    Assert-Rejected { Assert-NoReparseTree $temporary }
} finally {
    # Delete only the link, never recurse into its target.
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
    Remove-Item -LiteralPath $temporary -Recurse -Force
    Remove-Item -LiteralPath $outside -Recurse -Force
}
Write-Output "PASS: $checked PowerShell files parsed; Native.cs compiled; 9 unsafe ownership fixtures rejected; x64/ARM64/DLL/truncated PE guards checked; reparse escape rejected. No SCM mutation invoked."
