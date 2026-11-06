#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:PocId = '8f61bc537e1c49aaa52ae744ad486ef0'
$script:PocName = 'ServiceLatch.Poc1A.' + $script:PocId

function Assert-LabHost {
    param([switch]$LabConfirmed, [switch]$ReadOnly)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        -not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit PowerShell on Windows x64.'
    }
    if (-not $ReadOnly) {
        if (-not $LabConfirmed) { throw 'Pass -LabConfirmed only on the dedicated disposable lab VM.' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'Open an elevated PowerShell in the lab. This script never self-elevates.'
            }
        } finally { $identity.Dispose() }
    }
}

function Get-PocPaths {
    $folder = 'ServiceLatch-Poc1A-' + $script:PocId
    $binaryRoot = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) $folder
    $dataRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) $folder
    $binary = Join-Path $binaryRoot 'service-latch-poc1a.exe'
    $logs = Join-Path $dataRoot 'logs'
    [pscustomobject]@{
        BinaryRoot = $binaryRoot; DataRoot = $dataRoot; Binary = $binary; Logs = $logs
        Marker = (Join-Path $dataRoot 'owner.json')
        Command = ('"' + $binary + '" --service --log-dir "' + $logs + '"')
    }
}

function Initialize-PocNative {
    if (-not ('ServiceLatchPoc1ANative' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs')
    }
}

function Assert-WindowsX64Binary {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw 'Not a PE executable.' }
        $stream.Position = 60
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 26)) { throw 'Invalid PE offset.' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Expected Windows x64 (AMD64) PE.' }
        $stream.Position = $offset + 22
        $characteristics = $reader.ReadUInt16()
        if (($characteristics -band 2) -eq 0 -or ($characteristics -band 0x2000) -ne 0 -or
            $reader.ReadUInt16() -ne 0x20b) { throw 'Expected a PE32+ executable, not a DLL.' }
    } finally { $reader.Dispose() }
}

function Get-PocService {
    # Exact fixed identity; query failure is NOT interpreted as service absence.
    Get-CimInstance -ClassName Win32_Service -Filter ("Name='" + $script:PocName + "'") -ErrorAction Stop
}

function Assert-NoReparsePath {
    param([Parameter(Mandatory)][string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing reparse point: $cursor"
            }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
}

function Assert-NoReparseTree {
    param([Parameter(Mandatory)][string]$Path)
    Assert-NoReparsePath $Path
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $stack = New-Object 'Collections.Generic.Stack[string]'
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $directory = New-Object IO.DirectoryInfo($stack.Pop())
        foreach ($item in $directory.EnumerateFileSystemInfos()) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing reparse point: $($item.FullName)"
            }
            if (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0) { $stack.Push($item.FullName) }
        }
    }
}

function Set-PocDirectoryAcl {
    param([string]$Path, [Security.Principal.SecurityIdentifier]$ServiceSid,
        [Security.AccessControl.FileSystemRights]$Rights)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $admin = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl.SetOwner($admin)
    foreach ($sid in @($admin, $system)) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        $ServiceSid, $Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Assert-PocFingerprint {
    param($Marker, $Service, $Paths)
    if ($Marker.Schema -ne 1 -or $Marker.ProjectId -cne $script:PocId -or
        $Marker.ServiceName -cne $script:PocName -or
        $Marker.BinaryRoot -ine $Paths.BinaryRoot -or $Marker.DataRoot -ine $Paths.DataRoot -or
        $Marker.Command -cne $Paths.Command -or $Marker.BinarySha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Ownership marker mismatch. Nothing is changed.'
    }
    if ($null -ne $Service -and ($Service.Name -cne $script:PocName -or
        $Service.PathName -cne $Paths.Command -or $Service.StartName -ine 'NT AUTHORITY\LocalService' -or
        $Service.ServiceType -ne 'Own Process' -or $Service.DesktopInteract)) {
        throw 'Existing service fingerprint differs. Nothing is changed.'
    }
}

function Assert-OwnedPoc {
    param($Paths)
    Assert-NoReparseTree $Paths.BinaryRoot
    Assert-NoReparseTree $Paths.DataRoot
    if (-not (Test-Path -LiteralPath $Paths.Marker -PathType Leaf)) {
        throw 'Trusted ownership marker is missing. Refusing stop/delete/cleanup.'
    }
    $marker = Get-Content -LiteralPath $Paths.Marker -Raw | ConvertFrom-Json
    $service = Get-PocService
    Assert-PocFingerprint $marker $service $Paths
    if ((Test-Path -LiteralPath $Paths.Binary) -and
        (Get-FileHash -LiteralPath $Paths.Binary -Algorithm SHA256).Hash -ine $marker.BinarySha256) {
        throw 'Installed binary hash differs. Refusing automated cleanup/control.'
    }
    $service
}

function Wait-PocState {
    param([string]$State, [int]$TimeoutSeconds = 20, [int]$SpecificExit = -1)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $service = Get-PocService
        if ($null -eq $service) { throw 'PoC service unexpectedly absent.' }
        if ($service.State -eq $State -and
            ($SpecificExit -lt 0 -or ($service.ExitCode -eq 1066 -and $service.ServiceSpecificExitCode -eq $SpecificExit))) {
            return $service
        }
        Start-Sleep -Milliseconds 250
    } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Timed out waiting for state=$State specific_exit=$SpecificExit; last=$($service.State) Win32=$($service.ExitCode) specific=$($service.ServiceSpecificExitCode)"
}
