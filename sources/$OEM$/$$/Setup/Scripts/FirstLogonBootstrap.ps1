<#
  First-logon bootstrapper for Windows_init.
  - Used by SetupComplete.cmd (RunOnce) as a fallback trigger.
  - Avoids running Phase1 early when Phase2 RunOnce is pending (RootPhase=1).
#>

param(
    [switch]$Probe,
    [switch]$ProbeChain
)

$ErrorActionPreference = 'Stop'

function Initialize-BootstrapLogging {
    # Write early logs to multiple stable locations for troubleshooting.
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targets = @()

    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $logRoot = Join-Path -Path $programData -ChildPath 'WindowsInit\Logs'
    $null = New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction SilentlyContinue
    $targets += (Join-Path -Path $logRoot -ChildPath ("FirstLogonBootstrap-{0}.log" -f $timestamp))

    $publicRoot = if ($env:PUBLIC) { $env:PUBLIC } else { 'C:\Users\Public' }
    $publicDesktop = Join-Path -Path $publicRoot -ChildPath 'Desktop'
    $publicDebug = Join-Path -Path $publicDesktop -ChildPath 'WindowsInit-Debug'
    $null = New-Item -Path $publicDebug -ItemType Directory -Force -ErrorAction SilentlyContinue
    $targets += (Join-Path -Path $publicDebug -ChildPath ("FirstLogonBootstrap-{0}.log" -f $timestamp))

    $userDesktop = $null
    try { $userDesktop = [Environment]::GetFolderPath('Desktop') } catch { $userDesktop = $null }
    if (-not $userDesktop -and $env:USERPROFILE) {
        $userDesktop = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop'
    }

    if ($userDesktop) {
        $null = New-Item -Path $userDesktop -ItemType Directory -Force -ErrorAction SilentlyContinue
        $targets += (Join-Path -Path $userDesktop -ChildPath ("FirstLogonBootstrap-{0}.log" -f $timestamp))
    }

    return $targets
}

function Write-BootstrapLog {
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

function Get-RootPhase {
    # Read RootPhase from HKLM:\SOFTWARE\WindowsInit (0 = initial, 1 = phase2 pending, 2 = completed).
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
        # Best-effort: treat failures as RootPhase=0.
    }
    return 0
}

function Test-Phase2RunOncePresent {
    # Check whether WindowsInit-Phase2 RunOnce exists.
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    try {
        $props = Get-ItemProperty -Path $key -Name 'WindowsInit-Phase2' -ErrorAction SilentlyContinue
        return ($null -ne $props)
    }
    catch {
        return $false
    }
}

$logTargets = Initialize-BootstrapLogging
Write-BootstrapLog -Level 'INFO' -Message 'FirstLogonBootstrap started.' -Targets $logTargets
Write-BootstrapLog -Level 'INFO' -Message ("User='{0}\\{1}', PID={2}, PSVersion={3}" -f $env:USERDOMAIN, $env:USERNAME, $PID, $PSVersionTable.PSVersion) -Targets $logTargets

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
$loaderPath = Join-Path -Path $scriptRoot -ChildPath 'root.ps1'

Write-BootstrapLog -Level 'INFO' -Message ("ScriptRoot='{0}', LoaderPath='{1}'" -f $scriptRoot, $loaderPath) -Targets $logTargets

if (-not (Test-Path -LiteralPath $loaderPath)) {
    Write-BootstrapLog -Level 'ERROR' -Message "Loader script not found; exiting." -Targets $logTargets
    exit 0
}

$rootPhase = Get-RootPhase
$phase2Queued = Test-Phase2RunOncePresent

Write-BootstrapLog -Level 'INFO' -Message ("RootPhase={0}, Phase2RunOncePresent={1}, Probe={2}, ProbeChain={3}" -f $rootPhase, $phase2Queued, [bool]$Probe, [bool]$ProbeChain) -Targets $logTargets

if ($Probe) {
    Write-BootstrapLog -Level 'INFO' -Message 'Probe mode enabled; exiting without invoking loader.' -Targets $logTargets
    exit 0
}

if ($ProbeChain) {
    Write-BootstrapLog -Level 'INFO' -Message 'ProbeChain mode enabled; invoking loader with -Mode Probe.' -Targets $logTargets
    try {
        & $loaderPath -Mode 'Probe'
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-BootstrapLog -Level 'ERROR' -Message ("ProbeChain invocation failed: {0}" -f $_.Exception.Message) -Targets $logTargets
        $exitCode = 1
    }

    Write-BootstrapLog -Level 'INFO' -Message ("FirstLogonBootstrap ProbeChain exiting with code {0}." -f $exitCode) -Targets $logTargets
    exit $exitCode
}

if ($rootPhase -ge 2) {
    Write-BootstrapLog -Level 'INFO' -Message 'RootPhase indicates completed; skipping.' -Targets $logTargets
    exit 0
}

if ($rootPhase -eq 1 -and $phase2Queued) {
    # Phase 2 is already queued; don't start Phase 1 early in the same logon session.
    Write-BootstrapLog -Level 'INFO' -Message 'RootPhase=1 and Phase2 RunOnce is present; skipping to avoid early Phase1.' -Targets $logTargets
    exit 0
}

Write-BootstrapLog -Level 'INFO' -Message 'Invoking root.ps1 loader...' -Targets $logTargets
try {
    & $loaderPath
    $exitCode = $LASTEXITCODE
}
catch {
    Write-BootstrapLog -Level 'ERROR' -Message ("Loader invocation failed: {0}" -f $_.Exception.Message) -Targets $logTargets
    $exitCode = 1
}

Write-BootstrapLog -Level 'INFO' -Message ("FirstLogonBootstrap exiting with code {0}." -f $exitCode) -Targets $logTargets
exit $exitCode
