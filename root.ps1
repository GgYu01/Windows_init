<#
  Loader for root.core.ps1.
  - If running on PowerShell 7+, execute root.core.ps1 directly.
  - If running on Windows PowerShell 5.x, locate or install pwsh from the bundled MSI and re-invoke root.core.ps1.
#>

param(
    [ValidateSet('Normal', 'Probe')]
    [string]$Mode = 'Normal'
)

$ErrorActionPreference = 'Stop'

function Initialize-LoaderLogging {
    # Write early logs to stable locations for troubleshooting auto-run issues.
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targets = @()

    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $logRoot = Join-Path -Path $programData -ChildPath 'WindowsInit\Logs'
    $null = New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction SilentlyContinue
    $targets += (Join-Path -Path $logRoot -ChildPath ("RootLoader-{0}.log" -f $timestamp))

    $publicRoot = if ($env:PUBLIC) { $env:PUBLIC } else { 'C:\Users\Public' }
    $publicDesktop = Join-Path -Path $publicRoot -ChildPath 'Desktop'
    $publicDebug = Join-Path -Path $publicDesktop -ChildPath 'WindowsInit-Debug'
    $null = New-Item -Path $publicDebug -ItemType Directory -Force -ErrorAction SilentlyContinue
    $targets += (Join-Path -Path $publicDebug -ChildPath ("RootLoader-{0}.log" -f $timestamp))

    $userDesktop = $null
    try { $userDesktop = [Environment]::GetFolderPath('Desktop') } catch { $userDesktop = $null }
    if (-not $userDesktop -and $env:USERPROFILE) {
        $userDesktop = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop'
    }

    if ($userDesktop) {
        $null = New-Item -Path $userDesktop -ItemType Directory -Force -ErrorAction SilentlyContinue
        $targets += (Join-Path -Path $userDesktop -ChildPath ("RootLoader-{0}.log" -f $timestamp))
    }

    return $targets
}

function Write-LoaderLog {
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
        [string]$MsiName = 'PowerShell-7.5.4-win-x64.msi',
        [bool]$AllowInstall = $true
    )

    $existing = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) {
        return $existing.Source
    }

    if (-not $AllowInstall) {
        Write-Warning "[WARN ] pwsh.exe not found and installation is disabled (probe mode)."
        return $null
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
        [string]$CoreScript,
        [string]$Mode
    )

    $argList = @(
        '-ExecutionPolicy','Bypass',
        '-NoLogo','-NonInteractive',
        '-File', "`"$CoreScript`"",
        '-Mode', $Mode
    )

    $proc = Start-Process -FilePath $PwshPath -ArgumentList $argList -Wait -PassThru
    return $proc.ExitCode
}

$scriptDir  = Get-ScriptDirectory
$coreScript = Get-CoreScriptPath -Directory $scriptDir

$logTargets = Initialize-LoaderLogging
Write-LoaderLog -Level 'INFO' -Message 'root.ps1 loader started.' -Targets $logTargets
Write-LoaderLog -Level 'INFO' -Message ("User='{0}\\{1}', PID={2}, PSVersion={3}" -f $env:USERDOMAIN, $env:USERNAME, $PID, $PSVersionTable.PSVersion) -Targets $logTargets
Write-LoaderLog -Level 'INFO' -Message ("Mode='{0}', ScriptDir='{1}', CoreScript='{2}'" -f $Mode, $scriptDir, $coreScript) -Targets $logTargets

if (-not (Test-Path -LiteralPath $coreScript)) {
    Write-LoaderLog -Level 'ERROR' -Message ("Core script not found at '{0}'." -f $coreScript) -Targets $logTargets
    Write-Error "[ERROR] Core script not found at '$coreScript'."
    exit 1
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-LoaderLog -Level 'INFO' -Message 'Running on PowerShell 7+; invoking root.core.ps1 directly.' -Targets $logTargets
    & $coreScript -Mode $Mode
    exit $LASTEXITCODE
}

$null = Write-LoaderLog -Level 'INFO' -Message 'Running on Windows PowerShell; ensuring pwsh.exe is available.' -Targets $logTargets
$pwshPath = Install-PwshIfMissing -ScriptDir $scriptDir -AllowInstall:($Mode -ne 'Probe')
if (-not $pwshPath) {
    if ($Mode -eq 'Probe') {
        Write-LoaderLog -Level 'WARN' -Message 'pwsh.exe not found; probe mode will not install PowerShell 7. Exiting.' -Targets $logTargets
        exit 0
    }

    Write-LoaderLog -Level 'ERROR' -Message 'Unable to find or install pwsh.exe; exiting.' -Targets $logTargets
    Write-Error '[ERROR] Unable to find or install pwsh.exe; root.core.ps1 cannot be executed.'
    exit 1
}

$null = Write-LoaderLog -Level 'INFO' -Message ("Re-invoking root.core.ps1 via pwsh.exe at '{0}'." -f $pwshPath) -Targets $logTargets
$exitCode = Invoke-CoreWithPwsh -PwshPath $pwshPath -CoreScript $coreScript -Mode $Mode
exit $exitCode
