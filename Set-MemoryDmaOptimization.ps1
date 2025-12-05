<#
  Set-MemoryDmaOptimization.ps1
  - Configure Windows memory management and PCIe/DMA optimization for gaming workloads.
  - Addresses TLB shootdown, standby list bloat, and PCIe completion timeout issues.
  - Supports modular configuration via parameter switches.
  - Designed for manual execution with detailed logging and WhatIf support.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$DisableMemoryCompression,
    [switch]$DisableSysMain,
    [switch]$DisableASPM,
    [switch]$ExtendPcieTimeout,
    [switch]$OptimizePowerPlan,
    [switch]$OptimizeNetwork,
    [switch]$DisableBackgroundServices,
    [switch]$InstallStandbyListTask,
    [switch]$All,
    [switch]$ShowCurrentConfig
)

$ErrorActionPreference = 'Continue'

#region Logging Functions

function Write-Info {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO ] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [OK   ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [WARN ] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta
}

#endregion

#region Utility Functions

function Assert-Administrator {
    # Verify script runs with elevated privileges.
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Err "This script requires Administrator privileges."
        Write-Err "Please run PowerShell as Administrator and try again."
        exit 1
    }
}

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Default = $null
    )
    try {
        $props = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties.Match($Name).Count -gt 0) {
            return $props.$Name
        }
    }
    catch { }
    return $Default
}

function Set-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )

    # Ensure parent key exists
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, "Create registry key")) {
            New-Item -Path $Path -Force | Out-Null
            Write-Info "Created registry key: $Path"
        }
    }

    $currentValue = Get-RegistryValue -Path $Path -Name $Name
    Write-Info "  Current: $Name = $currentValue"
    Write-Info "  Target:  $Name = $Value"

    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set registry value to $Value")) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Success "  Set $Name = $Value"
    }
}

#endregion

#region Memory Status Functions

function Get-MemoryStatus {
    # Get detailed memory status including standby list size.
    Write-Info "Querying memory status via performance counters..."

    $result = [ordered]@{}

    # Get total physical memory
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $result['TotalPhysicalMemoryMB'] = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $result['FreePhysicalMemoryMB'] = [math]::Round($os.FreePhysicalMemory / 1024)
    }
    catch {
        Write-Warn "Failed to get CIM memory info: $($_.Exception.Message)"
    }

    # Get performance counters
    $counters = @(
        '\Memory\Available MBytes',
        '\Memory\Standby Cache Normal Priority Bytes',
        '\Memory\Standby Cache Reserve Bytes',
        '\Memory\Modified Page List Bytes',
        '\Memory\Free & Zero Page List Bytes'
    )

    try {
        $samples = Get-Counter -Counter $counters -ErrorAction Stop
        foreach ($sample in $samples.CounterSamples) {
            $name = $sample.Path -replace '.*\\', ''
            if ($name -match 'Bytes$') {
                $result[$name] = [math]::Round($sample.CookedValue / 1MB, 2)
            }
            else {
                $result[$name] = [math]::Round($sample.CookedValue, 2)
            }
        }
    }
    catch {
        Write-Warn "Failed to get performance counters: $($_.Exception.Message)"
    }

    return $result
}

function Show-MemoryStatus {
    param([hashtable]$Status)

    Write-Host ""
    Write-Host "Memory Status:" -ForegroundColor White
    Write-Host ("-" * 50)

    foreach ($key in $Status.Keys) {
        $value = $Status[$key]
        $unit = if ($key -match 'Bytes$|MB$') { 'MB' } else { '' }
        Write-Host ("  {0,-40} : {1,10} {2}" -f $key, $value, $unit)
    }

    # Calculate standby percentage
    if ($Status['TotalPhysicalMemoryMB'] -and $Status['Standby Cache Normal Priority Bytes']) {
        $standbyTotal = $Status['Standby Cache Normal Priority Bytes']
        if ($Status['Standby Cache Reserve Bytes']) {
            $standbyTotal += $Status['Standby Cache Reserve Bytes']
        }
        $standbyPercent = [math]::Round(($standbyTotal / $Status['TotalPhysicalMemoryMB']) * 100, 1)
        Write-Host ""
        Write-Host ("  Standby List Percentage: {0}%" -f $standbyPercent) -ForegroundColor $(if ($standbyPercent -gt 60) { 'Yellow' } else { 'Green' })
    }

    Write-Host ("-" * 50)
}

#endregion

#region Current Configuration Display

function Show-CurrentConfiguration {
    Write-Section "Current System Configuration"

    # Memory Management
    Write-Host ""
    Write-Host "Memory Management:" -ForegroundColor White
    Write-Host ("-" * 50)

    $mmKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $mmValues = @('DisablePageCombining', 'LargeSystemCache', 'NonPagedPoolSize', 'NonPagedPoolQuota')
    foreach ($name in $mmValues) {
        $value = Get-RegistryValue -Path $mmKey -Name $name -Default '(not set)'
        Write-Host ("  {0,-30} : {1}" -f $name, $value)
    }

    # MMAgent status
    try {
        $mmAgent = Get-MMAgent -ErrorAction Stop
        Write-Host ""
        Write-Host "  MMAgent Status:"
        Write-Host ("    MemoryCompression          : {0}" -f $mmAgent.MemoryCompression)
        Write-Host ("    PageCombining              : {0}" -f $mmAgent.PageCombining)
    }
    catch {
        Write-Warn "  Failed to query MMAgent: $($_.Exception.Message)"
    }

    # PCIe/DMA
    Write-Host ""
    Write-Host "PCIe/DMA Configuration:" -ForegroundColor White
    Write-Host ("-" * 50)

    $pciKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\PnP\Pci'
    $pciValues = @('ASPMOptOut', 'CompletionTimeout')
    foreach ($name in $pciValues) {
        $value = Get-RegistryValue -Path $pciKey -Name $name -Default '(not set)'
        Write-Host ("  {0,-30} : {1}" -f $name, $value)
    }

    # Services
    Write-Host ""
    Write-Host "Service Status:" -ForegroundColor White
    Write-Host ("-" * 50)

    $services = @('SysMain', 'DiagTrack', 'WSearch')
    foreach ($svcName in $services) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Host ("  {0,-20} : Status={1,-10} StartType={2}" -f $svcName, $svc.Status, $svc.StartType)
        }
        else {
            Write-Host ("  {0,-20} : (not found)" -f $svcName)
        }
    }

    # Power Plan
    Write-Host ""
    Write-Host "Power Plan:" -ForegroundColor White
    Write-Host ("-" * 50)

    try {
        $activePlan = & powercfg /getactivescheme 2>&1
        Write-Host "  $activePlan"
    }
    catch {
        Write-Warn "  Failed to query power plan"
    }

    # Network Throttling
    Write-Host ""
    Write-Host "Network Configuration:" -ForegroundColor White
    Write-Host ("-" * 50)

    $netKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $netValues = @('NetworkThrottlingIndex', 'SystemResponsiveness')
    foreach ($name in $netValues) {
        $value = Get-RegistryValue -Path $netKey -Name $name -Default '(not set)'
        if ($value -eq 0xFFFFFFFF) { $value = "0xFFFFFFFF (disabled)" }
        Write-Host ("  {0,-30} : {1}" -f $name, $value)
    }

    # Memory Status
    Write-Host ""
    $memStatus = Get-MemoryStatus
    Show-MemoryStatus -Status $memStatus
}

#endregion

#region Optimization Functions

function Disable-MemoryCompressionFunc {
    Write-Section "Disabling Memory Compression"

    $memBefore = Get-MemoryStatus
    Write-Info "Memory status before:"
    Show-MemoryStatus -Status $memBefore

    # Method 1: MMAgent cmdlet
    Write-Info "Attempting to disable via Disable-MMAgent..."
    try {
        if ($PSCmdlet.ShouldProcess("MMAgent", "Disable MemoryCompression")) {
            Disable-MMAgent -MemoryCompression -ErrorAction Stop
            Write-Success "Memory compression disabled via MMAgent."
        }
    }
    catch {
        Write-Warn "MMAgent method failed: $($_.Exception.Message)"
        Write-Info "This may require a reboot to take effect."
    }

    # Method 2: Registry (DisablePageCombining)
    Write-Info "Setting registry fallback (DisablePageCombining)..."
    $mmKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-RegistryValueSafe -Path $mmKey -Name 'DisablePageCombining' -Value 1 -Type 'DWord'

    Write-Warn "A system reboot is required for memory compression changes to take full effect."
}

function Disable-SysMainFunc {
    Write-Section "Disabling SysMain (Superfetch) Service"

    $svc = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Warn "SysMain service not found on this system."
        return
    }

    Write-Info "Current SysMain status: $($svc.Status), StartType: $($svc.StartType)"

    if ($PSCmdlet.ShouldProcess("SysMain", "Stop and disable service")) {
        try {
            if ($svc.Status -eq 'Running') {
                Write-Info "Stopping SysMain service..."
                Stop-Service -Name 'SysMain' -Force -ErrorAction Stop
                Write-Success "SysMain service stopped."
            }

            Write-Info "Setting SysMain startup type to Disabled..."
            Set-Service -Name 'SysMain' -StartupType Disabled -ErrorAction Stop
            Write-Success "SysMain service disabled."
        }
        catch {
            Write-Err "Failed to disable SysMain: $($_.Exception.Message)"
        }
    }
}

function Disable-ASPMFunc {
    Write-Section "Disabling PCIe ASPM (Active State Power Management)"

    Write-Info "ASPM allows PCIe links to enter low-power states (L0s, L1)."
    Write-Info "Recovery from these states adds latency that can cause TLP timeouts."

    $pciKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\PnP\Pci'

    Write-Info "Setting ASPMOptOut=1 (global ASPM disable)..."
    Set-RegistryValueSafe -Path $pciKey -Name 'ASPMOptOut' -Value 1 -Type 'DWord'

    Write-Warn "A system reboot is required for ASPM changes to take effect."
}

function Extend-PcieTimeoutFunc {
    Write-Section "Extending PCIe Completion Timeout"

    Write-Info "PCIe Completion Timeout ranges:"
    Write-Info "  0x0 = Default (50us - 50ms)"
    Write-Info "  0x3 = 16ms - 55ms"
    Write-Info "  0x6 = 65ms - 210ms (recommended for DMA devices)"
    Write-Info "  0x9 = 260ms - 900ms"
    Write-Info "  0xA = 1s - 3.5s"

    $pciKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\PnP\Pci'
    $targetValue = 0x6  # 65ms-210ms range

    Write-Info "Setting CompletionTimeout=0x6 (65ms-210ms range)..."
    Set-RegistryValueSafe -Path $pciKey -Name 'CompletionTimeout' -Value $targetValue -Type 'DWord'

    Write-Warn "A system reboot is required for PCIe timeout changes to take effect."
}

function Optimize-PowerPlanFunc {
    Write-Section "Configuring Ultimate Performance Power Plan"

    if (-not $PSCmdlet.ShouldProcess("Power Plan", "Configure Ultimate Performance")) {
        return
    }

    # Try to duplicate Ultimate Performance plan
    $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    Write-Info "Attempting to unlock Ultimate Performance power plan..."

    $output = & powercfg -duplicatescheme $ultimateGuid 2>&1
    $newGuid = $null

    if ($output -match '([a-f0-9-]{36})') {
        $newGuid = $Matches[1]
        Write-Success "Ultimate Performance plan created: $newGuid"
    }
    else {
        Write-Warn "Ultimate Performance plan not available, using High Performance as fallback."
        $newGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    }

    # Activate the plan
    Write-Info "Activating power plan..."
    & powercfg -setactive $newGuid
    Write-Success "Power plan activated."

    # Configure processor power management
    Write-Info "Configuring processor power management (100% min/max)..."
    & powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
    & powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
    Write-Success "Processor throttling disabled."

    # Disable USB selective suspend
    Write-Info "Disabling USB selective suspend..."
    & powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    Write-Success "USB selective suspend disabled."

    # Disable PCI Express link state power management
    Write-Info "Disabling PCI Express link state power management..."
    & powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
    Write-Success "PCIe link state power management disabled."

    # Apply changes
    & powercfg -setactive SCHEME_CURRENT

    Write-Info "Current active power plan:"
    & powercfg /getactivescheme
}

function Optimize-NetworkFunc {
    Write-Section "Optimizing Network Stack"

    # Disable network throttling
    Write-Info "Disabling network throttling..."
    $mmSystemProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

    Set-RegistryValueSafe -Path $mmSystemProfile -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Type 'DWord'
    Set-RegistryValueSafe -Path $mmSystemProfile -Name 'SystemResponsiveness' -Value 0 -Type 'DWord'

    # Configure TCP parameters
    Write-Info "Configuring TCP parameters..."
    $tcpParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

    Set-RegistryValueSafe -Path $tcpParams -Name 'TcpTimedWaitDelay' -Value 30 -Type 'DWord'
    Set-RegistryValueSafe -Path $tcpParams -Name 'MaxUserPort' -Value 65534 -Type 'DWord'

    # Disable Nagle algorithm per interface
    Write-Info "Disabling Nagle algorithm on all network interfaces..."
    $interfacesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'

    if (Test-Path -LiteralPath $interfacesPath) {
        $interfaces = Get-ChildItem -Path $interfacesPath -ErrorAction SilentlyContinue
        $count = 0

        foreach ($iface in $interfaces) {
            if ($PSCmdlet.ShouldProcess($iface.PSChildName, "Disable Nagle algorithm")) {
                Set-ItemProperty -Path $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $iface.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                $count++
            }
        }

        Write-Success "Nagle algorithm disabled on $count interfaces."
    }
    else {
        Write-Warn "Network interfaces registry path not found."
    }

    Write-Warn "Some network changes may require a reboot to take effect."
}

function Disable-BackgroundServicesFunc {
    Write-Section "Disabling Background Services"

    $services = @(
        @{ Name = 'DiagTrack'; Description = 'Connected User Experiences and Telemetry' },
        @{ Name = 'WSearch'; Description = 'Windows Search Indexer' }
    )

    foreach ($svcInfo in $services) {
        $svcName = $svcInfo.Name
        $svcDesc = $svcInfo.Description

        Write-Info "Processing: $svcName ($svcDesc)"

        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Warn "  Service not found: $svcName"
            continue
        }

        Write-Info "  Current status: $($svc.Status), StartType: $($svc.StartType)"

        if ($PSCmdlet.ShouldProcess($svcName, "Stop and disable service")) {
            try {
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                    Write-Info "  Service stopped."
                }

                Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
                Write-Success "  Service disabled: $svcName"
            }
            catch {
                Write-Err "  Failed to disable $svcName : $($_.Exception.Message)"
            }
        }
    }
}

function Install-StandbyListTaskFunc {
    Write-Section "Installing Standby List Maintenance Task"

    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $maintenanceDir = Join-Path -Path $scriptDir -ChildPath 'StandbyListMaintenance'
    $clearScript = Join-Path -Path $maintenanceDir -ChildPath 'Clear-StandbyListGradual.ps1'

    if (-not (Test-Path -LiteralPath $clearScript)) {
        Write-Err "Standby list maintenance script not found at: $clearScript"
        Write-Err "Please ensure StandbyListMaintenance/Clear-StandbyListGradual.ps1 exists."
        return
    }

    $taskName = 'StandbyListMaintenance'
    $taskPath = '\CustomMaintenance\'

    Write-Info "Task Name: $taskPath$taskName"
    Write-Info "Script Path: $clearScript"
    Write-Info "Interval: 15 minutes"
    Write-Info "Trigger: Standby List > 60% of physical memory"

    if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", "Register scheduled task")) {
        return
    }

    # Remove existing task if present
    Write-Info "Removing existing task if present..."
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue

    # Create trigger (every 15 minutes)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)

    # Create action
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$clearScript`""

    # Create principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    # Create settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -Priority 7 `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    # Register task
    try {
        Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath `
            -Trigger $trigger -Action $action -Principal $principal -Settings $settings -Force | Out-Null

        Write-Success "Scheduled task registered: $taskPath$taskName"
        Write-Info "The task will run every 15 minutes and clear standby list if > 60% of RAM."
    }
    catch {
        Write-Err "Failed to register scheduled task: $($_.Exception.Message)"
    }
}

#endregion

#region Main Execution

# Verify administrator privileges
Assert-Administrator

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Memory Management & PCIe/DMA Optimization Script" -ForegroundColor Cyan
Write-Host "  For gaming workloads with DMA device support" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Show current configuration if requested
if ($ShowCurrentConfig) {
    Show-CurrentConfiguration
    exit 0
}

# Determine which optimizations to apply
$applyAll = $All.IsPresent
$anySelected = $DisableMemoryCompression -or $DisableSysMain -or $DisableASPM -or `
               $ExtendPcieTimeout -or $OptimizePowerPlan -or $OptimizeNetwork -or `
               $DisableBackgroundServices -or $InstallStandbyListTask

# NOTE: -InstallStandbyListTask is NOT included in -All to avoid anti-cheat detection.
# The scheduled task runs P/Invoke calls to ntdll.dll which may trigger anti-cheat systems.
# Users should manually run Clear-StandbyListGradual.ps1 before launching games if needed.

if (-not $applyAll -and -not $anySelected) {
    Write-Host "Usage: .\Set-MemoryDmaOptimization.ps1 [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options (safe for anti-cheat, included in -All):" -ForegroundColor White
    Write-Host "  -All                      Apply all safe optimizations (excludes scheduled task)"
    Write-Host "  -DisableMemoryCompression Disable Windows memory compression"
    Write-Host "  -DisableSysMain           Disable SysMain (Superfetch) service"
    Write-Host "  -DisableASPM              Disable PCIe Active State Power Management"
    Write-Host "  -ExtendPcieTimeout        Extend PCIe completion timeout (65ms-210ms)"
    Write-Host "  -OptimizePowerPlan        Configure Ultimate Performance power plan"
    Write-Host "  -OptimizeNetwork          Optimize network stack (disable Nagle, throttling)"
    Write-Host "  -DisableBackgroundServices Disable DiagTrack, WSearch services"
    Write-Host "  -ShowCurrentConfig        Display current system configuration"
    Write-Host "  -WhatIf                   Preview changes without applying"
    Write-Host ""
    Write-Host "Options (may trigger anti-cheat, NOT included in -All):" -ForegroundColor Red
    Write-Host "  -InstallStandbyListTask   Install scheduled task for standby list maintenance"
    Write-Host "                            WARNING: Uses P/Invoke to ntdll.dll, may be detected!"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\Set-MemoryDmaOptimization.ps1 -All -WhatIf"
    Write-Host "  .\Set-MemoryDmaOptimization.ps1 -All"
    Write-Host "  .\Set-MemoryDmaOptimization.ps1 -DisableASPM -ExtendPcieTimeout"
    Write-Host ""
    Write-Host "For Standby List clearing, run manually before gaming:" -ForegroundColor Cyan
    Write-Host "  .\StandbyListMaintenance\Clear-StandbyListGradual.ps1 -Force"
    Write-Host ""
    exit 0
}

# Show initial configuration
Write-Info "Gathering current system configuration..."
Show-CurrentConfiguration

# Apply selected optimizations
if ($applyAll -or $DisableMemoryCompression) {
    Disable-MemoryCompressionFunc
}

if ($applyAll -or $DisableSysMain) {
    Disable-SysMainFunc
}

if ($applyAll -or $DisableASPM) {
    Disable-ASPMFunc
}

if ($applyAll -or $ExtendPcieTimeout) {
    Extend-PcieTimeoutFunc
}

if ($applyAll -or $OptimizePowerPlan) {
    Optimize-PowerPlanFunc
}

if ($applyAll -or $OptimizeNetwork) {
    Optimize-NetworkFunc
}

if ($applyAll -or $DisableBackgroundServices) {
    Disable-BackgroundServicesFunc
}

# NOTE: InstallStandbyListTask is NOT included in -All to avoid anti-cheat detection.
# Only install if explicitly requested with -InstallStandbyListTask flag.
if ($InstallStandbyListTask) {
    Write-Warn "WARNING: Installing scheduled task may trigger anti-cheat detection!"
    Write-Warn "The task uses P/Invoke calls to ntdll.dll (NtSetSystemInformation)."
    Write-Warn "Consider running Clear-StandbyListGradual.ps1 manually before gaming instead."
    Install-StandbyListTaskFunc
}

# Summary
Write-Section "Summary"

Write-Host ""
Write-Host "Optimizations applied. Please note:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Some changes require a REBOOT to take effect:" -ForegroundColor Yellow
Write-Host "     - Memory compression settings"
Write-Host "     - ASPM settings"
Write-Host "     - PCIe completion timeout"
Write-Host ""
Write-Host "  2. Verify DMA device functionality after reboot." -ForegroundColor Yellow
Write-Host ""
Write-Host "  3. To view current configuration, run:" -ForegroundColor Cyan
Write-Host "     .\Set-MemoryDmaOptimization.ps1 -ShowCurrentConfig"
Write-Host ""

#endregion
