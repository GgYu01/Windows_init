<# 
  Root first-boot orchestration script.
  - Runs once at first Administrator logon.
  - Installs PowerShell 7.5.4 from local MSI.
  - Configures Windows PowerShell to forward interactive sessions to pwsh.
  - Applies system tweaks (Defender, firewall, SmartScreen, UAC, etc.).
  - Copies predefined payloads to Administrator Downloads.
  - Optionally executes an extra user customization script.
  - Writes a detailed transcript log to the desktop and never aborts setup.
#>

param(
    [ValidateSet('Normal', 'Probe')]
    [string]$Mode = 'Normal'
)

$ErrorActionPreference = 'Stop'  # Fail fast inside each step; step wrapper catches.

$script:EarlyLogPath = $null

function Write-EarlyFileLog {
    # Best-effort file log for diagnosing cases where transcript/desktop logging is not available.
    param(
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $script:EarlyLogPath) {
        return
    }

    try {
        $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
        Add-Content -Path $script:EarlyLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore logging failures.
    }
}

function Write-LogInfo {
    param([string]$Message)
    Write-EarlyFileLog -Level 'INFO' -Message $Message
    Write-Host "[INFO ] $Message"
}

function Write-LogWarn {
    param([string]$Message)
    Write-EarlyFileLog -Level 'WARN' -Message $Message
    Write-Warning "[WARN ] $Message"
}

function Write-LogError {
    param([string]$Message)
    Write-EarlyFileLog -Level 'ERROR' -Message $Message
    Write-Error "[ERROR] $Message" -ErrorAction Continue
}

function Get-RootPhase {
    # Retrieve current root.ps1 execution phase from registry (0 = initial, 1 = post-Defender-removal, 2 = completed).
    $key = 'HKLM:\SOFTWARE\WindowsInit'
    try {
        if (Test-Path -LiteralPath $key) {
            $props = Get-ItemProperty -Path $key -Name 'RootPhase' -ErrorAction SilentlyContinue
            if ($props -and $props.PSObject.Properties.Match('RootPhase').Count -gt 0) {
                $value = 0
                if ([int]::TryParse($props.RootPhase.ToString(), [ref]$value)) {
                    return $value
                }
                return [int]$props.RootPhase
            }
        }
    }
    catch {
        Write-LogError "Failed to read RootPhase from registry: $($_.Exception.Message)"
    }
    return 0
}

function Set-RootPhase {
    param([int]$Phase)
    $key = 'HKLM:\SOFTWARE\WindowsInit'
    try {
        if (-not (Test-Path -LiteralPath $key)) {
            New-Item -Path $key -Force | Out-Null
        }
        Set-ItemProperty -Path $key -Name 'RootPhase' -Value $Phase -Type DWord -Force
        Write-LogInfo ("RootPhase set to {0} in registry." -f $Phase)
    }
    catch {
        Write-LogError "Failed to set RootPhase in registry: $($_.Exception.Message)"
    }
}

function Register-RootPhase2RunOnce {
    # Register a RunOnce entry to invoke this script again for second-phase configuration.
    try {
        $runOnceKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
        if (-not (Test-Path -LiteralPath $runOnceKey)) {
            New-Item -Path $runOnceKey -Force | Out-Null
        }

        $scriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $PSScriptRoot }
        $loaderPath = Join-Path -Path $scriptRoot -ChildPath 'root.ps1'

        $command = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File `"$loaderPath`""
        Set-ItemProperty -Path $runOnceKey -Name 'WindowsInit-Phase2' -Value $command -Force

        Write-LogInfo "Registered RunOnce entry 'WindowsInit-Phase2' that replays the root.ps1 loader for phase 2."
    }
    catch {
        Write-LogError "Failed to register RunOnce for second-phase execution: $($_.Exception.Message)"
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-LogInfo "=== Step: $Name ==="
    try {
        & $Action
        Write-LogInfo "=== Step '$Name' completed ==="
    }
    catch {
        Write-LogError "Step '$Name' failed: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            Write-LogError $_.ScriptStackTrace
        }
    }
}

function Get-DesktopPath {
    # Resolve current user's desktop directory.
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
    }
    catch {
        $desktop = $null
    }

    if (-not $desktop) {
        $desktop = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop'
    }

    if (-not (Test-Path -LiteralPath $desktop)) {
        New-Item -Path $desktop -ItemType Directory -Force | Out-Null
    }

    return $desktop
}

function Get-DownloadsPath {
    # Resolve current user's downloads directory.
    $base = $null
    try {
        $base = [Environment]::GetFolderPath('UserProfile')
    }
    catch {
        $base = $null
    }

    if (-not $base) {
        $base = $env:USERPROFILE
    }

    $downloads = Join-Path -Path $base -ChildPath 'Downloads'

    if (-not (Test-Path -LiteralPath $downloads)) {
        New-Item -Path $downloads -ItemType Directory -Force | Out-Null
    }

    return $downloads
}

function Install-PowerShell7 {
    # Install PowerShell 7.5.4 from local MSI if not already installed.
    $existing = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) {
        Write-LogInfo "PowerShell 7 already present at '$($existing.Source)'; skipping MSI installation."
        return
    }

    $msiPath = 'C:\Windows\Setup\Scripts\PowerShell-7.5.4-win-x64.msi'
    if (-not (Test-Path -LiteralPath $msiPath)) {
        throw "MSI not found at '$msiPath'."
    }

    $arguments = "/i `"$msiPath`" /qn ADD_PATH=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1"
    Write-LogInfo "Installing PowerShell 7 from '$msiPath'..."

    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "msiexec exited with code $($process.ExitCode)."
    }

    Write-LogInfo "PowerShell 7 MSI installation finished with exit code 0."
}

function Configure-PowerShellDefaults {
    # Configure Windows PowerShell profile to forward interactive sessions to pwsh.
    $profileDir = Join-Path -Path $env:USERPROFILE -ChildPath 'Documents\WindowsPowerShell'
    $profilePath = Join-Path -Path $profileDir -ChildPath 'profile.ps1'

    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }

    $pwshTarget = Join-Path -Path ${env:ProgramFiles} -ChildPath 'PowerShell\7\pwsh.exe'

    $profileContent = @"
# Auto-forward interactive Windows PowerShell console to PowerShell 7
try {
    if (`$Host.Name -eq 'ConsoleHost') {
        `$pwsh = '$pwshTarget'
        if (Test-Path -LiteralPath `$pwsh) {
            Start-Process -FilePath `$pwsh -ArgumentList '-NoLogo' -WorkingDirectory `$PWD
            exit
        }
    }
}
catch {
    Write-Error "Profile forwarding to pwsh failed: `$($_.Exception.Message)"
}
"@

    $profileContent | Set-Content -Path $profilePath -Encoding UTF8
    Write-LogInfo "Configured Windows PowerShell profile to forward interactive sessions to PowerShell 7."
}

function Set-ExecutionPolicies {
    # Relax execution policies for both Windows PowerShell and PowerShell 7.
    $isPowerShell7 = $PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7
    $isMsixPackagedPwsh = $PSHOME -like '*WindowsApps*' -or $PSHOME -like '*Microsoft.PowerShell_*'

    # 1) Windows PowerShell (5.x) via powershell.exe to ensure down-level consoles are unblocked.
    $winPs = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($winPs) {
        try {
            & $winPs.Source -NoLogo -NonInteractive -Command `
                "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force; Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force"
            Write-LogInfo "Set Windows PowerShell execution policies to Bypass for CurrentUser and LocalMachine."
        }
        catch {
            Write-LogError "Failed to set Windows PowerShell execution policies via powershell.exe: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "powershell.exe not found while setting Windows PowerShell execution policies; skipping."
    }

    # 2) Current engine (typically PowerShell 7 when invoked via the loader).
    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force -ErrorAction Stop
        Write-LogInfo "Set current-engine execution policy: CurrentUser = Bypass."
    }
    catch {
        Write-LogError "Failed to set current-engine execution policy for CurrentUser: $($_.Exception.Message)"
    }

    if ($isMsixPackagedPwsh) {
        # MSIX packaged pwsh cannot write LocalMachine config inside WindowsApps; avoid noisy failures.
        Write-LogWarn "Current engine is MSIX packaged under WindowsApps; skipping LocalMachine execution policy to avoid access denials."
    }
    else {
        try {
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force -ErrorAction Stop
            Write-LogInfo "Set current-engine execution policy: LocalMachine = Bypass."
        }
        catch {
            Write-LogError "Failed to set current-engine execution policy for LocalMachine: $($_.Exception.Message)"
        }
    }

    # 3) If running from Windows PowerShell, also configure PowerShell 7 explicitly when present.
    if (-not $isPowerShell7) {
        $pwshCmd = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pwshCmd) {
            try {
                & $pwshCmd.Source -NoLogo -NonInteractive -Command `
                    "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force; Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force"
                Write-LogInfo "Set PowerShell 7 execution policies to Bypass for CurrentUser and LocalMachine."
            }
            catch {
                Write-LogError "Failed to set PowerShell 7 execution policies: $($_.Exception.Message)"
            }
        }
        else {
            Write-LogWarn "PowerShell 7 not found while setting execution policies; skipping PowerShell 7 policy configuration."
        }
    }
}

function Install-WindowsTerminal {
    # Install or provision Windows Terminal from a local preinstall kit.
    $kitRoot = 'C:\Windows\Setup\Scripts\WindowsTerminal'

    if (-not (Test-Path -LiteralPath $kitRoot)) {
        Write-LogWarn "Windows Terminal kit root '$kitRoot' not found; skipping Windows Terminal installation."
        return
    }

    try {
        $bundle  = Get-ChildItem -Path $kitRoot -Filter '*.msixbundle' -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        $bundle = $null
    }

    try {
        $license = Get-ChildItem -Path $kitRoot -Filter '*_License*.xml' -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        $license = $null
    }

    # Force array semantics to avoid FileInfo '+' FileInfo (op_Addition) when only one match exists.
    $xamlDeps = @(Get-ChildItem -Path $kitRoot -Filter 'Microsoft.UI.Xaml.2.8_*_*.appx' -ErrorAction SilentlyContinue)
    $vcDeps   = @(Get-ChildItem -Path $kitRoot -Filter 'Microsoft.VCLibs.*Desktop*_*.appx' -ErrorAction SilentlyContinue)
    $deps     = @((@($xamlDeps) + @($vcDeps)) | Select-Object -ExpandProperty FullName)

    if (-not $bundle) {
        Write-LogWarn "Windows Terminal bundle (*.msixbundle) not found under '$kitRoot'; skipping."
        return
    }

    if (-not $license) {
        Write-LogWarn "Windows Terminal license XML not found under '$kitRoot'; skipping."
        return
    }

    Write-LogInfo ("Windows Terminal bundle: '{0}'" -f $bundle.FullName)
    Write-LogInfo ("Windows Terminal license: '{0}'" -f $license.FullName)

    if (-not $xamlDeps -or $xamlDeps.Count -eq 0) {
        Write-LogWarn "Microsoft.UI.Xaml dependency missing in Windows Terminal kit; skipping to avoid online retrieval."
        return
    }

    if (-not $vcDeps -or $vcDeps.Count -eq 0) {
        Write-LogWarn "Microsoft.VCLibs.*Desktop dependency missing in Windows Terminal kit; skipping to avoid online retrieval."
        return
    }

    $appxApiAvailable = $false
    try {
        $null = [Windows.Management.Deployment.PackageManager]::new()
        $appxApiAvailable = $true
    }
    catch {
        Write-LogWarn "AppX deployment API unavailable on this build: $($_.Exception.Message); skipping Windows Terminal installation."
    }

    $addAppxCmd = Get-Command -Name 'Add-AppxPackage' -ErrorAction SilentlyContinue

    if (-not $appxApiAvailable -or -not $addAppxCmd) {
        Write-LogWarn "Add-AppxPackage/AppX stack not present; skipping Windows Terminal installation to avoid hangs."
        return
    }

    $installedForCurrentUser = $false

    # Install for current user first; provisioning is attempted only after a successful install.
    try {
        Write-LogInfo "Installing Windows Terminal for the current user via Add-AppxPackage (offline kit)..."
        $supportsLicensePath = $addAppxCmd -and $addAppxCmd.Parameters.ContainsKey('LicensePath')

        if ($supportsLicensePath -and $license) {
            Add-AppxPackage -Path $bundle.FullName `
                            -LicensePath $license.FullName `
                            -DependencyPath $deps `
                            -ErrorAction Stop | Out-Null
        }
        else {
            if (-not $supportsLicensePath) {
                Write-LogWarn "Add-AppxPackage on this system does not support -LicensePath; installing without license file."
            }

            Add-AppxPackage -Path $bundle.FullName `
                            -DependencyPath $deps `
                            -ErrorAction Stop | Out-Null
        }

        $installedForCurrentUser = $true
        Write-LogInfo "Windows Terminal Add-AppxPackage completed for current user."
    }
    catch {
        Write-LogError "Add-AppxPackage for Windows Terminal failed: $($_.Exception.Message)"
    }

    $addProvisionCmd = Get-Command -Name 'Add-AppxProvisionedPackage' -ErrorAction SilentlyContinue

    if (-not $addProvisionCmd) {
        Write-LogWarn "Add-AppxProvisionedPackage not available; skipping provisioning step."
        return
    }

    if (-not $installedForCurrentUser) {
        Write-LogWarn "Skipping provisioning because current-user installation did not complete successfully."
        return
    }

    if (-not $appxApiAvailable) {
        Write-LogWarn "AppX deployment API unavailable; cannot provision Windows Terminal for all users."
        return
    }

    try {
        Write-LogInfo "Provisioning Windows Terminal as an Appx provisioned package (offline kit)..."
        Add-AppxProvisionedPackage -Online `
            -PackagePath $bundle.FullName `
            -LicensePath $license.FullName `
            -DependencyPackagePath $deps `
            -ErrorAction Stop | Out-Null

        Write-LogInfo "Windows Terminal provisioned successfully."
    }
    catch {
        Write-LogError "Add-AppxProvisionedPackage for Windows Terminal failed: $($_.Exception.Message)"
    }
}

function Set-DefaultTerminalToWindowsTerminal {
    # Configure Windows Terminal as the default console host for the current user.
    try {
        $kitRoot   = 'C:\Windows\Setup\Scripts\WindowsTerminal'
        $aumidPath = Join-Path -Path $kitRoot -ChildPath 'AUMIDs.txt'
        $terminalAumid = $null

        if (Test-Path -LiteralPath $aumidPath) {
            $content = Get-Content -Path $aumidPath -ErrorAction Stop
            $terminalAumid = ($content | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()
        }

        if (-not $terminalAumid) {
            # Fallback to well-known AUMID if AUMIDs.txt is missing or empty.
            $terminalAumid = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App'
        }

        $consoleKey = 'HKCU:\Console\%%Startup'
        if (-not (Test-Path -LiteralPath $consoleKey)) {
            New-Item -Path $consoleKey -Force | Out-Null
        }

        Set-ItemProperty -Path $consoleKey -Name 'DelegationConsole'  -Value $terminalAumid -Force
        Set-ItemProperty -Path $consoleKey -Name 'DelegationTerminal' -Value $terminalAumid -Force

        Write-LogInfo "Default console host configured to Windows Terminal (AUMID='$terminalAumid')."
    }
    catch {
        Write-LogError "Failed to configure Windows Terminal as default host: $($_.Exception.Message)"
    }
}

function Configure-DefenderAndFirewall {
    # Disable Defender core protections and Windows Firewall profiles.
    Write-LogInfo "Configuring Microsoft Defender Antivirus preferences..."
    $mpCmdletsPresent = (Get-Command -Name 'Set-MpPreference' -ErrorAction SilentlyContinue) -and
                        (Get-Command -Name 'Add-MpPreference' -ErrorAction SilentlyContinue)

    if ($mpCmdletsPresent) {
        try {
            Set-MpPreference -DisableRealtimeMonitoring $true `
                             -DisableBlockAtFirstSeen $true `
                             -DisableIOAVProtection $true `
                             -DisableScriptScanning $true `
                             -MAPSReporting Disabled `
                             -SubmitSamplesConsent NeverSend `
                             -PUAProtection Disabled `
                             -ErrorAction Stop

            Write-LogInfo "Defender preferences updated."
        }
        catch {
            Write-LogError "Failed to set Defender preferences: $($_.Exception.Message)"
        }
    }
    else {
        # Defender module typically disappears after third-party remover; rely on policy keys only.
        Write-LogWarn "Defender cmdlets (Set-MpPreference/Add-MpPreference) are unavailable; skipping cmdlet calls and falling back to policy keys only."
    }

    # Try to hard-disable Defender via policy keys (best effort; may be ignored on newer builds).
    try {
        $wdPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
        if (-not (Test-Path -LiteralPath $wdPolicyKey)) {
            New-Item -Path $wdPolicyKey -Force | Out-Null
        }

        Set-ItemProperty -Path $wdPolicyKey -Name 'DisableAntiSpyware' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $wdPolicyKey -Name 'DisableAntiVirus'   -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        $rtpKey = Join-Path -Path $wdPolicyKey -ChildPath 'Real-Time Protection'
        if (-not (Test-Path -LiteralPath $rtpKey)) {
            New-Item -Path $rtpKey -Force | Out-Null
        }

        $rtpValues = @{
            DisableRealtimeMonitoring = 1
            DisableIOAVProtection     = 1
            DisableScriptScanning     = 1
            DisableBehaviorMonitoring = 1
        }

        foreach ($name in $rtpValues.Keys) {
            Set-ItemProperty -Path $rtpKey -Name $name -Value $rtpValues[$name] -Type DWord -Force -ErrorAction SilentlyContinue
        }

        Write-LogInfo "Windows Defender policy keys written (DisableAntiSpyware/DisableAntiVirus/Real-Time Protection)."
    }
    catch {
        Write-LogError "Failed to write Windows Defender policy keys: $($_.Exception.Message)"
    }

    # Add very broad exclusions so Defender does not touch our payloads or downloads.
    if ($mpCmdletsPresent) {
        try {
            $downloads = Get-DownloadsPath
            $exclusionPaths = @(
                'C:\Windows\Setup\Scripts',
                'C:\Windows\Setup\Scripts\Payloads',
                $downloads
            )

            Write-LogInfo ("Adding Defender exclusion paths: {0}" -f ($exclusionPaths -join '; '))
            Add-MpPreference -ExclusionPath $exclusionPaths -ErrorAction Stop

            $exclusionExtensions = @('exe', 'dll', 'sys')
            Write-LogInfo ("Adding Defender exclusion extensions: {0}" -f ($exclusionExtensions -join '; '))
            Add-MpPreference -ExclusionExtension $exclusionExtensions -ErrorAction Stop

            $exclusionProcesses = @('powershell.exe', 'pwsh.exe', 'msiexec.exe')
            Write-LogInfo ("Adding Defender exclusion processes: {0}" -f ($exclusionProcesses -join '; '))
            Add-MpPreference -ExclusionProcess $exclusionProcesses -ErrorAction Stop

            Write-LogInfo "Defender exclusions configured."
        }
        catch {
            Write-LogError "Failed to configure Defender exclusions: $($_.Exception.Message)"
        }
    }

    # Best-effort attempt to stop and disable the Defender service. This may be blocked by the OS / tamper protection.
    try {
        $defSvc = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
        if ($defSvc) {
            Write-LogInfo ("WinDefend service status before change: Status={0}, StartType={1}" -f $defSvc.Status, $defSvc.StartType)

            try {
                if ($defSvc.Status -eq 'Running') {
                    Write-LogInfo "Attempting to stop WinDefend service..."
                    Stop-Service -Name 'WinDefend' -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-LogWarn "Failed to stop WinDefend service: $($_.Exception.Message)"
            }

            try {
                Write-LogInfo "Attempting to set WinDefend startup type to Disabled..."
                Set-Service -Name 'WinDefend' -StartupType Disabled -ErrorAction SilentlyContinue
            }
            catch {
                Write-LogWarn "Failed to change WinDefend startup type: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-LogWarn "Failed to query WinDefend service: $($_.Exception.Message)"
    }

    if ($mpCmdletsPresent) {
        try {
            $mpPref = Get-MpPreference
            $mpStatus = Get-MpComputerStatus

            Write-LogInfo ("Defender preference snapshot: " +
                           "RealTimeProtectionEnabled={0}, BlockAtFirstSeen={1}, IOAVProtectionEnabled={2}, ScriptScanningEnabled={3}, MAPSReporting={4}, SubmitSamplesConsent={5}, PUAProtection={6}" -f
                           $mpPref.RealTimeProtectionEnabled,
                           $mpPref.BlockAtFirstSeen,
                           $mpPref.IOAVProtectionEnabled,
                           $mpPref.ScriptScanningEnabled,
                           $mpPref.MAPSReporting,
                           $mpPref.SubmitSamplesConsent,
                           $mpPref.PUAProtection)

            Write-LogInfo ("Defender computer status snapshot: RealTimeProtectionEnabled={0}, IsTamperProtected={1}" -f
                           $mpStatus.RealTimeProtectionEnabled,
                           $mpStatus.IsTamperProtected)
        }
        catch {
            Write-LogError "Failed to query Defender status: $($_.Exception.Message)"
        }
    }

    Write-LogInfo "Disabling all Windows Firewall profiles..."
    try {
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False -ErrorAction Stop
        Write-LogInfo "Firewall profiles disabled."
    }
    catch {
        Write-LogError "Failed to disable firewall profiles: $($_.Exception.Message)"
    }

    try {
        $profiles = Get-NetFirewallProfile | Select-Object -Property Name, Enabled
        foreach ($p in $profiles) {
            Write-LogInfo ("Firewall profile status: Name={0}, Enabled={1}" -f $p.Name, $p.Enabled)
        }
    }
    catch {
        Write-LogError "Failed to query firewall profile status: $($_.Exception.Message)"
    }
}

function Invoke-DefenderRemoverTool {
    # Optionally run external Windows Defender removal tool if present.
    # This integrates with https://github.com/ionuttbara/windows-defender-remover
    # when its Script_Run.bat (and related files) are placed under
    # C:\Windows\Setup\Scripts\DefenderRemover.

    $toolRoot   = 'C:\Windows\Setup\Scripts\DefenderRemover'
    $batPath    = Join-Path -Path $toolRoot -ChildPath 'Script_Run.bat'
    $exePath    = Join-Path -Path $toolRoot -ChildPath 'Defender.Remover.exe'

    if (Test-Path -LiteralPath $batPath) {
        try {
            Write-LogInfo "Running Defender Remover Script_Run.bat in silent mode with option 'Y' (full Defender removal)..."
            $proc = Start-Process -FilePath $batPath -ArgumentList 'y' -WorkingDirectory $toolRoot -Wait -PassThru
            Write-LogInfo ("Script_Run.bat exited with code {0}. System may have been scheduled for reboot." -f $proc.ExitCode)
        }
        catch {
            Write-LogError "Script_Run.bat execution failed: $($_.Exception.Message)"
        }
        return
    }

    if (Test-Path -LiteralPath $exePath) {
        try {
            Write-LogInfo "Script_Run.bat not found; attempting Defender.Remover.exe automation with '/r'..."
            $proc = Start-Process -FilePath $exePath -ArgumentList '/r' -WorkingDirectory $toolRoot -PassThru
            Write-LogInfo ("Defender.Remover.exe started with PID {0}. It may still prompt for confirmation depending on version." -f $proc.Id)
        }
        catch {
            Write-LogError "Defender.Remover.exe execution failed: $($_.Exception.Message)"
        }
        return
    }

    Write-LogInfo "No Defender Remover entry point (Script_Run.bat / Defender.Remover.exe) found under '$toolRoot'; skipping Defender removal."
}

function Configure-SmartScreenAndUac {
    # Disable SmartScreen and UAC prompts via registry.
    Write-LogInfo "Disabling SmartScreen for Explorer and Edge..."

    $explorerPath    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
    $edgePolicyPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    $systemPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\System"

    try {
        Set-ItemProperty -Path $explorerPath -Name "SmartScreenEnabled" -Value "Off" -ErrorAction Stop
        Write-LogInfo "Set Explorer SmartScreenEnabled=Off."
    }
    catch {
        Write-LogError "Failed to disable Explorer SmartScreen: $($_.Exception.Message)"
    }

    try {
        if (-not (Test-Path -LiteralPath $edgePolicyPath)) {
            New-Item -Path $edgePolicyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $edgePolicyPath -Name "SmartScreenEnabled" -Value 0 -Type DWord -ErrorAction Stop
        Write-LogInfo "Set Edge SmartScreenEnabled=0."
    }
    catch {
        Write-LogError "Failed to disable Edge SmartScreen: $($_.Exception.Message)"
    }

    try {
        if (-not (Test-Path -LiteralPath $systemPolicyPath)) {
            New-Item -Path $systemPolicyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $systemPolicyPath -Name "EnableSmartScreen" -Value 0 -Type DWord -ErrorAction Stop
        Write-LogInfo "Set System EnableSmartScreen=0."
    }
    catch {
        Write-LogError "Failed to disable system SmartScreen: $($_.Exception.Message)"
    }

    Write-LogInfo "Disabling UAC and elevation prompts..."

    $uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

    $uacValues = @{
        ConsentPromptBehaviorUser   = 0
        ConsentPromptBehaviorAdmin  = 0
        EnableInstallerDetection    = 0
        EnableVirtualization        = 0
        EnableSecureUIAPaths        = 0
        PromptOnSecureDesktop       = 0
        EnableLUA                   = 0
        FilterAdministratorToken    = 0
        EnableUIADesktopToggle      = 1
        ValidateAdminCodeSignatures = 0
    }

    foreach ($name in $uacValues.Keys) {
        try {
            Set-ItemProperty -Path $uacKey -Name $name -Value $uacValues[$name] -Type DWord -Force -ErrorAction Stop
            Write-LogInfo ("Set UAC policy: {0}={1}" -f $name, $uacValues[$name])
        }
        catch {
            Write-LogError ("Failed to set UAC policy '{0}': {1}" -f $name, $_.Exception.Message)
        }
    }
}

function Configure-MemoryAndDma {
    # Configure memory management and PCIe/DMA optimization.
    # Addresses TLB shootdown, standby list bloat, and PCIe completion timeout issues.
    # Errors are logged but do not abort the setup process.

    Write-LogInfo "Configuring memory and DMA optimization..."

    # 1. Disable Memory Compression via MMAgent
    try {
        Disable-MMAgent -MemoryCompression -ErrorAction Stop
        Write-LogInfo "Memory compression disabled via MMAgent."
    }
    catch {
        Write-LogWarn "Failed to disable memory compression via MMAgent: $($_.Exception.Message)"
    }

    # 2. Registry fallback for memory compression (DisablePageCombining)
    $mmKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    try {
        Set-ItemProperty -Path $mmKey -Name 'DisablePageCombining' -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-LogInfo "Set DisablePageCombining=1"
    }
    catch {
        Write-LogWarn "Failed to set DisablePageCombining: $($_.Exception.Message)"
    }

    # 3. Disable SysMain (Superfetch) service
    try {
        $svc = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name 'SysMain' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'SysMain' -StartupType Disabled -ErrorAction Stop
            Write-LogInfo "SysMain service disabled."
        }
    }
    catch {
        Write-LogWarn "Failed to disable SysMain: $($_.Exception.Message)"
    }

    # 4. Disable ASPM (PCIe Active State Power Management)
    $pciKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\PnP\Pci'
    try {
        if (-not (Test-Path -LiteralPath $pciKey)) {
            New-Item -Path $pciKey -Force | Out-Null
        }
        Set-ItemProperty -Path $pciKey -Name 'ASPMOptOut' -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-LogInfo "Set ASPMOptOut=1 (ASPM disabled)"
    }
    catch {
        Write-LogWarn "Failed to disable ASPM: $($_.Exception.Message)"
    }

    # 5. Extend PCIe Completion Timeout (0x6 = 65ms-210ms range)
    try {
        Set-ItemProperty -Path $pciKey -Name 'CompletionTimeout' -Value 0x6 -Type DWord -Force -ErrorAction Stop
        Write-LogInfo "Set PCIe CompletionTimeout=0x6 (65ms-210ms range)"
    }
    catch {
        Write-LogWarn "Failed to set PCIe CompletionTimeout: $($_.Exception.Message)"
    }

    # 6. Configure Ultimate Performance power plan
    try {
        $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        $output = & powercfg -duplicatescheme $ultimateGuid 2>&1

        if ($output -match '([a-f0-9-]{36})') {
            $newGuid = $Matches[1]
            & powercfg -setactive $newGuid
            Write-LogInfo "Activated Ultimate Performance power plan: $newGuid"
        }
        else {
            & powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            Write-LogInfo "Activated High Performance power plan (fallback)"
        }

        # Disable processor throttling
        & powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
        & powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

        # Disable USB selective suspend
        & powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0

        # Disable PCI Express link state power management
        & powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0

        & powercfg -setactive SCHEME_CURRENT
        Write-LogInfo "Power plan optimizations applied."
    }
    catch {
        Write-LogWarn "Failed to configure power plan: $($_.Exception.Message)"
    }

    # 7. Disable network throttling
    $mmSystemProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    try {
        Set-ItemProperty -Path $mmSystemProfile -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $mmSystemProfile -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-LogInfo "Network throttling disabled."
    }
    catch {
        Write-LogWarn "Failed to disable network throttling: $($_.Exception.Message)"
    }

    # 8. Configure TCP parameters
    $tcpParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    try {
        Set-ItemProperty -Path $tcpParams -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $tcpParams -Name 'MaxUserPort' -Value 65534 -Type DWord -Force -ErrorAction Stop
        Write-LogInfo "TCP parameters configured."
    }
    catch {
        Write-LogWarn "Failed to configure TCP parameters: $($_.Exception.Message)"
    }

    # 9. Disable Nagle algorithm on all network interfaces
    $interfacesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    try {
        if (Test-Path -LiteralPath $interfacesPath) {
            $interfaces = Get-ChildItem -Path $interfacesPath -ErrorAction SilentlyContinue
            foreach ($iface in $interfaces) {
                Set-ItemProperty -Path $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $iface.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
            Write-LogInfo "Nagle algorithm disabled on network interfaces."
        }
    }
    catch {
        Write-LogWarn "Failed to disable Nagle algorithm: $($_.Exception.Message)"
    }

    Write-LogInfo "Memory and DMA optimization configuration completed."
}

function Copy-PayloadsToDownloads {
    # Copy predefined payloads from setup scripts directory into Downloads.
    $payloadRoot   = 'C:\Windows\Setup\Scripts\Payloads'
    $downloadsPath = Get-DownloadsPath

    if (-not (Test-Path -LiteralPath $payloadRoot)) {
        Write-LogWarn "Payload root '$payloadRoot' does not exist; skipping payload copy."
        return
    }

    $items = @(
        'Defender_Control_2.1.0_Single',
        'Sunshine',
        '7z2501-x64.exe',
        '581.57-desktop-win10-win11-64bit-international-dch-whql.exe',
        'Kook_PC_Setup_v0.99.0.0.exe',
        'MSIAfterburner-64-4.6.5.exe',
        'QQ9.7.25.29411.exe',
        'Set-GpuDeviceDesc.ps1',
        'ShareX-17.1.0-setup.exe',
        'SteamSetup.exe',
        'uuyc_4.8.2.exe',
        'VC_redist.x64.exe',
        'VC_redist.x86.exe'
    )

    foreach ($name in $items) {
        $src = Join-Path -Path $payloadRoot -ChildPath $name
        $dst = Join-Path -Path $downloadsPath -ChildPath $name

        try {
            if (-not (Test-Path -LiteralPath $src)) {
                Write-LogWarn "Payload source not found: '$src'; skipping."
                continue
            }

            $item = Get-Item -LiteralPath $src -ErrorAction Stop
            if ($item.PSIsContainer) {
                Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction Stop
                Write-LogInfo "Copied directory payload '$name' to Downloads."
            }
            else {
                Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop
                Write-LogInfo "Copied file payload '$name' to Downloads."
            }
        }
        catch {
            Write-LogError "Failed to copy payload '$name' from '$src' to '$dst': $($_.Exception.Message)"
        }
    }
}

function Install-Applications {
    # Perform best-effort silent installations for selected applications.
    $payloadRoot = 'C:\Windows\Setup\Scripts\Payloads'

    if (-not (Test-Path -LiteralPath $payloadRoot)) {
        Write-LogWarn "Payload root '$payloadRoot' does not exist; skipping application installation."
        return
    }

    # Steam - standard silent install switch /S
    $steamExe = Join-Path -Path $payloadRoot -ChildPath 'SteamSetup.exe'
    if (Test-Path -LiteralPath $steamExe) {
        try {
            Write-LogInfo "Starting Steam silent installer in background from '$steamExe'..."
            $p = Start-Process -FilePath $steamExe -ArgumentList '/S' -PassThru
            if ($p -and $p.Id) {
                Write-LogInfo ("Steam installer started with PID {0}; not waiting for completion." -f $p.Id)
            }
            else {
                Write-LogWarn "Steam installer process handle not available; continuing without wait."
            }
        }
        catch {
            Write-LogError "Steam installation failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "Steam installer not found at '$steamExe'; skipping."
    }

    # 7-Zip (7z2501-x64.exe) - standard silent install switch /S
    $sevenZipExe = Join-Path -Path $payloadRoot -ChildPath '7z2501-x64.exe'
    if (Test-Path -LiteralPath $sevenZipExe) {
        try {
            Write-LogInfo "Installing 7-Zip from '$sevenZipExe'..."
            $p = Start-Process -FilePath $sevenZipExe -ArgumentList '/S' -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-LogInfo "7-Zip installation completed with exit code 0."
            }
            else {
                Write-LogError "7-Zip installer exited with code $($p.ExitCode)."
            }
        }
        catch {
            Write-LogError "7-Zip installation failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "7-Zip installer not found at '$sevenZipExe'; skipping."
    }

    # NVIDIA driver - silent, clean installation, driver only if supported by the package.
    $nvidiaExe = Join-Path -Path $payloadRoot -ChildPath '581.57-desktop-win10-win11-64bit-international-dch-whql.exe'
    if (Test-Path -LiteralPath $nvidiaExe) {
        try {
            Write-LogInfo "Installing NVIDIA driver from '$nvidiaExe' (silent, clean)..."

            # Commonly used NVIDIA installer arguments; component-level control may vary across releases.
            $nvidiaArgs = '-s -noreboot -clean'

            $p = Start-Process -FilePath $nvidiaExe -ArgumentList $nvidiaArgs -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-LogInfo "NVIDIA driver installer exited with code 0."
            }
            else {
                Write-LogError "NVIDIA driver installer exited with code $($p.ExitCode)."
            }
        }
        catch {
            Write-LogError "NVIDIA driver installation failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "NVIDIA driver installer not found at '$nvidiaExe'; skipping."
    }

    # Visual C++ Redistributable x64
    $vcRedistX64 = Join-Path -Path $payloadRoot -ChildPath 'VC_redist.x64.exe'
    if (Test-Path -LiteralPath $vcRedistX64) {
        try {
            Write-LogInfo "Installing Visual C++ Redistributable x64 from '$vcRedistX64'..."
            $args = '/install /quiet /norestart'
            $p = Start-Process -FilePath $vcRedistX64 -ArgumentList $args -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-LogInfo "Visual C++ Redistributable x64 installation completed with exit code 0."
            }
            else {
                Write-LogError "Visual C++ Redistributable x64 installer exited with code $($p.ExitCode)."
            }
        }
        catch {
            Write-LogError "Visual C++ Redistributable x64 installation failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "Visual C++ Redistributable x64 installer not found at '$vcRedistX64'; skipping."
    }

    # Visual C++ Redistributable x86
    $vcRedistX86 = Join-Path -Path $payloadRoot -ChildPath 'VC_redist.x86.exe'
    if (Test-Path -LiteralPath $vcRedistX86) {
        try {
            Write-LogInfo "Installing Visual C++ Redistributable x86 from '$vcRedistX86'..."
            $args = '/install /quiet /norestart'
            $p = Start-Process -FilePath $vcRedistX86 -ArgumentList $args -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-LogInfo "Visual C++ Redistributable x86 installation completed with exit code 0."
            }
            else {
                Write-LogError "Visual C++ Redistributable x86 installer exited with code $($p.ExitCode)."
            }
        }
        catch {
            Write-LogError "Visual C++ Redistributable x86 installation failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "Visual C++ Redistributable x86 installer not found at '$vcRedistX86'; skipping."
    }
}

function Invoke-UserCustomizationScript {
    # Optionally execute an extra user script; all errors are captured in the log.
    $userScript = 'C:\Windows\Setup\Scripts\UserCustomization.ps1'

    if (-not (Test-Path -LiteralPath $userScript)) {
        Write-LogInfo "User customization script '$userScript' not found; skipping."
        return
    }

    Write-LogInfo "Invoking user customization script '$userScript'..."
    try {
        & powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File $userScript
        Write-LogInfo "User customization script finished."
    }
    catch {
        Write-LogError "User customization script failed: $($_.Exception.Message)"
    }
}

function Confirm-AdministratorToken {
    # Log whether the current process has an elevated administrator token.
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            Write-LogInfo "Administrator privileges confirmed."
        }
        else {
            Write-LogWarn "Current process is NOT elevated; many configuration steps may fail."
        }
    }
    catch {
        Write-LogError "Failed to verify administrator token: $($_.Exception.Message)"
    }
}

function Start-RootTranscript {
    # Start transcript and return a flag indicating success for later cleanup.
    param([string]$Path)

    $started = $false
    try {
        Start-Transcript -Path $Path -Force | Out-Null
        $started = $true
        Write-LogInfo "Transcript started at '$Path'."
    }
    catch {
        Write-LogError "Failed to start transcript at '$Path': $($_.Exception.Message)"
    }

    return $started
}

function Stop-RootTranscript {
    # Stop transcript only when it was started; swallow shutdown errors.
    param([bool]$Started)

    if (-not $Started) {
        return
    }

    try {
        Stop-Transcript | Out-Null
        Write-LogInfo "Transcript stopped."
    }
    catch {
        # Ignore transcript shutdown errors.
    }
}

function Invoke-RootOrchestration {
    # Main entry point coordinating first-boot tasks and logging.
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logRoot = Join-Path -Path ($env:ProgramData ? $env:ProgramData : 'C:\ProgramData') -ChildPath 'WindowsInit\Logs'
    $null = New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction SilentlyContinue

    $script:EarlyLogPath = Join-Path -Path $logRoot -ChildPath ("WindowsInit-Early-{0}.log" -f $timestamp)
    Write-LogInfo ("Windows_init starting. EarlyLogPath='{0}'." -f $script:EarlyLogPath)

    $mutexName = 'Global\WindowsInit.RootOrchestration'
    $mutex = $null
    $mutexAcquired = $false
    try {
        # Prevent multiple auto-run triggers (FirstLogonCommands/RunOnce/etc.) from running in parallel.
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        $mutexAcquired = $mutex.WaitOne(0)
    }
    catch {
        Write-LogWarn "Failed to acquire mutex '$mutexName': $($_.Exception.Message); continuing without single-instance protection."
    }

    if ($mutex -and (-not $mutexAcquired)) {
        Write-LogWarn "Another Windows_init instance is already running; skipping this invocation."
        return
    }

    $transcriptPath = Join-Path -Path $logRoot -ChildPath ("FirstBoot-{0}.log" -f $timestamp)
    $transcriptStarted = Start-RootTranscript -Path $transcriptPath

    try {
        $rootPhase = Get-RootPhase
        Write-LogInfo ("Detected RootPhase={0}." -f $rootPhase)
        Write-LogInfo ("Execution mode: {0}." -f $Mode)

        if ($Mode -eq 'Probe') {
            # Probe mode: produce logs only, do not change the system.
            $phase0 = $null
            $phase2 = $null
            try {
                $runOnceKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
                $props = Get-ItemProperty -Path $runOnceKey -ErrorAction SilentlyContinue
                if ($props) {
                    $phase0 = $props.'WindowsInit-Phase0'
                    $phase2 = $props.'WindowsInit-Phase2'
                }
            }
            catch {
                # Ignore probe read errors.
            }

            Write-LogInfo ("RunOnce WindowsInit-Phase0: {0}" -f ($phase0 ? $phase0 : '<missing>'))
            Write-LogInfo ("RunOnce WindowsInit-Phase2: {0}" -f ($phase2 ? $phase2 : '<missing>'))
            Write-LogInfo "Probe mode completed; exiting without executing steps."
            return
        }

        if ($rootPhase -ge 2) {
            Write-LogInfo "RootPhase indicates configuration already completed; skipping."
            return
        }

        # Phase 0: first login after installation.
        # If the Defender Remover tool exists, only perform Defender-related actions, register phase-2 RunOnce, and let the tool reboot the system.
        if ($rootPhase -eq 0) {
            Invoke-Step -Name 'Confirm administrator token'   -Action { Confirm-AdministratorToken }
            Invoke-Step -Name 'Configure Defender and firewall'   -Action { Configure-DefenderAndFirewall }
            Invoke-Step -Name 'Configure SmartScreen and UAC'     -Action { Configure-SmartScreenAndUac }

            $toolRoot = 'C:\Windows\Setup\Scripts\DefenderRemover'
            $batPath  = Join-Path -Path $toolRoot -ChildPath 'Script_Run.bat'
            $exePath  = Join-Path -Path $toolRoot -ChildPath 'Defender.Remover.exe'
            $hasRemover = (Test-Path -LiteralPath $batPath) -or (Test-Path -LiteralPath $exePath)

            if ($hasRemover) {
                Invoke-Step -Name 'Register second-phase RunOnce' -Action { Register-RootPhase2RunOnce; Set-RootPhase 1 }
                Invoke-Step -Name 'Run Defender.Remover (optional)' -Action { Invoke-DefenderRemoverTool }

                Write-LogInfo "Phase 1 (Defender removal) invoked. System may reboot automatically; remaining configuration will run on next logon."
                return
            }

            Write-LogInfo "Defender Remover tool not found; proceeding with single-phase configuration in this session."
        }
        else {
            Write-LogInfo "Non-zero RootPhase detected; skipping dedicated Defender removal phase."
        }

        # Phase 1 or single-phase: execute the remaining system configuration and application installs.
        Invoke-Step -Name 'Install PowerShell 7.5.4'           -Action { Install-PowerShell7 }
        Invoke-Step -Name 'Configure PowerShell defaults'      -Action { Configure-PowerShellDefaults }
        Invoke-Step -Name 'Set execution policies'             -Action { Set-ExecutionPolicies }
        Invoke-Step -Name 'Install Windows Terminal'           -Action { Install-WindowsTerminal }
        Invoke-Step -Name 'Set Windows Terminal as default host' -Action { Set-DefaultTerminalToWindowsTerminal }
        Invoke-Step -Name 'Configure memory and DMA optimization' -Action { Configure-MemoryAndDma }
        Invoke-Step -Name 'Copy payloads to Downloads'         -Action { Copy-PayloadsToDownloads }
        Invoke-Step -Name 'Install core applications'          -Action { Install-Applications }
        Invoke-Step -Name 'Invoke user customization script'   -Action { Invoke-UserCustomizationScript }

        if ($Mode -ne 'Probe' -and $rootPhase -lt 2) {
            Set-RootPhase 2
        }
    }
    catch {
        Write-LogError "Unhandled error in root orchestration: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            Write-LogError $_.ScriptStackTrace
        }
    }
    finally {
        Stop-RootTranscript -Started $transcriptStarted

        # Always try to surface logs to desktops for fast debugging.
        $publicDebug = 'C:\Users\Public\Desktop\WindowsInit-Debug'
        $null = New-Item -Path $publicDebug -ItemType Directory -Force -ErrorAction SilentlyContinue

        try {
            if (Test-Path -LiteralPath $script:EarlyLogPath) {
                Copy-Item -Path $script:EarlyLogPath -Destination (Join-Path -Path $publicDebug -ChildPath (Split-Path -Leaf $script:EarlyLogPath)) -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Ignore desktop copy failures.
        }

        try {
            if (Test-Path -LiteralPath $transcriptPath) {
                Copy-Item -Path $transcriptPath -Destination (Join-Path -Path $publicDebug -ChildPath (Split-Path -Leaf $transcriptPath)) -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Ignore desktop copy failures.
        }

        try {
            $desktopPath = Get-DesktopPath
            if (Test-Path -LiteralPath $transcriptPath) {
                Copy-Item -Path $transcriptPath -Destination (Join-Path -Path $desktopPath -ChildPath (Split-Path -Leaf $transcriptPath)) -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Ignore desktop copy failures.
        }

        if ($mutex -and $mutexAcquired) {
            try { $mutex.ReleaseMutex() } catch { }
        }

        if ($mutex) {
            $mutex.Dispose()
        }
    }
}

Invoke-RootOrchestration
