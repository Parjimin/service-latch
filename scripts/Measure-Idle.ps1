#Requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(10,3600)][int]$Seconds = 600)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost -ReadOnly
$paths = Get-PocPaths
$service = Assert-OwnedPoc $paths
if ($null -eq $service -or $service.State -ne 'Running') { throw 'PoC must already be Running.' }
$workerId = [int]$service.ProcessId
$before = Get-Process -Id $workerId
$created = $before.StartTime.ToUniversalTime()
$cpuBefore = $before.TotalProcessorTime.TotalSeconds
$ioBefore = Get-CimInstance Win32_Process -Filter "ProcessId=$workerId"
$clock = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds $Seconds
$after = Get-Process -Id $workerId
$ioAfter = Get-CimInstance Win32_Process -Filter "ProcessId=$workerId"
$elapsed = $clock.Elapsed.TotalSeconds
$current = Get-PocService
if ($current.State -ne 'Running' -or $current.ProcessId -ne $workerId -or
    $after.StartTime.ToUniversalTime() -ne $created) { throw 'Worker restarted/stopped; measurement invalid.' }
[ordered]@{
    WorkerId=$workerId; StartTimeUtc=$created.ToString('o'); ElapsedSeconds=$elapsed
    LogicalProcessors=[Environment]::ProcessorCount
    CpuPercentOfMachine=(100.0 * ($after.TotalProcessorTime.TotalSeconds-$cpuBefore) / $elapsed / [Environment]::ProcessorCount)
    WorkingSetBytes=$after.WorkingSet64; PrivateBytes=$after.PrivateMemorySize64
    PeakWorkingSetBytes=$after.PeakWorkingSet64
    ProcessReadBytesDelta=([decimal]$ioAfter.ReadTransferCount-[decimal]$ioBefore.ReadTransferCount)
    ProcessWriteBytesDelta=([decimal]$ioAfter.WriteTransferCount-[decimal]$ioBefore.WriteTransferCount)
    Note='Process I/O counters are not physical-disk counters; measurement does not prove network traffic absence.'
} | ConvertTo-Json
