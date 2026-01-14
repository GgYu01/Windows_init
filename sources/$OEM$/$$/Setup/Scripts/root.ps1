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

function Get-PwshCandidateVersion {
    param([string]$Name)

    $version = [version]'0.0.0'
    if ($Name -match 'PowerShell-([0-9]+(?:\.[0-9]+)+)') {
        try { $version = [version]$Matches[1] } catch { $version = [version]'0.0.0' }
    }

    return $version
}

function Resolve-PwshInstaller {
    param(
        [string]$ScriptDir,
        [string]$PreferredName,
        [string[]]$LogTargets = @()
    )

    $searchRoots = @(
        $ScriptDir,
        (Join-Path -Path $ScriptDir -ChildPath 'Payloads'),
        'C:\Windows\Setup\Scripts',
        'C:\Windows\Setup\Scripts\Payloads'
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    if ($LogTargets.Count -gt 0) {
        Write-LoaderLog -Level 'INFO' -Message ("Searching PowerShell installers in: {0}" -f ($searchRoots -join '; ')) -Targets $LogTargets
    }

    $preferredPath = $null
    if ($PreferredName) {
        foreach ($root in $searchRoots) {
            $candidate = Join-Path -Path $root -ChildPath $PreferredName
            if (Test-Path -LiteralPath $candidate) {
                $preferredPath = $candidate
                break
            }
        }
    }

    if ($preferredPath) {
        return [pscustomobject]@{
            Path = $preferredPath
            Extension = ([IO.Path]::GetExtension($preferredPath)).ToLowerInvariant()
            Version = Get-PwshCandidateVersion -Name (Split-Path -Leaf $preferredPath)
            Source = 'preferred'
        }
    }

    $patterns = @('PowerShell-*-win-x64*.msi', 'PowerShell-*-win-x64*.zip')
    $seen = @{}
    $candidates = @()

    foreach ($root in $searchRoots) {
        foreach ($pattern in $patterns) {
            $items = Get-ChildItem -Path $root -Filter $pattern -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($seen.ContainsKey($item.FullName)) { continue }
                $seen[$item.FullName] = $true
                $candidates += [pscustomobject]@{
                    Path = $item.FullName
                    Extension = $item.Extension.ToLowerInvariant()
                    Version = Get-PwshCandidateVersion -Name $item.Name
                    LastWriteTimeUtc = $item.LastWriteTimeUtc
                    Source = 'discovered'
                }
            }
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    if ($LogTargets.Count -gt 0) {
        foreach ($candidate in $candidates) {
            Write-LoaderLog -Level 'INFO' -Message ("Candidate installer: {0} (version={1}, ext={2})" -f $candidate.Path, $candidate.Version, $candidate.Extension) -Targets $LogTargets
        }
    }

    $priority = @{ '.msi' = 0; '.zip' = 1 }
    $selected = $candidates | Sort-Object `
        @{ Expression = { if ($priority.ContainsKey($_.Extension)) { $priority[$_.Extension] } else { 9 } }; Ascending = $true }, `
        @{ Expression = { $_.Version }; Descending = $true }, `
        @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true } | Select-Object -First 1

    return $selected
}

function Install-PwshFromZip {
    param(
        [string]$ZipPath,
        [string[]]$LogTargets = @()
    )

    $expandCmd = Get-Command -Name 'Expand-Archive' -ErrorAction SilentlyContinue
    if (-not $expandCmd) {
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message 'Expand-Archive is not available; cannot unpack PowerShell zip.' -Targets $LogTargets
        }
        return $null
    }

    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $tempRoot = Join-Path -Path $programData -ChildPath 'WindowsInit\Temp'
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $extractRoot = Join-Path -Path $tempRoot -ChildPath ("PwshZip-{0}" -f $timestamp)
    $null = New-Item -Path $extractRoot -ItemType Directory -Force -ErrorAction SilentlyContinue

    if ($LogTargets.Count -gt 0) {
        Write-LoaderLog -Level 'INFO' -Message ("Expanding PowerShell zip '{0}' to '{1}'." -f $ZipPath, $extractRoot) -Targets $LogTargets
    }

    try {
        Expand-Archive -Path $ZipPath -DestinationPath $extractRoot -Force
    }
    catch {
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message ("Expand-Archive failed: {0}" -f $_.Exception.Message) -Targets $LogTargets
        }
        return $null
    }

    $sourceRoot = $null
    if (Test-Path -LiteralPath (Join-Path -Path $extractRoot -ChildPath 'pwsh.exe')) {
        $sourceRoot = $extractRoot
    }
    else {
        $childDirs = Get-ChildItem -Path $extractRoot -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $childDirs) {
            $candidatePwsh = Join-Path -Path $dir.FullName -ChildPath 'pwsh.exe'
            if (Test-Path -LiteralPath $candidatePwsh) {
                $sourceRoot = $dir.FullName
                break
            }
        }
    }

    if (-not $sourceRoot) {
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message "pwsh.exe not found in extracted zip payload." -Targets $LogTargets
        }
        return $null
    }

    $installRoot = if ($env:ProgramFiles) { Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\\7' } else { 'C:\Program Files\PowerShell\7' }
    $null = New-Item -Path $installRoot -ItemType Directory -Force -ErrorAction SilentlyContinue

    try {
        Copy-Item -Path (Join-Path -Path $sourceRoot -ChildPath '*') -Destination $installRoot -Recurse -Force
    }
    catch {
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message ("Failed to copy PowerShell files: {0}" -f $_.Exception.Message) -Targets $LogTargets
        }
        return $null
    }

    try {
        Remove-Item -Path $extractRoot -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # Ignore cleanup failures.
    }

    return (Join-Path -Path $installRoot -ChildPath 'pwsh.exe')
}

function Install-PwshIfMissing {
    param(
        [string]$ScriptDir,
        [string]$MsiName = 'PowerShell-7.5.4-win-x64.msi',
        [bool]$AllowInstall = $true,
        [string[]]$LogTargets = @()
    )

    function Find-PwshPath {
        param([string]$BaseDir)

        $cmd = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return $cmd.Source
        }

        $candidates = @()

        if ($env:ProgramFiles) {
            $candidates += (Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe')
        }

        if ($env:ProgramW6432) {
            $candidates += (Join-Path -Path $env:ProgramW6432 -ChildPath 'PowerShell\7\pwsh.exe')
        }

        if ($env:LOCALAPPDATA) {
            $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe')
        }

        if ($BaseDir) {
            $candidates += (Join-Path -Path $BaseDir -ChildPath 'pwsh.exe')
        }

        foreach ($path in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
            if (Test-Path -LiteralPath $path) {
                return $path
            }
        }

        return $null
    }

    $existingPath = Find-PwshPath -BaseDir $null
    if ($existingPath) {
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'INFO' -Message ("Found pwsh.exe at '{0}'." -f $existingPath) -Targets $LogTargets
        }
        return $existingPath
    }

    if (-not $AllowInstall) {
        Write-Warning "[WARN ] pwsh.exe not found and installation is disabled (probe mode)."
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'WARN' -Message 'pwsh.exe not found; installation disabled (probe mode).' -Targets $LogTargets
        }
        return $null
    }

    $installer = Resolve-PwshInstaller -ScriptDir $ScriptDir -PreferredName $MsiName -LogTargets $LogTargets
    if (-not $installer) {
        Write-Warning "[WARN ] pwsh.exe not found and no offline installer was discovered."
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message 'pwsh.exe not found and no offline installer was discovered.' -Targets $LogTargets
        }
        return $null
    }

    if ($LogTargets.Count -gt 0) {
        Write-LoaderLog -Level 'INFO' -Message ("Selected PowerShell installer: '{0}' (ext={1}, version={2})." -f $installer.Path, $installer.Extension, $installer.Version) -Targets $LogTargets
    }

    if ($installer.Extension -eq '.msi') {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $msiLogDir = Join-Path -Path $programData -ChildPath 'WindowsInit\Logs'
        $null = New-Item -Path $msiLogDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        $msiLogPath = Join-Path -Path $msiLogDir -ChildPath ("PowerShell7-MSI-{0}.log" -f $timestamp)
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'INFO' -Message ("msiexec log: '{0}'." -f $msiLogPath) -Targets $LogTargets
        }

        Write-Host ("[INFO ] Installing PowerShell 7 from '{0}'..." -f $installer.Path)
        $args = "/i `"$($installer.Path)`" /qn /norestart ADD_PATH=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 /l*v `"$msiLogPath`""
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'INFO' -Message ("msiexec exited with code {0}." -f $proc.ExitCode) -Targets $LogTargets
        }

        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            Write-Warning ("[WARN ] PowerShell 7 MSI exited with code {0}." -f $proc.ExitCode)
            if ($LogTargets.Count -gt 0) {
                Write-LoaderLog -Level 'ERROR' -Message ("PowerShell 7 MSI failed with exit code {0}." -f $proc.ExitCode) -Targets $LogTargets
            }
            return $null
        }
    }
    elseif ($installer.Extension -eq '.zip') {
        Write-Host ("[INFO ] Installing PowerShell 7 from zip '{0}'..." -f $installer.Path)
        $zipResult = Install-PwshFromZip -ZipPath $installer.Path -LogTargets $LogTargets
        if (-not $zipResult) {
            Write-Warning "[WARN ] PowerShell zip installation failed."
            return $null
        }
    }
    else {
        Write-Warning ("[WARN ] Unsupported PowerShell installer type: {0}" -f $installer.Extension)
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message ("Unsupported PowerShell installer type: {0}" -f $installer.Extension) -Targets $LogTargets
        }
        return $null
    }

    $installedPath = Find-PwshPath -BaseDir $null
    if (-not $installedPath) {
        # PATH may not be refreshed in the current process; fall back to the default MSI location.
        $fallback = $null
        if ($env:ProgramFiles) {
            $fallback = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
        }

        if ($fallback -and (Test-Path -LiteralPath $fallback)) {
            $installedPath = $fallback
        }
    }

    if (-not $installedPath) {
        Write-Warning '[WARN ] PowerShell 7 installation finished but pwsh.exe was not found on PATH.'
        if ($LogTargets.Count -gt 0) {
            Write-LoaderLog -Level 'ERROR' -Message 'PowerShell 7 MSI finished but pwsh.exe was not found (PATH not refreshed and default location missing).' -Targets $LogTargets
        }
        return $null
    }

    if ($LogTargets.Count -gt 0) {
        Write-LoaderLog -Level 'INFO' -Message ("Using pwsh.exe at '{0}'." -f $installedPath) -Targets $LogTargets
    }

    return $installedPath
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
$pwshPath = Install-PwshIfMissing -ScriptDir $scriptDir -AllowInstall:($Mode -ne 'Probe') -LogTargets $logTargets
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
