<#
  Clear-StandbyListGradual.ps1
  - Periodically clear standby list when threshold exceeded.
  - Uses P/Invoke NtSetSystemInformation for native API access.
  - Only clears Standby List (MemoryPurgeStandbyList=4), safe for DMA devices.
  - Designed for scheduled task execution (every 15 minutes).

  Safety guarantees:
  - Only purges Standby List, not Modified List, Working Sets, or Zero Page List
  - Locked pages (DMA buffers with MDL) are NEVER in Standby List
  - Threshold-based trigger prevents unnecessary clearing
#>

[CmdletBinding()]
param(
    [int]$ThresholdPercent = 60,
    [switch]$Force,
    [switch]$Verbose
)

$ErrorActionPreference = 'SilentlyContinue'

#region Logging

$LogFile = Join-Path -Path $env:TEMP -ChildPath 'StandbyListMaintenance.log'

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] [$Level] $Message"

    # Write to log file
    Add-Content -Path $LogFile -Value $logLine -ErrorAction SilentlyContinue

    # Write to console if verbose
    if ($VerbosePreference -eq 'Continue' -or $Verbose) {
        switch ($Level) {
            'INFO'  { Write-Host $logLine -ForegroundColor Cyan }
            'WARN'  { Write-Host $logLine -ForegroundColor Yellow }
            'ERROR' { Write-Host $logLine -ForegroundColor Red }
            'OK'    { Write-Host $logLine -ForegroundColor Green }
            default { Write-Host $logLine }
        }
    }
}

#endregion

#region P/Invoke Definition

# Define NtSetSystemInformation P/Invoke signature
$MemoryPurgeSignature = @'
[DllImport("ntdll.dll", SetLastError = true)]
public static extern int NtSetSystemInformation(
    int SystemInformationClass,
    IntPtr SystemInformation,
    int SystemInformationLength
);
'@

# Add type if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'Win32.MemoryPurge').Type) {
    try {
        Add-Type -MemberDefinition $MemoryPurgeSignature -Name 'MemoryPurge' -Namespace 'Win32' -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to add P/Invoke type: $($_.Exception.Message)" -Level 'ERROR'
        exit 1
    }
}

# Constants for NtSetSystemInformation
# SystemMemoryListInformation = 80
# MemoryPurgeStandbyList = 4 (ONLY purges standby list - safe for DMA)
$SYSTEM_MEMORY_LIST_INFORMATION = 80
$MEMORY_PURGE_STANDBY_LIST = 4

#endregion

#region Memory Functions

function Get-StandbyListInfo {
    # Get standby list size and percentage using performance counters.
    $result = @{
        TotalPhysicalMB = 0
        StandbyMB = 0
        StandbyPercent = 0
        FreeMB = 0
        AvailableMB = 0
    }

    try {
        # Get total physical memory
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $result.TotalPhysicalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $result.FreeMB = [math]::Round($os.FreePhysicalMemory / 1024)
    }
    catch {
        Write-Log "Failed to get CIM memory info: $($_.Exception.Message)" -Level 'WARN'
        return $null
    }

    # Get standby list size from performance counters
    try {
        $counters = @(
            '\Memory\Standby Cache Normal Priority Bytes',
            '\Memory\Standby Cache Reserve Bytes',
            '\Memory\Available MBytes'
        )

        $samples = Get-Counter -Counter $counters -ErrorAction Stop

        $standbyNormal = 0
        $standbyReserve = 0

        foreach ($sample in $samples.CounterSamples) {
            $path = $sample.Path
            $value = $sample.CookedValue

            if ($path -match 'Standby Cache Normal Priority Bytes') {
                $standbyNormal = $value
            }
            elseif ($path -match 'Standby Cache Reserve Bytes') {
                $standbyReserve = $value
            }
            elseif ($path -match 'Available MBytes') {
                $result.AvailableMB = [math]::Round($value)
            }
        }

        $result.StandbyMB = [math]::Round(($standbyNormal + $standbyReserve) / 1MB)
        $result.StandbyPercent = [math]::Round(($result.StandbyMB / $result.TotalPhysicalMB) * 100, 1)
    }
    catch {
        Write-Log "Failed to get performance counters: $($_.Exception.Message)" -Level 'WARN'
        return $null
    }

    return $result
}

function Clear-StandbyList {
    # Purge standby list using NtSetSystemInformation.
    # This is safe for DMA devices as locked pages (MDL) are not in standby list.

    Write-Log "Executing NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList)..."

    $commandValue = $MEMORY_PURGE_STANDBY_LIST
    $gcHandle = $null

    try {
        # Allocate pinned memory for the command value
        $gcHandle = [System.Runtime.InteropServices.GCHandle]::Alloc(
            $commandValue,
            [System.Runtime.InteropServices.GCHandleType]::Pinned
        )

        $ptr = $gcHandle.AddrOfPinnedObject()
        $size = [System.Runtime.InteropServices.Marshal]::SizeOf($commandValue)

        # Call NtSetSystemInformation
        $result = [Win32.MemoryPurge]::NtSetSystemInformation(
            $SYSTEM_MEMORY_LIST_INFORMATION,
            $ptr,
            $size
        )

        if ($result -eq 0) {
            Write-Log "NtSetSystemInformation succeeded (NTSTATUS=0)" -Level 'OK'
            return $true
        }
        else {
            # Convert NTSTATUS to hex for logging
            $statusHex = "0x{0:X8}" -f $result
            Write-Log "NtSetSystemInformation returned NTSTATUS: $statusHex" -Level 'WARN'

            # Common NTSTATUS codes
            switch ($result) {
                0xC0000022 { Write-Log "  STATUS_ACCESS_DENIED - Run as Administrator/SYSTEM" -Level 'ERROR' }
                0xC000000D { Write-Log "  STATUS_INVALID_PARAMETER" -Level 'ERROR' }
                0xC0000008 { Write-Log "  STATUS_INVALID_HANDLE" -Level 'ERROR' }
            }

            return $false
        }
    }
    catch {
        Write-Log "Exception during NtSetSystemInformation: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
    finally {
        if ($gcHandle -ne $null -and $gcHandle.IsAllocated) {
            $gcHandle.Free()
        }
    }
}

#endregion

#region Main Execution

Write-Log "========== Standby List Maintenance Started =========="
Write-Log "Threshold: $ThresholdPercent%, Force: $Force"

# Get current memory status
$memInfo = Get-StandbyListInfo

if ($null -eq $memInfo) {
    Write-Log "Failed to retrieve memory information. Exiting." -Level 'ERROR'
    exit 1
}

Write-Log "Memory Status:"
Write-Log "  Total Physical: $($memInfo.TotalPhysicalMB) MB"
Write-Log "  Standby List:   $($memInfo.StandbyMB) MB ($($memInfo.StandbyPercent)%)"
Write-Log "  Available:      $($memInfo.AvailableMB) MB"
Write-Log "  Free:           $($memInfo.FreeMB) MB"

# Check if clearing is needed
$shouldClear = $Force -or ($memInfo.StandbyPercent -gt $ThresholdPercent)

if (-not $shouldClear) {
    Write-Log "Standby list ($($memInfo.StandbyPercent)%) is below threshold ($ThresholdPercent%). No action needed."
    Write-Log "========== Standby List Maintenance Completed =========="
    exit 0
}

if ($Force) {
    Write-Log "Force flag set. Proceeding with standby list clear."
}
else {
    Write-Log "Standby list ($($memInfo.StandbyPercent)%) exceeds threshold ($ThresholdPercent%). Clearing..."
}

# Clear standby list
$success = Clear-StandbyList

if ($success) {
    # Get post-clear memory status
    Start-Sleep -Milliseconds 500  # Brief delay for counters to update
    $memInfoAfter = Get-StandbyListInfo

    if ($null -ne $memInfoAfter) {
        $freedMB = $memInfo.StandbyMB - $memInfoAfter.StandbyMB
        Write-Log "Memory Status After Clear:"
        Write-Log "  Standby List:   $($memInfoAfter.StandbyMB) MB ($($memInfoAfter.StandbyPercent)%)"
        Write-Log "  Available:      $($memInfoAfter.AvailableMB) MB"
        Write-Log "  Freed:          $freedMB MB"
    }

    Write-Log "Standby list cleared successfully." -Level 'OK'
}
else {
    Write-Log "Failed to clear standby list." -Level 'ERROR'
}

Write-Log "========== Standby List Maintenance Completed =========="

#endregion
