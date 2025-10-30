#Requires -Version 7.0

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Validation utility requires colored console output for validation results. Write-Host is appropriate for interactive validation reporting.'
)]

<#
.SYNOPSIS
    Validates M.E.Doc Update Check configuration file without executing the monitoring script

.DESCRIPTION
    Performs comprehensive validation of the configuration file including:
    - Required parameter presence and format
    - File path accessibility
    - Telegram bot token format compliance
    - Chat ID numeric validation
    - Checkpoint directory creation permissions (if writable path)

.PARAMETER ConfigPath
    Path to the configuration file (Config-*.ps1)
    Default: Config-$env:COMPUTERNAME.ps1

.PARAMETER Verbose
    Show detailed validation output

.EXAMPLE
    .\utils\Validate-Config.ps1
    Validate default configuration

    .\utils\Validate-Config.ps1 -ConfigPath .\configs\Config-SERVER01.ps1
    Validate specific configuration file

.EXAMPLE
    .\utils\Validate-Config.ps1 -Verbose
    Show detailed validation steps

.NOTES
    This utility validates configuration without starting the monitoring service.
    Use this before deploying to verify configuration is correct.
#>

param(
    [string]$ConfigPath,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Import shared validation functions
$libPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "lib") -ChildPath "ConfigValidation.psm1"
Import-Module $libPath -Force

# Determine config path
if (-not $ConfigPath) {
    $ConfigPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "configs") -ChildPath "Config-$env:COMPUTERNAME.ps1"
}

# Normalize path
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

if ($Verbose) {
    Write-Host "M.E.Doc Update Check - Configuration Validator" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Config Path: $ConfigPath" -ForegroundColor White
    Write-Host ""
}

# Check if config file exists
if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Configuration file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

if ($Verbose) {
    Write-Host "✓ Configuration file exists" -ForegroundColor Green
}

# Load configuration
try {
    $config = @{}
    . $ConfigPath
} catch {
    Write-Host "ERROR: Failed to load configuration: $_" -ForegroundColor Red
    exit 1
}

if ($Verbose) {
    Write-Host "✓ Configuration file loaded successfully" -ForegroundColor Green
    Write-Host ""
}

$errorsFound = 0
$warningsFound = 0

# Validation 1: ServerName
$serverResult = Test-ServerName -ServerName $config.ServerName
if (-not $serverResult.Valid) {
    Write-Host "✗ ServerName validation failed: $($serverResult.ErrorMessage)" -ForegroundColor Red
    $errorsFound++
} elseif ($Verbose) {
    Write-Host "✓ ServerName is valid: $($config.ServerName)" -ForegroundColor Green
}

if ($Verbose) { Write-Host "" }

# Validation 2: MedocLogsPath
$logsResult = Test-MedocLogsPath -MedocLogsPath $config.MedocLogsPath
if (-not $logsResult.Valid) {
    Write-Host "✗ $($logsResult.ErrorMessage)" -ForegroundColor Red
    $errorsFound++
} elseif ($Verbose) {
    Write-Host "✓ MedocLogsPath exists and accessible: $($config.MedocLogsPath)" -ForegroundColor Green
}

if ($Verbose) { Write-Host "" }

# Validation 3: BotToken format
$botResult = Test-BotToken -BotToken $config.BotToken
if (-not $botResult.Valid) {
    Write-Host "✗ $($botResult.ErrorMessage)" -ForegroundColor Red
    $errorsFound++
} elseif ($Verbose) {
    Write-Host "✓ BotToken format valid (Telegram format)" -ForegroundColor Green
}

if ($Verbose) { Write-Host "" }

# Validation 4: ChatId is numeric
$chatResult = Test-ChatId -ChatId $config.ChatId
if (-not $chatResult.Valid) {
    Write-Host "✗ $($chatResult.ErrorMessage)" -ForegroundColor Red
    $errorsFound++
} elseif ($Verbose) {
    Write-Host "✓ ChatId is numeric: $($config.ChatId)" -ForegroundColor Green
}

if ($Verbose) { Write-Host "" }

# Validation 5: EncodingCodePage (optional, with default fallback)
if ($config.ContainsKey("EncodingCodePage")) {
    $encodingResult = Test-EncodingCodePage -EncodingCodePage $config.EncodingCodePage -UseDefault
    if ($encodingResult.IsWarning) {
        Write-Host "⚠ $($encodingResult.ErrorMessage)" -ForegroundColor Yellow
        $warningsFound++
    } elseif (-not $encodingResult.Valid) {
        Write-Host "✗ $($encodingResult.ErrorMessage)" -ForegroundColor Red
        $errorsFound++
    } elseif ($Verbose) {
        Write-Host "✓ EncodingCodePage is valid: $($config.EncodingCodePage)" -ForegroundColor Green
    }
} elseif ($Verbose) {
    Write-Host "✓ EncodingCodePage not specified (will use default: 1251)" -ForegroundColor Green
}

if ($Verbose) { Write-Host "" }

# Validation 6: LastRunFile path is writable (if specified)
if ($config.ContainsKey("LastRunFile")) {
    $checkpointResult = Test-CheckpointPath -CheckpointPath $config.LastRunFile
    if (-not $checkpointResult.Valid) {
        Write-Host "✗ $($checkpointResult.ErrorMessage)" -ForegroundColor Red
        $errorsFound++
    } elseif ($Verbose) {
        Write-Host "✓ Checkpoint directory accessible: $($checkpointResult.DirectoryPath)" -ForegroundColor Green
    }
}

if ($Verbose) { Write-Host "" }

# Summary
Write-Host "================================================" -ForegroundColor Cyan
if ($errorsFound -eq 0 -and $warningsFound -eq 0) {
    Write-Host "✓ Configuration validation passed!" -ForegroundColor Green
    Write-Host "Configuration is ready for deployment." -ForegroundColor Green
    exit 0
} else {
    if ($errorsFound -gt 0) {
        Write-Host "✗ Configuration validation FAILED" -ForegroundColor Red
        Write-Host "Errors found: $errorsFound" -ForegroundColor Red
    }
    if ($warningsFound -gt 0) {
        Write-Host "⚠ Configuration has warnings: $warningsFound" -ForegroundColor Yellow
    }

    if ($errorsFound -gt 0) {
        exit 1
    } else {
        exit 0  # Warnings only
    }
}
