<#
  Set-GpuDeviceDesc.ps1
  - Update the DeviceDesc registry value for a display adapter instance.
  - Intended for manual execution on an installed system (not invoked automatically).
  - Supports both direct instance ID input and interactive selection.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InstanceId,

    [Parameter(Mandatory = $false)]
    [string]$NewDescription = 'NVIDIA Geforce GTX 660'
)

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

function Assert-Administrator {
    # Ensure the script runs with an elevated administrator token.
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Err "This script must be run as Administrator to modify HKLM registry keys."
            throw "Administrator privileges are required."
        }
    }
    catch {
        throw
    }
}

function Select-GpuInstanceIdInteractive {
    # Enumerate display adapters and let the user select one by index.
    try {
        $gpus = Get-PnpDevice -Class Display -Status OK -ErrorAction Stop
    }
    catch {
        Write-Err "Get-PnpDevice failed. Ensure the PnpDevice module is available. Error: $($_.Exception.Message)"
        return $null
    }

    if (-not $gpus) {
        Write-Warn "No display adapters were found via Get-PnpDevice -Class Display."
        return $null
    }

    Write-Info "Available display adapters:"
    $index = 0
    $indexed = @()
    foreach ($gpu in $gpus) {
        $indexed += [PSCustomObject]@{
            Index      = $index
            InstanceId = $gpu.InstanceId
            Friendly   = $gpu.FriendlyName
            Status     = $gpu.Status
        }
        $index++
    }

    $indexed | Format-Table -AutoSize

    $selection = Read-Host "Enter index of target display adapter"

    # Parse user input into an integer index; treat invalid input as a non-fatal condition.
    $parsedIndex = 0
    if (-not [int]::TryParse($selection, [ref]$parsedIndex)) {
        Write-Warn "Invalid index input. Aborting interactive selection."
        return $null
    }

    $selectionIndex = $parsedIndex
    $chosen = $indexed | Where-Object { $_.Index -eq $selectionIndex } | Select-Object -First 1
    if (-not $chosen) {
        Write-Warn "No adapter found for index $selectionIndex."
        return $null
    }

    Write-Info "Selected adapter: Index=$($chosen.Index), Friendly='$($chosen.Friendly)', InstanceId='$($chosen.InstanceId)'."
    return $chosen.InstanceId
}

function Set-DeviceDescriptionForInstanceId {
    param(
        [Parameter(Mandatory = $true)][string]$TargetInstanceId,
        [Parameter(Mandatory = $true)][string]$TargetDescription
    )

    # Update DeviceDesc under HKLM:\SYSTEM\CurrentControlSet\Enum\<InstanceId>.
    $relativePath = $TargetInstanceId.TrimStart('\')
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$relativePath"

    Write-Info "Using registry path '$regPath' for instance ID '$TargetInstanceId'."

    if (-not (Test-Path -LiteralPath $regPath)) {
        Write-Err "Registry key '$regPath' does not exist. Verify the instance ID."
        return
    }

    $oldValue = $null
    try {
        $props = Get-ItemProperty -LiteralPath $regPath -Name 'DeviceDesc' -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties.Match('DeviceDesc').Count -gt 0) {
            $oldValue = $props.DeviceDesc
        }
    }
    catch {
        Write-Warn "Failed to read existing DeviceDesc at '$regPath': $($_.Exception.Message)"
    }

    try {
        Set-ItemProperty -LiteralPath $regPath -Name 'DeviceDesc' -Value $TargetDescription -Type String -Force
        Write-Info "DeviceDesc updated to '$TargetDescription'."

        if ($null -ne $oldValue) {
            Write-Info "Previous DeviceDesc value was: '$oldValue'."
        }
        else {
            Write-Info "No previous DeviceDesc value was detected."
        }
    }
    catch {
        Write-Err "Failed to set DeviceDesc at '$regPath': $($_.Exception.Message)"
    }
}

try {
    Assert-Administrator

    $effectiveInstanceId = $InstanceId
    if (-not $effectiveInstanceId) {
        Write-Info "No InstanceId parameter provided; entering interactive selection mode."
        $effectiveInstanceId = Select-GpuInstanceIdInteractive
    }

    if (-not $effectiveInstanceId) {
        Write-Err "No valid InstanceId resolved; aborting without changes."
        return
    }

    Write-Info "Target DeviceDesc will be set to '$NewDescription'."
    Set-DeviceDescriptionForInstanceId -TargetInstanceId $effectiveInstanceId -TargetDescription $NewDescription
}
catch {
    Write-Err "Unhandled error: $($_.Exception.Message)"
}
