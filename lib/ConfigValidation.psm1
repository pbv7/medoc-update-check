#Requires -Version 7.0

<#
.SYNOPSIS
    Shared configuration validation functions for M.E.Doc Update Check

.DESCRIPTION
    Provides centralized validation functions for configuration parameters.
    Used by both the main module (lib/MedocUpdateCheck.psm1) and utility scripts (utils/Validate-Config.ps1).

.NOTES
    This module is imported by MedocUpdateCheck.psm1 and provides reusable validation logic.
#>

# Essential Windows codepages for M.E.Doc environments
# Default: 1251 (Cyrillic - Windows-1251)
# Other supported: 65001 (UTF-8), 1200 (UTF-16 LE)
$defaultCodePage = 1251
$validCodePages = @($defaultCodePage, 65001, 1200)

<#
.SYNOPSIS
    Validates ServerName configuration parameter

.PARAMETER ServerName
    The server name to validate

.OUTPUTS
    [psobject] with properties:
    - Valid: [bool] Whether validation passed
    - ErrorMessage: [string] Error message if validation failed
#>
function Test-ServerName {
    param([string]$ServerName)

    if ([string]::IsNullOrWhiteSpace($ServerName)) {
        return @{
            Valid        = $false
            ErrorMessage = "ServerName cannot be empty"
        }
    }

    if ($ServerName -notmatch '^[\w\-\s]{1,255}$') {
        return @{
            Valid        = $false
            ErrorMessage = "ServerName must contain only alphanumeric characters, dashes, or spaces (max 255 chars)"
        }
    }

    return @{ Valid = $true }
}

<#
.SYNOPSIS
    Validates MedocLogsPath configuration parameter

.PARAMETER MedocLogsPath
    The M.E.Doc logs directory path to validate

.OUTPUTS
    [psobject] with properties:
    - Valid: [bool] Whether validation passed
    - ErrorMessage: [string] Error message if validation failed
#>
function Test-MedocLogsPath {
    param([string]$MedocLogsPath)

    if (-not (Test-Path $MedocLogsPath -PathType Container)) {
        return @{
            Valid        = $false
            ErrorMessage = "MedocLogsPath is not a valid directory: $MedocLogsPath"
        }
    }

    return @{ Valid = $true }
}

<#
.SYNOPSIS
    Validates BotToken configuration parameter

.PARAMETER BotToken
    The Telegram bot token to validate

.OUTPUTS
    [psobject] with properties:
    - Valid: [bool] Whether validation passed
    - ErrorMessage: [string] Error message if validation failed
#>
function Test-BotToken {
    param([string]$BotToken)

    if ([string]::IsNullOrWhiteSpace($BotToken)) {
        return @{
            Valid        = $false
            ErrorMessage = "BotToken cannot be empty. Format must be: {botId}:{botToken}"
        }
    }

    # Validate Telegram bot token format: numeric_id:alphanumeric_token
    # Format: {1-10 digits}:{35+ alphanumeric/hyphen/underscore characters}
    # Example: 1234567890:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC
    if (-not ($BotToken -match '^\d{1,10}:[A-Za-z0-9_-]{35,}$')) {
        $preview = $BotToken.Substring(0, [Math]::Min(20, $BotToken.Length))
        return @{
            Valid        = $false
            ErrorMessage = "BotToken format invalid. Expected format: {botId}:{botToken} (e.g., 1234567890:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC). Got: $preview..."
        }
    }

    return @{ Valid = $true }
}

<#
.SYNOPSIS
    Validates ChatId configuration parameter

.PARAMETER ChatId
    The Telegram chat ID to validate

.OUTPUTS
    [psobject] with properties:
    - Valid: [bool] Whether validation passed
    - ErrorMessage: [string] Error message if validation failed
#>
function Test-ChatId {
    param([string]$ChatId)

    if (-not ($ChatId -match '^-?\d+$')) {
        return @{
            Valid        = $false
            ErrorMessage = "ChatId must be numeric (integer): $ChatId"
        }
    }

    return @{ Valid = $true }
}

<#
.SYNOPSIS
    Validates EncodingCodePage configuration parameter

.PARAMETER EncodingCodePage
    The Windows encoding code page to validate

.PARAMETER UseDefault
    If true and invalid, return warning result instead of error (can fall back to 1251)

.OUTPUTS
    [psobject] with properties:
    - Valid: [bool] Whether validation passed
    - IsWarning: [bool] Whether this is a warning (can use default)
    - ErrorMessage: [string] Warning/error message
    - DefaultValue: [int] Default codepage to use (1251 if UseDefault)
#>
function Test-EncodingCodePage {
    param(
        [int]$EncodingCodePage,
        [switch]$UseDefault
    )

    # Check if it's one of the supported encodings
    if ($EncodingCodePage -notin $validCodePages) {
        $validList = $validCodePages -join ', '
        if ($UseDefault) {
            return @{
                Valid        = $true
                IsWarning    = $true
                ErrorMessage = "EncodingCodePage $EncodingCodePage is not supported (valid: $validList). Using default $defaultCodePage instead."
                DefaultValue = $defaultCodePage
            }
        } else {
            return @{
                Valid        = $false
                ErrorMessage = "EncodingCodePage is not supported: $EncodingCodePage (valid: $validList)"
            }
        }
    }

    return @{ Valid = $true }
}

<#
.SYNOPSIS
    Validates that a checkpoint directory can be created

.PARAMETER CheckpointPath
    Full path to the checkpoint file

.OUTPUTS
    [psobject] with properties:
    - Valid: [bool] Whether directory can be created/accessed
    - ErrorMessage: [string] Error message if validation failed
    - DirectoryPath: [string] The directory path that would contain the checkpoint file
#>
function Test-CheckpointPath {
    param([string]$CheckpointPath)

    $checkpointDir = Split-Path $CheckpointPath -Parent

    if (-not (Test-Path $checkpointDir)) {
        try {
            New-Item -Path $checkpointDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            return @{
                Valid         = $false
                ErrorMessage  = "Cannot create checkpoint directory: $checkpointDir - $_"
                DirectoryPath = $checkpointDir
            }
        }
    }

    return @{
        Valid         = $true
        DirectoryPath = $checkpointDir
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Test-ServerName',
    'Test-MedocLogsPath',
    'Test-BotToken',
    'Test-ChatId',
    'Test-EncodingCodePage',
    'Test-CheckpointPath'
) -Variable @('defaultCodePage', 'validCodePages')
