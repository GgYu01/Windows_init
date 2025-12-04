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

$ErrorActionPreference = 'Stop'  # Fail fast inside each step; step wrapper catches.

function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO ] $Message"
}

function Write-LogWarn {
    param([string]$Message)
    Write-Warning "[WARN ] $Message"
}

function Write-LogError {
    param([string]$Message)
    Write-Error "[ERROR] $Message"
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
    $profilePath = $profile.CurrentUserAllHosts
    $profileDir = Split-Path -Path $profilePath -Parent

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
    # Relax execution policies for both CurrentUser and LocalMachine scopes.
    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force -ErrorAction Stop
        Write-LogInfo "Set Windows PowerShell execution policy: CurrentUser = Bypass."
    }
    catch {
        Write-LogError "Failed to set execution policy for CurrentUser: $($_.Exception.Message)"
    }

    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force -ErrorAction Stop
        Write-LogInfo "Set Windows PowerShell execution policy: LocalMachine = Bypass."
    }
    catch {
        Write-LogError "Failed to set execution policy for LocalMachine: $($_.Exception.Message)"
    }

    # Try to configure PowerShell 7 execution policies if available.
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

    $deps = Get-ChildItem -Path $kitRoot -Filter 'Microsoft.UI.Xaml.2.8_*_*.appx' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName

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

    if (-not $deps -or $deps.Count -eq 0) {
        Write-LogWarn "No Microsoft.UI.Xaml dependency packages found under '$kitRoot'; attempting installation without explicit dependencies."
    }

    # Provision for all future users, if possible.
    try {
        Write-LogInfo "Provisioning Windows Terminal as an Appx provisioned package (Online)..."
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

    # Ensure the current Administrator session has Windows Terminal installed.
    try {
        Write-LogInfo "Installing Windows Terminal for the current user via Add-AppxPackage..."
        Add-AppxPackage -Path $bundle.FullName `
                        -LicensePath $license.FullName `
                        -DependencyPath $deps `
                        -ErrorAction Stop | Out-Null

        Write-LogInfo "Windows Terminal Add-AppxPackage completed for current user."
    }
    catch {
        Write-LogError "Add-AppxPackage for Windows Terminal failed: $($_.Exception.Message)"
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
        'uuyc_4.8.0.exe',
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

    # Steam - standard silent install switch /S
    $steamExe = Join-Path -Path $payloadRoot -ChildPath 'SteamSetup.exe'
    if (Test-Path -LiteralPath $steamExe) {
        try {
            Write-LogInfo "Installing Steam from '$steamExe'..."
            $p = Start-Process -FilePath $steamExe -ArgumentList '/S' -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-LogInfo "Steam installation completed with exit code 0."
            }
            else {
                Write-LogError "Steam installer exited with code $($p.ExitCode)."
            }
        }
        catch {
            Write-LogError "Steam installation failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogWarn "Steam installer not found at '$steamExe'; skipping."
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

# Main orchestration

$desktopPath = Get-DesktopPath
$logPath     = Join-Path -Path $desktopPath -ChildPath ("FirstBoot-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

try {
    try {
        Start-Transcript -Path $logPath -Force | Out-Null
        Write-LogInfo "Transcript started at '$logPath'."
    }
    catch {
        Write-LogError "Failed to start transcript at '$logPath': $($_.Exception.Message)"
    }

    Invoke-Step -Name 'Confirm administrator token'        -Action { Confirm-AdministratorToken }
    Invoke-Step -Name 'Install PowerShell 7.5.4'           -Action { Install-PowerShell7 }
    Invoke-Step -Name 'Configure PowerShell defaults'          -Action { Configure-PowerShellDefaults }
    Invoke-Step -Name 'Set execution policies'                 -Action { Set-ExecutionPolicies }
    Invoke-Step -Name 'Install Windows Terminal'               -Action { Install-WindowsTerminal }
    Invoke-Step -Name 'Set Windows Terminal as default host'   -Action { Set-DefaultTerminalToWindowsTerminal }
    Invoke-Step -Name 'Configure Defender and firewall'        -Action { Configure-DefenderAndFirewall }
    Invoke-Step -Name 'Configure SmartScreen and UAC'          -Action { Configure-SmartScreenAndUac }
    Invoke-Step -Name 'Copy payloads to Downloads'             -Action { Copy-PayloadsToDownloads }
    Invoke-Step -Name 'Install core applications'              -Action { Install-Applications }
    Invoke-Step -Name 'Invoke user customization script'       -Action { Invoke-UserCustomizationScript }
}
finally {
    try {
        Stop-Transcript | Out-Null
        Write-LogInfo "Transcript stopped."
    }
    catch {
        # Ignore transcript shutdown errors.
    }
}
