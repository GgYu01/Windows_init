<# 
  WinPE helper script.
  - Generate random hexadecimal identifiers and persist them to a text file.
  - Install a NIC driver from a relative INF path.
  - Launch several GUI tools from relative paths for manual interaction.
  This script is intended to run in a graphical WinPE with PowerShell available.
#>

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO ] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "[WARN ] $Message"
}

function Write-Err {
    param([string]$Message)
    Write-Error "[ERROR] $Message"
}

function Get-ScriptRoot {
    # Resolve script root directory in WinPE.
    if ($MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }

    return (Get-Location).Path
}

function New-RandomHexString {
    param(
        [Parameter(Mandatory = $true)][int]$Length
    )

    # Generate an uppercase hexadecimal string of the given length.
    $chars = '0123456789ABCDEF'
    -join (1..$Length | ForEach-Object { $chars[Get-Random -Minimum 0 -Maximum $chars.Length] })
}

function Generate-HexIdentifiers {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    Write-Info "Generating random hexadecimal identifiers to '$OutputPath'..."

    $lines = @()

    # Five random 10-digit hexadecimal strings (uppercase).
    1..5 | ForEach-Object {
        $lines += (New-RandomHexString -Length 10)
    }

    # One identifier starting with 000E followed by eight random hexadecimal digits.
    $suffix = New-RandomHexString -Length 8
    $lines += ("000E$suffix")

    try {
        $lines | Set-Content -Path $OutputPath -Encoding ASCII
        Write-Info "Hex identifiers written to '$OutputPath'."
    }
    catch {
        Write-Err "Failed to write hex identifiers to '$OutputPath': $($_.Exception.Message)"
    }
}

function Install-NicDriverFromInf {
    param(
        [Parameter(Mandatory = $true)][string]$InfPath
    )

    if (-not (Test-Path -LiteralPath $InfPath)) {
        Write-Warn "NIC INF file not found at '$InfPath'; skipping NIC installation."
        return
    }

    Write-Info "Installing NIC driver from INF '$InfPath'..."

    try {
        # Use setupapi INF installation entry point; DefaultInstall section is used in most vendor INF files.
        $infFullPath = (Get-Item -LiteralPath $InfPath).FullName
        $args = "setupapi,InstallHinfSection DefaultInstall 132 `"$infFullPath`""

        $p = Start-Process -FilePath 'rundll32.exe' -ArgumentList $args -Wait -PassThru

        Write-Info "NIC INF installation completed with exit code $($p.ExitCode)."
    }
    catch {
        Write-Err "NIC INF installation failed: $($_.Exception.Message)"
    }
}

function Start-GuiTool {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string]$Description = $null
    )

    $root = Get-ScriptRoot
    $fullPath = Join-Path -Path $root -ChildPath $RelativePath

    if (-not (Test-Path -LiteralPath $fullPath)) {
        Write-Warn "GUI tool not found at '$fullPath' (Description: '$Description'); skipping."
        return
    }

    try {
        $workingDir = Split-Path -Parent $fullPath
        Write-Info "Launching GUI tool '$fullPath' (Description: '$Description')..."
        Start-Process -FilePath $fullPath -WorkingDirectory $workingDir | Out-Null
    }
    catch {
        Write-Err "Failed to launch GUI tool '$fullPath': $($_.Exception.Message)"
    }
}

# Main entry point for WinPE usage.

$scriptRoot = Get-ScriptRoot
Write-Info "Script root resolved to '$scriptRoot'."

# Generate random hexadecimal identifiers.
$hexOutput = Join-Path -Path $scriptRoot -ChildPath 'RandomHexIdentifiers.txt'
Generate-HexIdentifiers -OutputPath $hexOutput

# Install NIC driver from INF relative path.
$nicInfRelative = '无序网卡使用教程带工具\驱动\右键安装.inf'
Install-NicDriverFromInf -InfPath (Join-Path -Path $scriptRoot -ChildPath $nicInfRelative)

# Launch GUI tools for manual interaction.
Start-GuiTool -RelativePath '无序网卡使用教程带工具\修改程序.exe' `
              -Description 'Unordered NIC modification utility'

Start-GuiTool -RelativePath '硬盘PE系统和教程 文件如果无法打开请下载 RAR 解压工具 注意别下广告收费的\第二 SATA 硬盘 这个整个文件夹拷贝到PE桌面\VIUpdateTools.exe' `
              -Description 'Second SATA disk and update tools'

Start-GuiTool -RelativePath '主板修改和板载网卡教学\机器猫硬解工具 (1).exe' `
              -Description 'Motherboard and onboard NIC modification tool'

Write-Info "WinPE helper operations completed."

