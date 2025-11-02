#Requires -Version 7.0

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Setup utility requires colored console output for status messages and user feedback. Write-Host is appropriate for interactive setup operations.'
)]

<#
.SYNOPSIS
    Automated setup of Windows Task Scheduler job for M.E.Doc Update Check

.DESCRIPTION
    Creates a scheduled task to run the update check script daily.
    Must be run as Administrator.

.PARAMETER RunScriptPath
    Full path to the launcher script - the main M.E.Doc Update Check entry point
    (default: Run.ps1 in project root)
    Alias: ScriptPath (for backward compatibility with earlier versions)

.PARAMETER ConfigPath
    Path to server configuration file (REQUIRED)
    Each server needs its own config file with server-specific settings
    Can be relative to project root or absolute path
    Example: ".\configs\Config-MyServer.ps1" or "C:\Scripts\MedocUpdateCheck\configs\Config-MyServer.ps1"

.PARAMETER TaskName
    Task Scheduler task name (default: "M.E.Doc Update Check")

.PARAMETER ScheduleTime
    Time to run daily in format HH:MM (default: 08:00)

.EXAMPLE
    .\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-MyServer.ps1"
    # Creates task to run at 08:00 as SYSTEM

.EXAMPLE
    .\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-MyServer.ps1" -ScheduleTime "22:00"
    # Creates task to run at 22:00 as SYSTEM

.NOTES
    Requires Administrator privileges
#>

param(
    [Parameter(Mandatory = $false)]
    [Alias('ScriptPath')]
    [string]$RunScriptPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Run.ps1'),

    [string]$ConfigPath,
    [string]$TaskName = "M.E.Doc Update Check",
    [string]$ScheduleTime = "08:00"
)

# Verify running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "ERROR: This script must be run as Administrator"
    exit 1
}

# Find PowerShell 7+ executable (pwsh)
$pwshPath = Get-Command -Name pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $pwshPath) {
    Write-Error "ERROR: PowerShell 7+ (pwsh) not found on this system"
    Write-Error "PowerShell 7+ is required. See: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
    exit 1
}

Write-Host "✓ Found PowerShell 7+: $pwshPath"

Write-Host "M.E.Doc Update Check - Task Scheduler Setup"
Write-Host ([string]::new('=', 50)) -ForegroundColor Gray

# Validate ConfigPath parameter
if (-not $ConfigPath) {
    Write-Error "ERROR: Server configuration file path is required"
    Write-Error "Usage (relative): .\Setup-ScheduledTask.ps1 -ConfigPath '.\configs\Config-MyServer.ps1'"
    Write-Error "Usage (absolute): .\Setup-ScheduledTask.ps1 -ConfigPath 'C:\Scripts\MedocUpdateCheck\configs\Config-MyServer.ps1'"
    exit 1
}

# Resolve relative ConfigPath to absolute path for Task Scheduler reliability
# Relative paths are resolved against the project root to ensure consistency
# when the scheduled task executes in a different working directory context
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $pathFromRoot = Join-Path -Path $projectRoot -ChildPath $ConfigPath
    $resolvedPath = Resolve-Path -Path $pathFromRoot -ErrorAction SilentlyContinue
    if ($resolvedPath) {
        $ConfigPath = $resolvedPath.Path
        Write-Host "✓ Resolved config path to absolute: $ConfigPath"
    } else {
        # Fail explicitly to prevent creating a misconfigured scheduled task
        Write-Error "ERROR: Failed to resolve config file path from project root"
        Write-Error "Tried: $pathFromRoot"
        Write-Error "Use an absolute path or provide path relative to project root"
        exit 1
    }
}

# Validate launcher script exists
if (-not (Test-Path $RunScriptPath)) {
    Write-Error "ERROR: Launcher script not found at: $RunScriptPath"
    exit 1
}

Write-Host "✓ Launcher script found: $RunScriptPath"

# Validate server configuration file exists
if (-not (Test-Path $ConfigPath)) {
    Write-Error "ERROR: Server configuration file not found: $ConfigPath"
    exit 1
}

Write-Host "✓ Server configuration file found: $ConfigPath"

# Validate time format
if ($ScheduleTime -notmatch '^\d{2}:\d{2}$') {
    Write-Error "ERROR: Invalid time format. Use HH:MM (e.g., 05:10)"
    exit 1
}

[int]$hour = [int]$ScheduleTime.Split(':')[0]
[int]$minute = [int]$ScheduleTime.Split(':')[1]

if ($hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59) {
    Write-Error "ERROR: Invalid time values. Hour: 0-23, Minute: 0-59"
    exit 1
}

Write-Host "✓ Schedule time valid: $ScheduleTime"

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "⚠ Task '$TaskName' already exists"
    $response = Read-Host "Replace existing task? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Cancelled"
        exit 0
    }

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "✓ Removed existing task"
    } catch {
        Write-Error "ERROR: Failed to remove existing task: $_"
        exit 1
    }
}

# Create task action using PowerShell 7+ (pwsh)
# -NoProfile: Skip loading user profile for faster execution
# -ExecutionPolicy Bypass: Allow unsigned local scripts (script is on trusted local system)
$scriptDirectory = (Get-Item $RunScriptPath).DirectoryName
$action = New-ScheduledTaskAction `
    -Execute $pwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RunScriptPath`" -ConfigPath `"$ConfigPath`"" `
    -WorkingDirectory $scriptDirectory

Write-Host "✓ Task action created (using PowerShell 7+)"

# Create task trigger
try {
    $triggerTime = [DateTime]::ParseExact($ScheduleTime, 'HH:mm', $null)
    $trigger = New-ScheduledTaskTrigger `
        -Daily `
        -At $triggerTime

    Write-Host "✓ Task trigger created: Daily at $($triggerTime.ToString('HH:mm'))"
} catch {
    Write-Error "ERROR: Failed to create scheduled trigger: $_"
    exit 1
}

# Create task settings
# -AllowStartIfOnBatteries: Run even if system is on battery power (important for laptops)
# -DontStopIfGoingOnBatteries: Don't interrupt if AC power is lost during execution
# -StartWhenAvailable: Run immediately when system becomes available (if task was missed)
# -RunOnlyIfNetworkAvailable: Only run when network is connected (M.E.Doc requires network)
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

Write-Host "✓ Task settings configured"

# Create principal for SYSTEM user
# SYSTEM: Runs with system privileges (required for accessing M.E.Doc logs in system directories)
# ServiceAccount: Special logon type for system service accounts (no user interaction required)
# RunLevel Highest: Runs with elevated privileges (required for Event Log access)
$principal = New-ScheduledTaskPrincipal `
    -UserId 'NT AUTHORITY\SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

Write-Host "✓ Principal: SYSTEM (Highest privilege)"

# Create and register task
try {
    $task = New-ScheduledTask `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Monitors M.E.Doc updates and sends Telegram notifications"

    Register-ScheduledTask `
        -InputObject $task `
        -TaskName $TaskName `
        -Force | Out-Null

    Write-Host "✓ Task registered successfully"
} catch {
    Write-Error "ERROR: Failed to create task: $_"
    exit 1
}

Write-Host ""
Write-Host "✅ Task Scheduler Setup Complete!"
Write-Host ""
Write-Host "Task Details:"
Write-Host "  Name: $TaskName"
Write-Host "  Schedule: Daily at $ScheduleTime"
Write-Host "  Principal: SYSTEM"
Write-Host "  Launcher Script: $RunScriptPath"
Write-Host "  Configuration: $ConfigPath"
Write-Host ""
Write-Host "Verify in Task Scheduler:"
Write-Host "  Task Scheduler Library → Find '$TaskName'"
Write-Host ""
Write-Host "Monitor execution:"
Write-Host "  Event Viewer → Application → Source: 'M.E.Doc Update Check'"
Write-Host ""

exit 0
