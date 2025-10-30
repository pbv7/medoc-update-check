#Requires -Version 7.0

<#
.SYNOPSIS
    M.E.Doc Update Check - Main Entry Point

.DESCRIPTION
    This script loads configuration and calls the update check module.
    Designed to be called by Windows Task Scheduler.

.PARAMETER ConfigPath
    Path to configuration file (REQUIRED)

    First time setup:
    1. Copy: cp configs/Config.template.ps1 configs/Config-MyServer.ps1
    2. Edit: configs/Config-MyServer.ps1 with your server's M.E.Doc logs directory path
    3. Run: .\Run.ps1 -ConfigPath ".\configs\Config-MyServer.ps1"

.EXAMPLE
    .\Run.ps1 -ConfigPath ".\configs\Config-MyServer.ps1"
    .\Run.ps1 -ConfigPath ".\configs\Config-MainOffice.ps1"
    .\Run.ps1 -ConfigPath ".\configs\Config-Warehouse.ps1"

.NOTES
    Call from Task Scheduler:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Script\MedocUpdateCheck\Run.ps1" -ConfigPath ".\configs\Config-MyServer.ps1"
#>

param(
    [string]$ConfigPath
)

# Ensure we're in the script directory
Set-Location $PSScriptRoot

# Validate ConfigPath parameter
if (-not $ConfigPath) {
    Write-Error "ConfigPath parameter is required."
    Write-Error "Usage: .\Run.ps1 -ConfigPath '.\configs\Config-MyServer.ps1'"
    Write-Error ""
    Write-Error "Steps:"
    Write-Error "  1. Copy the template: cp configs\Config.template.ps1 configs\Config-MyServer.ps1"
    Write-Error "  2. Edit Config-MyServer.ps1 with your server settings"
    Write-Error "  3. Run: .\Run.ps1 -ConfigPath '.\configs\Config-MyServer.ps1'"
    exit 1
}

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

try {
    . $ConfigPath
} catch {
    Write-Error "Failed to load configuration: $_"
    exit 1
}

# Load module
$modulePath = Join-Path $PSScriptRoot "lib\MedocUpdateCheck.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Error "Module not found: $modulePath"
    exit 1
}

try {
    Import-Module $modulePath -Force
} catch {
    Write-Error "Failed to load module: $_"
    exit 1
}

# Execute the check
try {
    $result = Invoke-MedocUpdateCheck -Config $config

    # Defensive: if function unexpectedly returned $null or lacks Outcome, treat as error
    if ($null -eq $result -or -not ($result.PSObject.Properties.Name -contains 'Outcome')) {
        exit 1
    }

    $exitCode = Get-ExitCodeForOutcome -Outcome $result.Outcome
    exit $exitCode
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
}
