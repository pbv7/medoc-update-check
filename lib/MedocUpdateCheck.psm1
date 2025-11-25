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
    Success = 1000                          # ✅ Update successful (both markers confirmed)
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

    # 1300-1399: Update/marker validation failures
    UpdateValidationFailed = 1302           # ❌ Update failed (Missing version or completion marker)

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
            # FAILURE case: Generic failure message without marker details
            $startTimeStr = if ($UpdateResult.UpdateStartTime) { $UpdateResult.UpdateStartTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }
            $failedTimeStr = if ($UpdateResult.UpdateEndTime) { $UpdateResult.UpdateEndTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }

            return "❌ UPDATE FAILED | $ServerName`nVersion: $($UpdateResult.FromVersion) → $($UpdateResult.ToVersion)`nStarted: $startTimeStr`nFailed at: $failedTimeStr`nReason: $($UpdateResult.Reason)`nChecked: $CheckTime"
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
            # FAILURE case: Omit marker details, include reason
            $startTime = if ($UpdateResult.UpdateStartTime) { $UpdateResult.UpdateStartTime.ToString('dd.MM.yyyy HH:mm:ss') } else { "N/A" }

            return "Server=$ServerName | Status=UPDATE_FAILED | FromVersion=$($UpdateResult.FromVersion) | ToVersion=$($UpdateResult.ToVersion) | UpdateStarted=$startTime | Reason=$($UpdateResult.Reason) | CheckTime=$CheckTime"
        }
    } else {
        # Legacy: $null case (should not happen with new code, but kept for safety)
        return "Server=$ServerName | Status=NO_UPDATE | CheckTime=$CheckTime"
    }
}

function Find-LastUpdateOperation {
    <#
    .SYNOPSIS
        Locates the last (most recent) update operation block in log content

    .DESCRIPTION
        Searches backward from the end of the log file to find the most recent
        update operation. Handles logs that may contain multiple update operations
        by returning only the last one.

    .PARAMETER UpdateLogContent
        Full content of the update log file as a string

    .OUTPUTS
        Hashtable with the following keys:
        - Found: $true if operation markers found, $false otherwise
        - StartPosition: Index where operation begins (or $null if not found)
        - EndPosition: Index where operation ends (or $null if not found)
        - Content: The operation block content (or empty string if not found)

    .NOTES
        Search strategy:
        1. Search backward from end for: 'Завершення роботи, операція "Оновлення"'
        2. Record end position
        3. Search backward from end position for: 'Початок роботи, операція "Оновлення"'
        4. Record start position
        5. Extract content between markers
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpdateLogContent
    )

    # Search for operation end marker (completion)
    $endMarker = 'Завершення роботи, операція "Оновлення"'
    $endPosition = $UpdateLogContent.LastIndexOf($endMarker)

    if ($endPosition -eq -1) {
        # No operation found
        return @{
            Found        = $false
            StartPosition = $null
            EndPosition  = $null
            Content      = ""
        }
    }

    # Search backward from end position for operation start marker
    $startMarker = 'Початок роботи, операція "Оновлення"'
    $contentBeforeEnd = $UpdateLogContent.Substring(0, $endPosition)
    $startPosition = $contentBeforeEnd.LastIndexOf($startMarker)

    if ($startPosition -eq -1) {
        # Found end marker but not start marker (malformed log)
        return @{
            Found        = $false
            StartPosition = $null
            EndPosition  = $endPosition
            Content      = ""
        }
    }

    # Extract operation content (from start marker to end of end marker)
    $operationStart = $startPosition
    $operationEnd = $endPosition + $endMarker.Length
    $operationContent = $UpdateLogContent.Substring($operationStart, $operationEnd - $operationStart)

    return @{
        Found        = $true
        StartPosition = $startPosition
        EndPosition  = $operationEnd
        Content      = $operationContent
    }
}

function Test-UpdateMarker {
    <#
    .SYNOPSIS
        Validates presence of version confirmation (V) and completion (C) markers

    .DESCRIPTION
        Tests whether both required markers are present in the operation block:
        - Marker V: Version confirmation ("Версія програми - {VERSION}")
        - Marker C: Update completion ("Завершення роботи, операція \"Оновлення\"")

    .PARAMETER OperationContent
        Content of the update operation block (from Find-LastUpdateOperation)

    .PARAMETER TargetVersion
        Expected version number to match (e.g., "187" or "11.02.187")

    .OUTPUTS
        Hashtable with the following keys:
        - VersionConfirm: $true if version marker present, $false otherwise
        - CompletionMarker: $true if completion marker present, $false otherwise

    .NOTES
        This function ONLY validates marker presence. Determination of success/failure
        (orchestration logic) is the responsibility of the caller.

        Version matching uses word boundary (\b) to ensure exact matches.
        For example, version "187" will NOT match "1870" or "2187".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationContent,

        [Parameter(Mandatory = $true)]
        [string]$TargetVersion
    )

    # Test for version marker with flexible whitespace and word boundary
    # Pattern: "Версія" + flexible spaces + "програми" + optional spaces + "-" + optional spaces + version + word boundary
    $versionPattern = "Версія\s+програми\s*-\s*$([regex]::Escape($TargetVersion))\b"
    $hasVersionConfirm = $OperationContent -match $versionPattern

    # Test for completion marker
    $completionPattern = 'Завершення роботи, операція "Оновлення"'
    $hasCompletionMarker = $OperationContent -match [regex]::Escape($completionPattern)

    return @{
        VersionConfirm    = $hasVersionConfirm
        CompletionMarker  = $hasCompletionMarker
    }
}

function Test-UpdateState {
    <#
    .SYNOPSIS
        Tests update state by analyzing markers in the log file

    .DESCRIPTION
        Analyzes the full update log to determine if the update succeeded or failed.
        Uses the two-marker system:
        - Marker V: Version confirmation (Версія програми - {VERSION})
        - Marker C: Update completion (Завершення роботи, операція "Оновлення")

        Success requires BOTH markers to be present.

    .PARAMETER UpdateLogContent
        Full content of the update log file

    .PARAMETER TargetVersion
        Expected version number from the update operation

    .OUTPUTS
        Hashtable with the following keys:
        - Status: "Success" or "Failed"
        - VersionConfirm: $true if version marker present
        - CompletionMarker: $true if completion marker present
        - OperationFound: $true if operation block was located
        - Message: Human-readable reason (success or failure reason)

    .NOTES
        Classification logic:
        1. Locate the last update operation in the log
        2. If no operation found → Status = "Failed"
        3. Check for V and C markers in operation
        4. If (V = true AND C = true) → Status = "Success"
        5. Otherwise → Status = "Failed"

        This function handles multiple operations correctly by evaluating
        only the LAST operation (most recent).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpdateLogContent,

        [Parameter(Mandatory = $true)]
        [string]$TargetVersion
    )

    # Step 1: Find the last update operation
    $operationResult = Find-LastUpdateOperation -UpdateLogContent $UpdateLogContent

    if (-not $operationResult.Found) {
        return @{
            Status            = "Failed"
            VersionConfirm    = $false
            CompletionMarker  = $false
            OperationFound    = $false
            Message           = "No update operation found in log"
        }
    }

    # Step 2: Test markers in the operation block
    $markerResult = Test-UpdateMarker -OperationContent $operationResult.Content `
                                      -TargetVersion $TargetVersion

    # Step 3: Determine success based on both markers
    $bothMarkersPresent = $markerResult.VersionConfirm -and $markerResult.CompletionMarker
    $status = $bothMarkersPresent ? "Success" : "Failed"

    # Build appropriate message
    $message = if ($bothMarkersPresent) {
        "Update completed successfully with both required markers"
    } else {
        "Missing required markers: " + @(
            $markerResult.VersionConfirm ? $null : "Version confirmation"
            $markerResult.CompletionMarker ? $null : "Completion marker"
        ) | Where-Object { $_ } | Join-String -Separator " and "
    }

    return @{
        Status            = $status
        VersionConfirm    = $markerResult.VersionConfirm
        CompletionMarker  = $markerResult.CompletionMarker
        OperationFound    = $operationResult.Found
        Message           = $message
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
        Log file encoding code page (default: $defaultCodePage)

    .OUTPUTS
        Always returns a hashtable with the following keys:
        - Status: "Success", "Failed", "NoUpdate", or "Error"
        - ErrorId: Event ID from [MedocEventId] enum
        - Success: $true if validation passed
        - FromVersion: Starting version (e.g., "11.02.183")
        - ToVersion: Target version (e.g., "11.02.184")
        - TargetVersion: Alternative name for ToVersion
        - UpdateTime: Timestamp when update was detected in Planner.log
        - UpdateStartTime: When update process started (from update log)
        - UpdateEndTime: When update process completed (from update log)
        - UpdateDuration: Duration in seconds
        - UpdateLogPath: Full path to update_YYYY-MM-DD.log
        - MarkerVersionConfirm: $true if "Версія програми - {VERSION}" found
        - MarkerCompletionMarker: $true if completion marker found
        - OperationFound: $true if operation block boundaries were identified
        - Reason: Human-readable reason for status (e.g., which markers are missing)

    .NOTES
        Strategy: Dual-log validation
        1. Detect update trigger in Planner.log: "Завантаження оновлення ezvit.X.X.X-X.X.X.upd"
        2. Extract target version from update filename
        3. Find and parse update_YYYY-MM-DD.log (FAILURE if missing)
        4. Verify both required markers:
           - Version confirmation: Версія програми - {TARGET_VERSION}
           - Completion marker: Завершення роботи, операція "Оновлення"
        5. Return SUCCESS only if both markers present, otherwise FAILURE
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MedocLogsPath,

        [Parameter(Mandatory = $false)]
        $SinceTime,

        [Parameter(Mandatory = $false)]
        [int]$EncodingCodePage = $defaultCodePage
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

    # Build encoding troubleshooting message (reused in multiple error handlers)
    $encodingTroubleshoot = "Troubleshooting: Verify EncodingCodePage matches M.E.Doc log file encoding. Common supported values: $($validCodePages -join ', ')."

    # Read Planner.log with encoding error handling
    try {
        $lines = Get-Content $PlannerLogPath -Encoding $Encoding
    } catch {
        $errorMsg = "Error reading Planner.log with encoding $EncodingCodePage : $_`n"
        $errorMsg += "$encodingTroubleshoot "
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

            # Break only when records are strictly older than checkpoint
            # Records with timestamp equal to checkpoint are still processed (may contain new updates)
            if ($SinceTime -and $timestamp -lt $SinceTime) {
                break
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
            MarkerVersionConfirm   = $false
            MarkerCompletionMarker = $false
            OperationFound         = $false
            Reason                 = "Update log file not found (validation skipped because update log is missing)"
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
        $errorMsg += "$encodingTroubleshoot "
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

    # Test update state using marker-based validation
    # Returns: Status (Success/Failed), VersionConfirm, CompletionMarker, OperationFound, Message
    $classificationResult = Test-UpdateState -UpdateLogContent $updateLogContent `
                                             -TargetVersion $targetVersionNum

    # Determine final status and ErrorId
    $status = $classificationResult.Status
    $errorId = if ($status -eq "Success") {
        [MedocEventId]::Success
    } else {
        # All failures now map to UpdateValidationFailed (marker-based classification)
        [MedocEventId]::UpdateValidationFailed
    }

    return @{
        Status               = $status
        ErrorId              = $errorId
        Success              = ($status -eq "Success")
        FromVersion          = $fromVersion
        ToVersion            = $toVersion
        TargetVersion        = $targetVersionNum
        UpdateTime           = $updateTime
        UpdateStartTime      = $updateStartTime
        UpdateEndTime        = $updateEndTime
        UpdateDuration       = $updateDuration
        UpdateLogPath        = $updateLogPath
        MarkerVersionConfirm = $classificationResult.VersionConfirm
        MarkerCompletionMarker = $classificationResult.CompletionMarker
        OperationFound       = $classificationResult.OperationFound
        Reason               = $classificationResult.Message
    }
}

function Invoke-EventLogSourceExists {
    param([string]$EventLogSource)
    [System.Diagnostics.EventLog]::SourceExists($EventLogSource)
}

function Invoke-CreateEventLogSource {
    param(
        [string]$EventLogSource,
        [string]$EventLogName
    )
    [System.Diagnostics.EventLog]::CreateEventSource($EventLogSource, $EventLogName)
}

function New-EventLogHandle {
    param([string]$EventLogName)
    [System.Diagnostics.EventLog]::new($EventLogName)
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
        if (-not (Invoke-EventLogSourceExists -EventLogSource $EventLogSource)) {
            try {
                Invoke-CreateEventLogSource -EventLogSource $EventLogSource -EventLogName $EventLogName
            } catch {
                # May fail if running without admin privileges or Event Log is unavailable
                # When creation fails, we cannot write to Event Log - warn and exit gracefully
                Write-Warning "Could not create Event Log source: $_"
                return
            }
        }

        # Write to Event Log using .NET
        $eventLog = New-EventLogHandle -EventLogName $EventLogName
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
        - EncodingCodePage: Log file encoding code page (default: $defaultCodePage)
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
        - UpdateResult: [hashtable] from Test-UpdateOperationSuccess (when test was executed) or $null if config validation failed before test

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
                # Use -ErrorAction Stop to convert non-terminating errors to exceptions (catch them in the catch block)
                New-Item -ItemType Directory -Path $checkpointDir -Force -ErrorAction Stop | Out-Null
            } catch {
                # Cannot create checkpoint directory = cannot persist state = blocking error
                $errorMsg = "Failed to create checkpoint directory: $_"
                Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::CheckpointDirCreationFailed)
                Write-Error $errorMsg
                return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::CheckpointDirCreationFailed) -NotificationSent:$false -UpdateResult $null)
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
                # Use -ErrorAction Stop to convert non-terminating errors to exceptions (catch them in the catch block)
                New-Item -ItemType Directory -Path $checkpointDir -Force -ErrorAction Stop | Out-Null
            } catch {
                # Cannot create checkpoint directory = cannot persist state = blocking error
                $errorMsg = "Failed to create checkpoint directory: $_"
                Write-EventLogEntry -Message $errorMsg -EventType Error -EventId ([MedocEventId]::CheckpointDirCreationFailed)
                Write-Error $errorMsg
                return (New-OutcomeObject -Outcome 'Error' -EventId ([MedocEventId]::CheckpointDirCreationFailed) -NotificationSent:$false -UpdateResult $null)
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
            ([int][MedocEventId]::Success) { "Information" }        # Success - both markers confirmed
            ([int][MedocEventId]::NoUpdate) { "Information" }       # No update - normal condition, not an error
            ([int][MedocEventId]::UpdateValidationFailed) { "Error" } # Marker validation failed
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
    "Find-LastUpdateOperation",
    "Test-UpdateMarker",
    "Test-UpdateState",
    "Test-UpdateOperationSuccess",
    "Write-EventLogEntry",
    "Invoke-MedocUpdateCheck",
    "Get-ExitCodeForOutcome"
)
