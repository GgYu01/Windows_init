<#
  Diagnostics helper for Windows_init.
  - Collects autorun trigger state and file presence.
  - Optionally registers a non-invasive RunOnce probe (does not run installers).
#>

param(
    [ValidateSet('Machine', 'User')]
    [string]$Scope = 'Machine',

    [ValidateSet('Bootstrap', 'Chain')]
    [string]$ProbeMode = 'Bootstrap',

    [switch]$RegisterProbe,
    [switch]$ClearProbe
)

$ErrorActionPreference = 'Stop'

function Initialize-DiagnosticsLogging {
    # Write logs to multiple stable locations for troubleshooting.
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targets = @()

    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $logRoot = Join-Path -Path $programData -ChildPath 'WindowsInit\Logs'
    $null = New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction SilentlyContinue
    $targets += (Join-Path -Path $logRoot -ChildPath ("Diagnostics-{0}.log" -f $timestamp))

    $publicRoot = if ($env:PUBLIC) { $env:PUBLIC } else { 'C:\Users\Public' }
    $publicDesktop = Join-Path -Path $publicRoot -ChildPath 'Desktop'
    $publicDebug = Join-Path -Path $publicDesktop -ChildPath 'WindowsInit-Debug'
    $null = New-Item -Path $publicDebug -ItemType Directory -Force -ErrorAction SilentlyContinue
    $targets += (Join-Path -Path $publicDebug -ChildPath ("Diagnostics-{0}.log" -f $timestamp))

    $userDesktop = $null
    try { $userDesktop = [Environment]::GetFolderPath('Desktop') } catch { $userDesktop = $null }
    if (-not $userDesktop -and $env:USERPROFILE) {
        $userDesktop = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop'
    }

    if ($userDesktop) {
        $null = New-Item -Path $userDesktop -ItemType Directory -Force -ErrorAction SilentlyContinue
        $targets += (Join-Path -Path $userDesktop -ChildPath ("Diagnostics-{0}.log" -f $timestamp))
    }

    return $targets
}

function Write-DiagnosticsLog {
    param(
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string[]]$Targets
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    foreach ($path in $Targets) {
        try {
            Add-Content -Path $path -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore logging failures.
        }
    }
}

function Format-OptionalValue {
    param([object]$Value)
    if ($null -eq $Value -or ($Value -is [string] -and $Value.Length -eq 0)) {
        return '<missing>'
    }
    return $Value
}

function Get-RootPhase {
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
        # Treat failures as 0.
    }
    return 0
}

function Get-RunOnceValue {
    param(
        [Parameter(Mandatory = $true)][string]$Hive,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $key = if ($Hive -eq 'HKCU') { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' } else { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    try {
        $props = Get-ItemProperty -Path $key -Name $Name -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties.Match($Name).Count -gt 0) {
            return $props.$Name
        }
    }
    catch {
        # Ignore.
    }
    return $null
}

function Set-RunOnceValue {
    param(
        [Parameter(Mandatory = $true)][string]$Hive,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $key = if ($Hive -eq 'HKCU') { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' } else { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    if (-not (Test-Path -LiteralPath $key)) {
        New-Item -Path $key -Force | Out-Null
    }

    Set-ItemProperty -Path $key -Name $Name -Value $Value -Force
}

function Remove-RunOnceValue {
    param(
        [Parameter(Mandatory = $true)][string]$Hive,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $key = if ($Hive -eq 'HKCU') { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' } else { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    try {
        Remove-ItemProperty -Path $key -Name $Name -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore.
    }
}

$logTargets = Initialize-DiagnosticsLogging
Write-DiagnosticsLog -Level 'INFO' -Message 'WindowsInitDiagnostics started.' -Targets $logTargets
Write-DiagnosticsLog -Level 'INFO' -Message ("User='{0}\\{1}', PID={2}, PSVersion={3}, Scope={4}, ProbeMode={5}" -f $env:USERDOMAIN, $env:USERNAME, $PID, $PSVersionTable.PSVersion, $Scope, $ProbeMode) -Targets $logTargets

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
Write-DiagnosticsLog -Level 'INFO' -Message ("ScriptRoot='{0}'" -f $scriptRoot) -Targets $logTargets

$expectedFiles = @(
    'root.ps1',
    'root.core.ps1',
    'SetupComplete.cmd',
    'FirstLogonBootstrap.ps1',
    'WindowsInitDiagnostics.ps1'
)
foreach ($name in $expectedFiles) {
    $path = Join-Path -Path $scriptRoot -ChildPath $name
    $exists = Test-Path -LiteralPath $path
    Write-DiagnosticsLog -Level 'INFO' -Message ("File '{0}': exists={1} path='{2}'" -f $name, $exists, $path) -Targets $logTargets
}

$installerRoots = @(
    $scriptRoot,
    (Join-Path -Path $scriptRoot -ChildPath 'Payloads'),
    'C:\Windows\Setup\Scripts',
    'C:\Windows\Setup\Scripts\Payloads'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$pwshInstallerPatterns = @('PowerShell-*-win-x64*.msi', 'PowerShell-*-win-x64*.zip')
$pwshInstallers = @()
foreach ($root in $installerRoots) {
    foreach ($pattern in $pwshInstallerPatterns) {
        $pwshInstallers += Get-ChildItem -Path $root -Filter $pattern -File -ErrorAction SilentlyContinue
    }
}

if ($pwshInstallers.Count -eq 0) {
    Write-DiagnosticsLog -Level 'WARN' -Message 'No PowerShell offline installer was discovered (msi/zip).' -Targets $logTargets
}
else {
    foreach ($item in ($pwshInstallers | Sort-Object -Property FullName -Unique)) {
        Write-DiagnosticsLog -Level 'INFO' -Message ("PowerShell installer candidate: {0}" -f $item.FullName) -Targets $logTargets
    }
}

$pwshCandidates = @()
if ($env:ProgramFiles) { $pwshCandidates += (Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\\7\\pwsh.exe') }
if ($env:ProgramW6432) { $pwshCandidates += (Join-Path -Path $env:ProgramW6432 -ChildPath 'PowerShell\\7\\pwsh.exe') }
if ($env:LOCALAPPDATA) { $pwshCandidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\\WindowsApps\\pwsh.exe') }

foreach ($path in ($pwshCandidates | Where-Object { $_ } | Select-Object -Unique)) {
    $exists = Test-Path -LiteralPath $path
    Write-DiagnosticsLog -Level 'INFO' -Message ("pwsh candidate: exists={0} path='{1}'" -f $exists, $path) -Targets $logTargets
}

$rootPhase = Get-RootPhase
Write-DiagnosticsLog -Level 'INFO' -Message ("RootPhase={0}" -f $rootPhase) -Targets $logTargets

$phase0 = Get-RunOnceValue -Hive 'HKLM' -Name 'WindowsInit-Phase0'
$phase2 = Get-RunOnceValue -Hive 'HKLM' -Name 'WindowsInit-Phase2'
Write-DiagnosticsLog -Level 'INFO' -Message ("HKLM RunOnce WindowsInit-Phase0: {0}" -f (Format-OptionalValue -Value $phase0)) -Targets $logTargets
Write-DiagnosticsLog -Level 'INFO' -Message ("HKLM RunOnce WindowsInit-Phase2: {0}" -f (Format-OptionalValue -Value $phase2)) -Targets $logTargets

$probeHive = if ($Scope -eq 'User') { 'HKCU' } else { 'HKLM' }
$probeName = 'WindowsInit-Probe'
$probeValue = Get-RunOnceValue -Hive $probeHive -Name $probeName
Write-DiagnosticsLog -Level 'INFO' -Message ("{0} RunOnce {1}: {2}" -f $probeHive, $probeName, (Format-OptionalValue -Value $probeValue)) -Targets $logTargets

$bootstrapPath = Join-Path -Path $scriptRoot -ChildPath 'FirstLogonBootstrap.ps1'
if ($ProbeMode -eq 'Chain') {
    $probeCmd = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File `"$bootstrapPath`" -ProbeChain"
}
else {
    $probeCmd = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File `"$bootstrapPath`" -Probe"
}

if ($ClearProbe) {
    Remove-RunOnceValue -Hive $probeHive -Name $probeName
    Write-DiagnosticsLog -Level 'INFO' -Message ("Cleared probe RunOnce: {0}\\...\\RunOnce\\{1}" -f $probeHive, $probeName) -Targets $logTargets
}

if ($RegisterProbe) {
    Set-RunOnceValue -Hive $probeHive -Name $probeName -Value $probeCmd
    Write-DiagnosticsLog -Level 'INFO' -Message ("Registered probe RunOnce: {0}\\...\\RunOnce\\{1}" -f $probeHive, $probeName) -Targets $logTargets
    Write-DiagnosticsLog -Level 'INFO' -Message ("Probe command: {0}" -f $probeCmd) -Targets $logTargets
}

Write-DiagnosticsLog -Level 'INFO' -Message 'WindowsInitDiagnostics completed.' -Targets $logTargets
