<#
  Register-StandbyListTask.ps1
  - Register a scheduled task for periodic standby list maintenance.
  - Task runs every 15 minutes as SYSTEM with highest privileges.
  - Executes Clear-StandbyListGradual.ps1 to conditionally clear standby list.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]$IntervalMinutes = 15,
    [string]$ScriptPath,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

#region Logging

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO ] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK   ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN ] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

#endregion

#region Main

# Task configuration
$taskName = 'StandbyListMaintenance'
$taskPath = '\CustomMaintenance\'
$taskFullPath = "$taskPath$taskName"

# Determine script path
if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ScriptPath = Join-Path -Path $scriptDir -ChildPath 'Clear-StandbyListGradual.ps1'
}

# Verify administrator privileges
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Err "This script requires Administrator privileges."
    exit 1
}

# Handle unregister
if ($Unregister) {
    Write-Info "Unregistering scheduled task: $taskFullPath"

    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($existingTask) {
        if ($PSCmdlet.ShouldProcess($taskFullPath, "Unregister scheduled task")) {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
            Write-Success "Scheduled task unregistered: $taskFullPath"
        }
    }
    else {
        Write-Warn "Scheduled task not found: $taskFullPath"
    }
    exit 0
}

# Verify script exists
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-Err "Maintenance script not found: $ScriptPath"
    exit 1
}

Write-Info "Registering Standby List Maintenance Task"
Write-Info "  Task Name:     $taskFullPath"
Write-Info "  Script Path:   $ScriptPath"
Write-Info "  Interval:      $IntervalMinutes minutes"
Write-Info "  Run As:        SYSTEM (highest privileges)"

# Remove existing task if present
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Info "Removing existing task..."
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
}

if (-not $PSCmdlet.ShouldProcess($taskFullPath, "Register scheduled task")) {
    exit 0
}

# Create trigger (repeating every N minutes, starting now)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

# Create action
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$ScriptPath`""

# Create principal (run as SYSTEM with highest privileges)
$principal = New-ScheduledTaskPrincipal `
    -UserId 'NT AUTHORITY\SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Create settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -Priority 7 `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

# Register task
try {
    $task = Register-ScheduledTask `
        -TaskName $taskName `
        -TaskPath $taskPath `
        -Trigger $trigger `
        -Action $action `
        -Principal $principal `
        -Settings $settings `
        -Force

    Write-Success "Scheduled task registered successfully!"
    Write-Info ""
    Write-Info "Task Details:"
    Write-Info "  State:         $($task.State)"
    Write-Info "  Next Run Time: $($task.NextRunTime)"
    Write-Info ""
    Write-Info "To manually run the task:"
    Write-Info "  Start-ScheduledTask -TaskPath '$taskPath' -TaskName '$taskName'"
    Write-Info ""
    Write-Info "To unregister the task:"
    Write-Info "  .\Register-StandbyListTask.ps1 -Unregister"
}
catch {
    Write-Err "Failed to register scheduled task: $($_.Exception.Message)"
    exit 1
}

#endregion
