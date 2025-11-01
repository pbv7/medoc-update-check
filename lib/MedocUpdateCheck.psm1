#Requires -Version 7.0
<#
.SYNOPSIS
    Universal M.E.Doc Update Status Check Module

.DESCRIPTION
    Reusable module for checking M.E.Doc update status across multiple servers.
    Analyzes server logs to determine if updates succeeded or failed.

.NOTES
    Author: Bohdan Potishuk
    For use with: Config.ps1 and Run.ps1
    Version: Check git tags with 'git describe --tags' or see Release History in README.md
#>

# Import shared configuration validation functions
Import-Module (Join-Path $PSScriptRoot "ConfigValidation.psm1") -Force

# Centralized Event ID definitions for Windows Event Log
# Each range represents a category of events for easy filtering and monitoring
enum MedocEventId {
    # 1000-1099: Normal flow (operational, not errors)
    Success = 1000                          # ✅ Update successful (all 3 flags confirmed)
    NoUpdate = 1001                         # ℹ️ No update detected (normal, no updates since last check)

    # 1100-1199: Configuration errors
    ConfigMissingKey = 1100                 # ❌ Missing required config key
    ConfigInvalidValue = 1101               # ❌ Invalid config value

    # 1200-1299: Environment/filesystem errors
    PlannerLogMissing = 1200                # ❌ Planner.log not found
    UpdateLogMissing = 1201                 # ❌ update_YYYY-MM-DD.log not found
    LogsDirectoryMissing = 1202             # ❌ M.E.Doc logs directory not found
    CheckpointDirCreationFailed = 1203      # ❌ Checkpoint directory creation failed
    EncodingError = 1204                    # ❌ Encoding error reading logs

    # 1300-1399: Update/flag validation failures
    Flag1Failed = 1300                      # ❌ Flag 1 missing (Infrastructure validation failed)
    Flag2Failed = 1301                      # ❌ Flag 2 missing (Service restart failed)
    Flag3Failed = 1302                      # ❌ Flag 3 missing (Version confirmation failed)
    MultipleFlagsFailed = 1303              # ❌ Multiple flags missing

    # 1400-1499: Notification/communication errors
    TelegramAPIError = 1400                 # ❌ Telegram API error
    TelegramSendError = 1401                # ❌ Telegram message send failed

    # 1500-1599: Checkpoint/state persistence errors
    CheckpointWriteError = 1500             # ❌ Checkpoint file write failed

    # 1900+: Unexpected/general errors
    GeneralError = 1900                     # ❌ Unexpected error (catch-all for unhandled exceptions)
}

function Get-VersionInfo {
    <#
    .SYNOPSIS
        Parse version string from M.E.Doc log format

    .PARAMETER RawVersion
        Raw version string from log (e.g., "ezvit.11.02.164-11.02.165.upd")
        Format: ezvit.{FromVersion}-{ToVersion}.upd

    .OUTPUTS
        Hashtable with FromVersion and ToVersion properties
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawVersion
    )

    # Parse standard M.E.Doc format: ezvit.11.02.164-11.02.165.upd
    # Separator is always hyphen (-) in M.E.Doc logs
    $parts = $RawVersion -split '-'

    if ($parts.Count -ge 2) {
        # Has from and to versions
        $fromVersion = $parts[0].Trim().Replace('ezvit.', '')
        $toVersion = $parts[1].Trim().Replace('.upd', '')
    } else {
        # Single version (unlikely but handle gracefully)
        $fromVersion = "previous"
        $toVersion = $RawVersion.Replace('ezvit.', '').Replace('.upd', '')
    }

    return @{
        FromVersion = $fromVersion
        ToVersion   = $toVersion
    }
}

function Format-UpdateTelegramMessage {
    <#
    .SYNOPSIS
        Format update result into human-readable Telegram message with emoji

    .PARAMETER UpdateResult
        Result object from Test-UpdateOperationSuccess with Status/ErrorId/Success properties

    .PARAMETER ServerName
        Server name for display

    .PARAMETER CheckTime
        Time when check was performed (current time)

    .OUTPUTS
        Formatted message string with emoji for Telegram
    #>
    param(
        [Parameter(Mandatory = $false)]
        $UpdateResult,

        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$CheckTime
    )

    if ($UpdateResult) {
        # Check explicit Status field for NoUpdate case (Status='NoUpdate', ErrorId=1001)
        if ($UpdateResult.Status -eq "NoUpdate") {
            # NO UPDATE case: Informational message
            return "ℹ️ NO UPDATE | $ServerName`nChecked: $CheckTime"
        } elseif ($UpdateResult.Success) {
            # SUCCESS case: Clean message (no flags shown)
            $durationStr = ""
            if ($UpdateResult.UpdateDuration) {
                $minutes = [int]($UpdateResult.UpdateDuration / 60)
                $seconds = $UpdateResult.UpdateDuration % 60
                $durationStr = "`nDuration: $minutes min $seconds sec"
            }

            $startTimeStr = if ($UpdateResult.UpdateStartTime) { $UpdateResult.UpdateStartTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }
            $endTimeStr = if ($UpdateResult.UpdateEndTime) { $UpdateResult.UpdateEndTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }

            return "✅ UPDATE OK | $ServerName`nVersion: $($UpdateResult.FromVersion) → $($UpdateResult.ToVersion)`nStarted: $startTimeStr`nCompleted: $endTimeStr$durationStr`nChecked: $CheckTime"
        } else {
            # FAILURE case: Show which flags failed
            $flags = @()
            if (-not $UpdateResult.Flag1_Infrastructure) { $flags += "✗ Infrastructure (DI/AI)" }
            if (-not $UpdateResult.Flag2_ServiceRestart) { $flags += "✗ Service Restart (ZvitGrp)" }
            if (-not $UpdateResult.Flag3_VersionConfirm) { $flags += "✗ Version Confirmed" }

            $flagsStr = if ($flags.Count -gt 0) { "`nValidation Failures: " + ($flags -join ", ") } else { "" }

            $startTimeStr = if ($UpdateResult.UpdateStartTime) { $UpdateResult.UpdateStartTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }
            $failedTimeStr = if ($UpdateResult.UpdateEndTime) { $UpdateResult.UpdateEndTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }

            return "❌ UPDATE FAILED | $ServerName`nVersion: $($UpdateResult.FromVersion) → $($UpdateResult.ToVersion)`nStarted: $startTimeStr`nFailed at: $failedTimeStr$flagsStr`nReason: $($UpdateResult.Reason)`nChecked: $CheckTime"
        }
    } else {
        # Legacy: $null case (should not happen with new code, but kept for safety)
        return "ℹ️ NO UPDATE | $ServerName`nChecked: $CheckTime"
    }
}

function Format-UpdateEventLogMessage {
    <#
    .SYNOPSIS
        Format update result into structured Event Log message (key=value format)

    .PARAMETER UpdateResult
        Result object from Test-UpdateOperationSuccess with Status/ErrorId/Success properties

    .PARAMETER ServerName
        Server name for display

    .PARAMETER CheckTime
        Time when check was performed (current time)

    .OUTPUTS
        Structured message string for Event Log (parseable key=value format)
    #>
    param(
        [Parameter(Mandatory = $false)]
        $UpdateResult,

        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$CheckTime
    )

    if ($UpdateResult) {
        # Check explicit Status field for NoUpdate case (Status='NoUpdate', ErrorId=1001)
        if ($UpdateResult.Status -eq "NoUpdate") {
            # NO UPDATE case: Minimal informational status
            return "Server=$ServerName | Status=NO_UPDATE | CheckTime=$CheckTime"
        } elseif ($UpdateResult.Success) {
            # SUCCESS case: Full details, no flag details
            $startTimeStr = if ($UpdateResult.UpdateStartTime) { $UpdateResult.UpdateStartTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }
            $endTimeStr = if ($UpdateResult.UpdateEndTime) { $UpdateResult.UpdateEndTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }
            return "Server=$ServerName | Status=UPDATE_OK | FromVersion=$($UpdateResult.FromVersion) | ToVersion=$($UpdateResult.ToVersion) | UpdateStarted=$startTimeStr | UpdateCompleted=$endTimeStr | Duration=$($UpdateResult.UpdateDuration) | CheckTime=$CheckTime"
        } else {
            # FAILURE case: Include flag details
            $flagsStr = "Flag1=$($UpdateResult.Flag1_Infrastructure) | Flag2=$($UpdateResult.Flag2_ServiceRestart) | Flag3=$($UpdateResult.Flag3_VersionConfirm)"
            $startTime = if ($UpdateResult.UpdateStartTime) { $UpdateResult.UpdateStartTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }

            return "Server=$ServerName | Status=UPDATE_FAILED | FromVersion=$($UpdateResult.FromVersion) | ToVersion=$($UpdateResult.ToVersion) | UpdateStarted=$startTime | $flagsStr | Reason=$($UpdateResult.Reason) | CheckTime=$CheckTime"
        }
    } else {
        # Legacy: $null case (should not happen with new code, but kept for safety)
        return "Server=$ServerName | Status=NO_UPDATE | CheckTime=$CheckTime"
    }
}

function Test-UpdateOperationSuccess {
    <#
    .SYNOPSIS
        Detects M.E.Doc update in Planner.log and validates success via update_YYYY-MM-DD.log

    .PARAMETER MedocLogsPath
        Directory containing Planner.log and update_YYYY-MM-DD.log files

    .PARAMETER SinceTime
        Optional: Only search for updates after this timestamp (for checkpoint filtering)

    .PARAMETER EncodingCodePage
        Log file encoding (default: 1251 for Windows-1251/Cyrillic)

    .OUTPUTS
        Always returns a hashtable with the following keys:
        - Status: "Success", "Failed", "NoUpdate", or "Error"
        - ErrorId: Event ID from [MedocEventId] enum
        - Success: $true if all success flags present, $false if any flag missing
        - FromVersion: Starting version (e.g., "11.02.183")
        - ToVersion: Target version (e.g., "11.02.184")
        - TargetVersion: Alternative name for ToVersion
        - UpdateTime: Timestamp when update was detected in Planner.log
        - UpdateStartTime: When update process started (from update log)
        - UpdateEndTime: When update process completed (from update log)
        - UpdateDuration: Duration in seconds
        - UpdateLogPath: Full path to update_YYYY-MM-DD.log
        - Flag1_Infrastructure: $true if "IsProcessCheckPassed DI: True, AI: True" found
        - Flag2_ServiceRestart: $true if "Службу ZvitGrp запущено" found
        - Flag3_VersionConfirm: $true if "Версія програми - {VERSION}" found
        - Reason: Human-readable reason for status (e.g., "All success flags confirmed" or "Missing success flags")

    .NOTES
        Strategy: Dual-log validation
        1. Detect update trigger in Planner.log: "Завантаження оновлення ezvit.X.X.X-X.X.X.upd"
        2. Extract target version from update filename
        3. Find and parse update_YYYY-MM-DD.log (FAILURE if missing)
        4. Verify ALL 3 success flags:
           - IsProcessCheckPassed DI: True, AI: True
           - Службу ZvitGrp запущено
           - Версія програми - {TARGET_VERSION}
        5. Return SUCCESS only if ALL flags present, otherwise FAILURE
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MedocLogsPath,

        [Parameter(Mandatory = $false)]
        $SinceTime,

        [Parameter(Mandatory = $false)]
        [int]$EncodingCodePage = 1251
    )

    $Encoding = [System.Text.Encoding]::GetEncoding($EncodingCodePage)
    $PlannerLogPath = Join-Path $MedocLogsPath 'Planner.log'

    # Verify Planner.log exists
    if (-not (Test-Path $PlannerLogPath)) {
        $errorMsg = "Planner.log not found at $PlannerLogPath"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::PlannerLogMissing)
        Write-Error $errorMsg
        return @{
            Status  = "Error"
            ErrorId = [MedocEventId]::PlannerLogMissing
            Message = $errorMsg
        }
    }

    # Read Planner.log with encoding error handling
    try {
        $lines = Get-Content $PlannerLogPath -Encoding $Encoding
    } catch {
        $errorMsg = "Error reading Planner.log with encoding $EncodingCodePage : $_`n"
        $errorMsg += "Troubleshooting: Verify EncodingCodePage matches M.E.Doc log file encoding. "
        $errorMsg += "Common values: 1251 (Windows-1251, default), 65001 (UTF-8), 1200 (UTF-16 LE). "
        $errorMsg += "Ensure Planner.log file is accessible and not locked by another process."
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::EncodingError)
        Write-Error $errorMsg
        return @{
            Status  = "Error"
            ErrorId = [MedocEventId]::EncodingError
            Message = $errorMsg
        }
    }

    # Phase 1: Search from end to find LATEST update operation
    # IMPORTANT: Planner.log uses 4-digit year format (DD.MM.YYYY)
    # This is different from update_*.log which uses 2-digit year (DD.MM.YY)
    # Searching backwards ensures we find the most recent update entry
    $updateTime = $null
    $targetVersionNum = $null
    $fromVersion = $null
    $toVersion = $null

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]

        # Parse timestamp and event from Planner.log
        # Format: DD.MM.YYYY HH:MM:SS EventText
        # Example: 23.10.2025 5:00:00 Завантаження оновлення ezvit.11.02.185-11.02.186.upd
        # Regex captures: [1]=Date, [2]=Time, [3]=Event
        # NOTE: Must use 4-digit year (\d{4}) - not 2-digit like update_*.log
        if ($line -match '^(\d{2}\.\d{2}\.\d{4})\s+(\d{1,2}:\d{2}:\d{2})\s+(.+)$') {
            try {
                # Parse date and time separately
                $dateStr = $matches[1]      # DD.MM.YYYY
                $timeStr = $matches[2]      # HH:MM:SS
                $timestampStr = "$dateStr $timeStr"
                $timestamp = [DateTime]::ParseExact($timestampStr, 'dd.MM.yyyy H:mm:ss', $null)
            } catch {
                continue
            }
            $logEvent = $matches[3]

            # Skip entries before checkpoint time if provided
            if ($SinceTime -and $timestamp -le $SinceTime) {
                continue
            }

            # Found the latest update operation
            if ($logEvent -match 'Завантаження оновлення.*ezvit\.[\d\.]+-[\d\.]+\.upd') {
                $updateTime = $timestamp

                # Extract version: ezvit.11.02.185-11.02.186.upd → 185 and 186
                if ($logEvent -match 'ezvit\.(\d+\.\d+\.\d+)-(\d+\.\d+\.(\d+))\.upd') {
                    $fromVersion = $matches[1]         # 11.02.185
                    $toVersion = $matches[2]           # 11.02.186
                    $targetVersionNum = $matches[3]    # 186 (last part only, used for flag validation)
                }

                break
            }
        }
    }

    # If no update operation found
    if (-not $updateTime) {
        return @{
            Status  = "NoUpdate"
            ErrorId = [MedocEventId]::NoUpdate
            Message = "No update operation found in logs"
        }
    }

    # Phase 2: Locate update_YYYY-MM-DD.log file
    $updateLogDate = $updateTime.ToString('yyyy-MM-dd')
    $updateLogPath = Join-Path $MedocLogsPath "update_$updateLogDate.log"

    # Check if update log exists
    if (-not (Test-Path $updateLogPath)) {
        # Log file missing = FAILURE
        return @{
            Status               = "Failed"
            ErrorId              = [MedocEventId]::UpdateLogMissing
            Success              = $false
            FromVersion          = $fromVersion
            ToVersion            = $toVersion
            TargetVersion        = $targetVersionNum
            UpdateTime           = $updateTime
            UpdateStartTime      = $null
            UpdateEndTime        = $null
            UpdateDuration       = $null
            UpdateLogPath        = $updateLogPath
            Flag1_Infrastructure = $false
            Flag2_ServiceRestart = $false
            Flag3_VersionConfirm = $false
            Reason               = "Update log file not found"
        }
    }

    # Phase 3: Parse update log and check for 3 success flags
    # IMPORTANT DISTINCTION: update_*.log uses 2-digit year format (DD.MM.YY)
    # This is different from Planner.log which uses 4-digit year (DD.MM.YYYY)
    # Example: 23.10.25 10:30:15.100 00000001 INFO    Message

    # Read update log with encoding error handling
    try {
        $updateLogLines = @(Get-Content $updateLogPath -Encoding $Encoding)
    } catch {
        $errorMsg = "Error reading update log $updateLogPath with encoding $EncodingCodePage : $_`n"
        $errorMsg += "Troubleshooting: Verify EncodingCodePage matches M.E.Doc log file encoding. "
        $errorMsg += "Common values: 1251 (Windows-1251, default), 65001 (UTF-8), 1200 (UTF-16 LE). "
        $errorMsg += "Ensure update log file is accessible and not locked by another process."
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::EncodingError)
        Write-Error $errorMsg
        return @{
            Status  = "Error"
            ErrorId = [MedocEventId]::EncodingError
            Message = $errorMsg
        }
    }

    # Convert to string for searching (handles both single line and array)
    $updateLogContent = $updateLogLines -join "`n"

    # Extract update log timestamps (start and end)
    # Format: DD.MM.YY HH:MM:SS.MMM XXXXXXXX LEVEL message
    # - Date: 2-digit year (23.10.25) - different from 4-digit in Planner.log
    # - Time: HH:MM:SS with optional milliseconds (.MMM) - ignored in parsing
    # - Log ID: XXXXXXXX (8 hex digits, e.g., 00000001)
    # - Level: INFO/WARNING/ERROR (ignored in parsing)
    # - Message: Event description with success flags
    $updateStartTime = $null
    $updateEndTime = $null

    # Find first and last timestamps in the update log
    # Searches for first and last lines matching the 2-digit year format
    if ($updateLogLines.Count -gt 0) {
        for ($i = 0; $i -lt $updateLogLines.Count; $i++) {
            $line = $updateLogLines[$i]
            # Match timestamp: DD.MM.YY HH:MM:SS (2-digit year, not 4-digit)
            # Milliseconds (.MMM) are captured in the regex but not used in parsing
            # Log ID and LEVEL are ignored - only timestamp matters for duration calculation
            if ($line -match '^(\d{2}\.\d{2}\.\d{2})\s+(\d{1,2}:\d{2}:\d{2})') {
                try {
                    $dateStr = $matches[1]      # DD.MM.YY
                    $timeStr = $matches[2]      # HH:MM:SS
                    $timestampStr = "$dateStr $timeStr"
                    $timestamp = [DateTime]::ParseExact($timestampStr, 'dd.MM.yy H:mm:ss', $null)

                    # Set first timestamp as start time
                    if (-not $updateStartTime) {
                        $updateStartTime = $timestamp
                    }
                    # Keep updating end time to get the last one
                    $updateEndTime = $timestamp
                } catch {
                    continue
                }
            }
        }
    }

    # Calculate update duration in seconds if both times are available
    $updateDuration = $null
    if ($updateStartTime -and $updateEndTime) {
        $updateDuration = [int]($updateEndTime - $updateStartTime).TotalSeconds
    }

    # Check Flag 1: .NET Infrastructure Validation
    $hasInfrastructureValid = $updateLogContent -match 'IsProcessCheckPassed\s+DI:\s*True,\s*AI:\s*True'

    # Check Flag 2: Service Restart Success
    # Looks for: "Службу ZvitGrp запущено" (may include "з підвищенням прав")
    # Message format in M.E.Doc update logs (Windows-1251 encoding)
    $hasServiceRestart = $updateLogContent -match 'Службу\s+ZvitGrp\s+запущено'

    # Check Flag 3: Version Confirmation
    # Looks for: "Версія програми - {TARGET_VERSION}" (exact version number from update)
    # Message format in M.E.Doc update logs (Windows-1251 encoding)
    $hasVersionConfirm = $updateLogContent -match "Версія\s+програми\s*-\s*$targetVersionNum\b"

    # Success only if ALL 3 flags present
    $allFlagsPresent = $hasInfrastructureValid -and $hasServiceRestart -and $hasVersionConfirm

    # Determine Status and ErrorId based on flags
    $status = $allFlagsPresent ? "Success" : "Failed"

    # Determine ErrorId for failures
    $errorId = if ($allFlagsPresent) {
        [MedocEventId]::Success
    } else {
        $missingCount = @(
            (-not $hasInfrastructureValid),
            (-not $hasServiceRestart),
            (-not $hasVersionConfirm)
        ) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count

        if ($missingCount -eq 1) {
            if (-not $hasInfrastructureValid) {
                [MedocEventId]::Flag1Failed
            } elseif (-not $hasServiceRestart) {
                [MedocEventId]::Flag2Failed
            } else {
                [MedocEventId]::Flag3Failed
            }
        } else {
            [MedocEventId]::MultipleFlagsFailed
        }
    }

    return @{
        Status               = $status
        ErrorId              = $errorId
        Success              = $allFlagsPresent
        FromVersion          = $fromVersion
        ToVersion            = $toVersion
        TargetVersion        = $targetVersionNum
        UpdateTime           = $updateTime
        UpdateStartTime      = $updateStartTime
        UpdateEndTime        = $updateEndTime
        UpdateDuration       = $updateDuration
        UpdateLogPath        = $updateLogPath
        Flag1_Infrastructure = $hasInfrastructureValid
        Flag2_ServiceRestart = $hasServiceRestart
        Flag3_VersionConfirm = $hasVersionConfirm
        Reason               = if ($allFlagsPresent) { "All success flags confirmed" } else { "Missing success flags" }
    }
}

function Write-EventLogEntry {
    <#
    .SYNOPSIS
        Writes an entry to Windows Event Log

    .PARAMETER Message
        Message to log

    .PARAMETER EventType
        Type of event: Information, Warning, or Error

    .PARAMETER EventId
        Numeric event ID for filtering

    .PARAMETER EventLogSource
        Event Log source name

    .PARAMETER EventLogName
        Event Log name (usually "Application")
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$EventType = "Information",

        [Parameter(Mandatory = $false)]
        [int]$EventId = 1000,

        [Parameter(Mandatory = $false)]
        [string]$EventLogSource = "M.E.Doc Update Check",

        [Parameter(Mandatory = $false)]
        [string]$EventLogName = "Application"
    )

    try {
        # PowerShell 7+ doesn't have Write-EventLog/New-EventLog cmdlets
        # Use .NET directly to write to Event Log (works on all Windows/PowerShell versions)

        # Check if source exists, create if needed
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
            try {
                [System.Diagnostics.EventLog]::CreateEventSource($EventLogSource, $EventLogName)
            } catch {
                # May fail if running without admin privileges
                Write-Warning "Could not create Event Log source: $_"
                return
            }
        }

        # Write to Event Log using .NET
        $eventLog = [System.Diagnostics.EventLog]::new($EventLogName)
        $eventLog.Source = $EventLogSource

        # Convert EventType string to EventLogEntryType enum
        $entryType = [System.Diagnostics.EventLogEntryType]::$EventType

        $eventLog.WriteEntry($Message, $entryType, $EventId)
        $eventLog.Dispose()
    } catch {
        # Fallback: if we can't write to Event Log
        Write-Warning "Could not write to Event Log: $_"
    }
}

function Invoke-MedocUpdateCheck {
    <#
    .SYNOPSIS
        Main function to check M.E.Doc update status and send notification

    .PARAMETER Config
        Hashtable with configuration (required keys):
        - ServerName: Display name for this server
        - MedocLogsPath: Path to M.E.Doc logs directory (containing Planner.log and update_YYYY-MM-DD.log)
        - BotToken: Telegram bot token
        - ChatId: Telegram chat/channel ID

        Optional keys:
        - LastRunFile: Path to checkpoint file (if not provided, uses $env:ProgramData\MedocUpdateCheck\checkpoints\)
        - EncodingCodePage: Log file encoding (default: 1251 for Windows-1251)
        - EventLogSource: Event Log source name (default: "M.E.Doc Update Check")

    .OUTPUTS
        [pscustomobject] with properties:
        - Outcome: 'Success' | 'NoUpdate' | 'UpdateFailed' | 'Error'
          * Success: Update confirmed with all validation flags
          * NoUpdate: No update detected in logs since last run
          * UpdateFailed: Update detected but validation failed (missing flags or version mismatch)
          * Error: Configuration, I/O, or notification transport error
        - EventId: [int] from MedocEventId enum (for Event Log tracing)
        - NotificationSent: [bool] - whether notification reached Telegram
        - UpdateResult: [hashtable] from Test-UpdateOperationSuccess (when available) or $null on config/transport errors

    .EXAMPLE
        $result = Invoke-MedocUpdateCheck -Config $config
        if ($result.Outcome -eq 'Success') {
            Write-Host "Update successful, notification sent"
        }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        # Helper: Build standardized outcome object
        function New-OutcomeObject($Outcome, $EventId, [bool]$NotificationSent, $UpdateResult) {
            [pscustomobject]@{
                Outcome          = $Outcome
                EventId          = [int]$EventId
                NotificationSent = $NotificationSent
                UpdateResult     = $UpdateResult
            }
        }
        # Validate required config keys
        $requiredKeys = @("ServerName", "MedocLogsPath", "BotToken", "ChatId")
    foreach ($key in $requiredKeys) {
        if (-not $Config.ContainsKey($key)) {
            Write-EventLogEntry -Message "Missing required config key: $key" -EventType Error -EventId ([MedocEventId]::ConfigMissingKey)
            Write-Error "Missing required config key: $key"
            return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::ConfigMissingKey) -NotificationSent:$false -UpdateResult $null)
        }
    }

    # Validate required config values (non-empty, valid format)
    # ServerName validation: non-empty string and valid format
    $serverNameResult = Test-ServerName -ServerName $Config.ServerName
    if (-not $serverNameResult.Valid) {
        $errorMsg = "Config error: $($serverNameResult.ErrorMessage)"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::ConfigInvalidValue)
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::ConfigInvalidValue) -NotificationSent:$false -UpdateResult $null)
    }

    # MedocLogsPath validation: directory exists
    $logsPathResult = Test-MedocLogsPath -MedocLogsPath $Config.MedocLogsPath
    if (-not $logsPathResult.Valid) {
        $errorMsg = "Config error: $($logsPathResult.ErrorMessage)"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::ConfigInvalidValue)
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::ConfigInvalidValue) -NotificationSent:$false -UpdateResult $null)
    }

    # BotToken validation: must be non-empty and match Telegram format
    $botTokenResult = Test-BotToken -BotToken $Config.BotToken
    if (-not $botTokenResult.Valid) {
        $errorMsg = "Config error: $($botTokenResult.ErrorMessage)"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::ConfigInvalidValue)
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::ConfigInvalidValue) -NotificationSent:$false -UpdateResult $null)
    }

    # ChatId validation: must be numeric (negative or positive)
    $chatIdResult = Test-ChatId -ChatId $Config.ChatId
    if (-not $chatIdResult.Valid) {
        $errorMsg = "Config error: $($chatIdResult.ErrorMessage)"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::ConfigInvalidValue)
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::ConfigInvalidValue) -NotificationSent:$false -UpdateResult $null)
    }

    # Set defaults for optional config
    if (-not $Config.ContainsKey("EncodingCodePage")) { $Config.EncodingCodePage = $defaultCodePage }
    if (-not $Config.ContainsKey("EventLogSource")) { $Config.EventLogSource = "M.E.Doc Update Check" }

    # EncodingCodePage validation: must be valid Windows codepage (with fallback to default)
    $encodingResult = Test-EncodingCodePage -EncodingCodePage $Config.EncodingCodePage -UseDefault
    if ($encodingResult.IsWarning) {
        Write-EventLogEntry -Message $encodingResult.ErrorMessage -EventType Warning -EventId ([MedocEventId]::ConfigInvalidValue)
        Write-Warning $encodingResult.ErrorMessage
        $Config.EncodingCodePage = $encodingResult.DefaultValue
    } elseif (-not $encodingResult.Valid) {
        $errorMsg = "Config error: $($encodingResult.ErrorMessage)"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::ConfigInvalidValue)
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::ConfigInvalidValue) -NotificationSent:$false -UpdateResult $null)
    }

    # Checkpoint file handling - support both explicit path and automatic system-wide location
    if (-not $Config.ContainsKey("LastRunFile")) {
        # Use system-wide ProgramData directory (best practice for system services)
        $checkpointDir = "$env:ProgramData\MedocUpdateCheck\checkpoints"

        # Create directory if it doesn't exist
        if (-not (Test-Path $checkpointDir)) {
            try {
                New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
            } catch {
                Write-EventLogEntry -Message "Failed to create checkpoint directory: $_" -EventType Error -EventId ([MedocEventId]::CheckpointDirCreationFailed)
            }
        }

        # Generate checkpoint filename from server name
        $checkpointFileName = "last_run_$($Config.ServerName -replace '[^\w\-]', '_').txt"
        $Config.LastRunFile = Join-Path $checkpointDir $checkpointFileName
    } else {
        # If explicit LastRunFile is provided, ensure directory exists
        $checkpointDir = Split-Path -Parent $Config.LastRunFile
        if (-not (Test-Path $checkpointDir)) {
            try {
                New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
            } catch {
                Write-EventLogEntry -Message "Failed to create checkpoint directory: $_" -EventType Error -EventId ([MedocEventId]::CheckpointDirCreationFailed)
            }
        }
    }

    $currentTimestamp = Get-Date -Format "dd.MM.yyyy HH:mm:ss"

    # Verify M.E.Doc logs directory exists
    if (-not (Test-Path $Config.MedocLogsPath)) {
        $errorMsg = "M.E.Doc logs directory not found: $($Config.MedocLogsPath)"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::LogsDirectoryMissing)
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::LogsDirectoryMissing) -NotificationSent:$false -UpdateResult $null)
    }

    # Get last run time from checkpoint file for filtering logs
    $lastRunTime = $null
    if (Test-Path $Config.LastRunFile) {
        $lastRunTimestamp = Get-Content $Config.LastRunFile
        try {
            $lastRunTime = [DateTime]::ParseExact($lastRunTimestamp, 'dd.MM.yyyy HH:mm:ss', $null)
        } catch {
            $lastRunTime = $null
        }
    }

    # Analyze update operation result
    # Use the M.E.Doc logs directory from config (already a directory, not a file path)
    $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $Config.MedocLogsPath `
        -SinceTime $lastRunTime `
        -EncodingCodePage $Config.EncodingCodePage

    # Determine Event ID and messages based on update result
    $telegramMessage = $null
    $eventLogMessage = $null
    $eventId = $null

    # Handle errors from Test-UpdateOperationSuccess
    if ($updateResult.Status -eq "Error") {
        # Planner.log missing or other file system error
        $errorMsg = $updateResult.Message
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([int]$updateResult.ErrorId) -EventLogSource $Config.EventLogSource
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([int]$updateResult.ErrorId) -NotificationSent:$false -UpdateResult $updateResult)
    }

    # Format messages using new formatting functions
    $telegramMessage = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName $Config.ServerName -CheckTime $currentTimestamp
    $eventLogMessage = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName $Config.ServerName -CheckTime $currentTimestamp

    # Use Event ID from updateResult
    $eventId = [int]$updateResult.ErrorId

    # Update checkpoint file FIRST with current timestamp (safer: prevents duplicate notifications if Telegram send fails)
    # If checkpoint write fails, we abort before sending notification
    try {
        $currentTimestamp | Set-Content $Config.LastRunFile
    } catch {
        $errorMsg = "Failed to update checkpoint file: $_"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::CheckpointWriteError) -EventLogSource $Config.EventLogSource
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::CheckpointWriteError) -NotificationSent:$false -UpdateResult $updateResult)
    }

    # Send message to Telegram (after checkpoint is safely written)
    $uri = "https://api.telegram.org/bot$($Config.BotToken)/sendMessage"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body @{
            chat_id = $Config.ChatId
            text    = $telegramMessage
        }

        if (-not $response.ok) {
            $errorMsg = "Telegram API error: $($response.description)"
            Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::TelegramAPIError) -EventLogSource $Config.EventLogSource
            Write-Error $errorMsg
            # Checkpoint already written, so no duplicate notification on retry
            return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::TelegramAPIError) -NotificationSent:$false -UpdateResult $updateResult)
        }

        # Log message send with appropriate level: success/no-update = Information, all failures = Error
        $logLevel = switch ($eventId) {
            ([int][MedocEventId]::Success) { "Information" }        # Success - all flags confirmed
            ([int][MedocEventId]::NoUpdate) { "Information" }       # No update - normal condition, not an error
            ([int][MedocEventId]::Flag1Failed) { "Error" }          # Flag 1 failure - update validation failed
            ([int][MedocEventId]::Flag2Failed) { "Error" }          # Flag 2 failure - update validation failed
            ([int][MedocEventId]::Flag3Failed) { "Error" }          # Flag 3 failure - update validation failed
            ([int][MedocEventId]::MultipleFlagsFailed) { "Error" }  # Multiple flag failures - update validation failed
            default { "Error" }                                       # Other event IDs (all are errors)
        }
        Write-EventLogEntry -Message $eventLogMessage `
            -EventType $logLevel -EventId $eventId `
            -EventLogSource $Config.EventLogSource
    } catch {
        $errorMsg = "Failed to send Telegram message: $_"
        Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::TelegramSendError) -EventLogSource $Config.EventLogSource
        Write-Error $errorMsg
        # Checkpoint already written, so no duplicate notification on retry
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::TelegramSendError) -NotificationSent:$false -UpdateResult $updateResult)
    }

    # Determine final outcome mapping for success / no-update / validation failure
    $finalOutcome = switch ($updateResult.Status) {
        'Success'   { 'Success' }
        'NoUpdate'  { 'NoUpdate' }
        'Failed'    { 'UpdateFailed' }
        default     { 'Error' }
    }

    # Map outcome to a final EventId to ensure correctness
    $finalEventId = switch ($finalOutcome) {
        'Success'      { [int][MedocEventId]::Success }
        'NoUpdate'     { [int][MedocEventId]::NoUpdate }
        'UpdateFailed' { [int]$updateResult.ErrorId }
        default        { [int][MedocEventId]::GeneralError }
    }

    return (New-OutcomeObject -Outcome $finalOutcome -EventId $finalEventId -NotificationSent:$true -UpdateResult $updateResult)
    } catch {
        # Catch-all for any unexpected exceptions in Invoke-MedocUpdateCheck
        $errorMsg = "Unexpected error during update check: $_"
        try {
            Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::GeneralError)
        } catch {
            # If Event Log fails, still report the error
            Write-Error $errorMsg
        }
        Write-Error $errorMsg
        return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::GeneralError) -NotificationSent:$false -UpdateResult $null)
    }
}

# Maps an outcome string to process exit code for schedulers/ops tools
function Get-ExitCodeForOutcome {
    <#
    .SYNOPSIS
        Maps update check outcome to process exit code for Task Scheduler and monitoring.

    .DESCRIPTION
        Converts high-level outcomes returned by Invoke-MedocUpdateCheck into integer
        exit codes suitable for schedulers and monitoring systems. This mapping is
        stable and may be relied upon by external tooling.

        Exit codes allow operators to configure alerts in Task Scheduler:
        - Exit code 0 (success/no-update) - routine completion, no action needed
        - Exit code 1 (error) - operational/configuration problem, requires investigation
        - Exit code 2 (validation failure) - update detected but failed verification, critical

    .PARAMETER Outcome
        One of: 'Success', 'NoUpdate', 'UpdateFailed', 'Error' (case-sensitive).

    .OUTPUTS
        [int] Exit code:
        - 0: Success or NoUpdate (routine operation)
        - 1: Error (configuration, I/O, Telegram transport issues)
        - 2: UpdateFailed (update validation failed - missing flags or version mismatch)

    .EXAMPLE
        $result = Invoke-MedocUpdateCheck -Config $config
        $exitCode = Get-ExitCodeForOutcome -Outcome $result.Outcome
        exit $exitCode

    .NOTES
        Keep this mapping stable once published; external tooling may rely on it.
        Operators should alert on exit codes 1 and 2 in Task Scheduler.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Success','NoUpdate','UpdateFailed','Error')]
        [string]$Outcome
    )

    switch ($Outcome) {
        'Success'     { 0 }
        'NoUpdate'    { 0 }
        'UpdateFailed'{ 2 }
        default       { 1 }
    }
}

# Export public functions
Export-ModuleMember -Function @(
    "Get-VersionInfo",
    "Format-UpdateTelegramMessage",
    "Format-UpdateEventLogMessage",
    "Test-UpdateOperationSuccess",
    "Write-EventLogEntry",
    "Invoke-MedocUpdateCheck",
    "Get-ExitCodeForOutcome"
)
