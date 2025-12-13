<#
  First-logon bootstrapper for Windows_init.
  - Used by SetupComplete.cmd (RunOnce) as a fallback trigger.
  - Avoids running Phase1 early when Phase2 RunOnce is pending (RootPhase=1).
#>

$ErrorActionPreference = 'Stop'

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

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
$loaderPath = Join-Path -Path $scriptRoot -ChildPath 'root.ps1'

if (-not (Test-Path -LiteralPath $loaderPath)) {
    exit 0
}

$rootPhase = Get-RootPhase

if ($rootPhase -ge 2) {
    exit 0
}

if ($rootPhase -eq 1 -and (Test-Phase2RunOncePresent)) {
    # Phase 2 is already queued; don't start Phase 1 early in the same logon session.
    exit 0
}

& $loaderPath
exit $LASTEXITCODE
