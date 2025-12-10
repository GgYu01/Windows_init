<#
  Loader for root.core.ps1.
  - If running on PowerShell 7+, execute root.core.ps1 directly.
  - If running on Windows PowerShell 5.x, locate or install pwsh from the bundled MSI and re-invoke root.core.ps1.
#>

$ErrorActionPreference = 'Stop'

function Get-ScriptDirectory {
    # Resolve the directory that contains this loader.
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Get-CoreScriptPath {
    param([string]$Directory)
    return (Join-Path -Path $Directory -ChildPath 'root.core.ps1')
}

function Install-PwshIfMissing {
    param(
        [string]$ScriptDir,
        [string]$MsiName = 'PowerShell-7.5.4-win-x64.msi'
    )

    $existing = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) {
        return $existing.Source
    }

    $msiPath = Join-Path -Path $ScriptDir -ChildPath $MsiName
    if (-not (Test-Path -LiteralPath $msiPath)) {
        Write-Warning "[WARN ] pwsh.exe not found and MSI '$msiPath' is missing."
        return $null
    }

    Write-Host "[INFO ] Installing PowerShell 7 from '$msiPath'..."
    $args = "/i `"$msiPath`" /qn ADD_PATH=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1"
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Warning ("[WARN ] PowerShell 7 MSI exited with code {0}." -f $proc.ExitCode)
        return $null
    }

    $installed = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $installed) {
        Write-Warning '[WARN ] PowerShell 7 installation finished but pwsh.exe was not found on PATH.'
        return $null
    }

    return $installed.Source
}

function Invoke-CoreWithPwsh {
    param(
        [string]$PwshPath,
        [string]$CoreScript
    )

    $argList = @(
        '-ExecutionPolicy','Bypass',
        '-NoLogo','-NonInteractive',
        '-File', "`"$CoreScript`""
    )

    $proc = Start-Process -FilePath $PwshPath -ArgumentList $argList -Wait -PassThru
    return $proc.ExitCode
}

$scriptDir  = Get-ScriptDirectory
$coreScript = Get-CoreScriptPath -Directory $scriptDir

if (-not (Test-Path -LiteralPath $coreScript)) {
    Write-Error "[ERROR] Core script not found at '$coreScript'."
    exit 1
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    & $coreScript
    exit $LASTEXITCODE
}

$pwshPath = Install-PwshIfMissing -ScriptDir $scriptDir
if (-not $pwshPath) {
    Write-Error '[ERROR] Unable to find or install pwsh.exe; root.core.ps1 cannot be executed.'
    exit 1
}

$exitCode = Invoke-CoreWithPwsh -PwshPath $pwshPath -CoreScript $coreScript
exit $exitCode
