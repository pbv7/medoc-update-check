<#
.SYNOPSIS
    Configuration template for M.E.Doc Update Check

.DESCRIPTION
    Server-specific settings. Copy this file, rename it, and customize for your server.

    Shows all available configuration options with explanations.

.USAGE
    1. Copy this file: cp Config.template.ps1 Config-MyServer.ps1
    2. Edit Config-MyServer.ps1 with your server's specific settings
    3. Run with your config: .\Run.ps1 -ConfigPath ".\configs\Config-MyServer.ps1"

.SECURITY NOTE
    Use Setup-Credentials.ps1 to store BotToken and ChatId securely.
    Credentials are encrypted with CMS (Cryptographic Message Syntax) using LocalMachine certificate
    and are auto-loaded below. Do not put credentials in this file.

.NOTES
    - Do not edit this template directly. Create a copy for each server you want to monitor.
    - Each server needs its own config file with unique settings.
    - Configuration is sourced by Run.ps1 and provides server-specific values to the module.
#>

# PSScriptAnalyzer: Suppressing unused variable warning - sourced by Run.ps1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# ==================== SERVER NAME CONFIGURATION ====================
# Server name displayed in Telegram messages and Event Log
#
# Strategy: Check in order (first match wins):
# 1. $env:MEDOC_SERVER_NAME environment variable (if set by admin/automation)
# 2. $env:COMPUTERNAME - Windows hostname (fallback, automatic)
# 3. Explicit override (uncomment if you need custom name):
#    $serverName = "MY_SERVER_NAME"
#
# Example:
#   - Auto-detect: Uses "SERVER-01" (from Windows hostname)
#   - Override: Set $serverName = "Production Database Server" for custom name
#
$serverName = if ($env:MEDOC_SERVER_NAME) {
    $env:MEDOC_SERVER_NAME
} else {
    $env:COMPUTERNAME  # Falls back to Windows hostname
}

# Uncomment to override with explicit name:
# $serverName = "MY_SERVER_NAME"

# ==================== TELEGRAM CREDENTIALS ====================
# IMPORTANT: Use Setup-Credentials.ps1 to store credentials securely
# Credentials are encrypted with CMS (Cryptographic Message Syntax) using LocalMachine certificate

# Load encrypted credentials from shared helper
$telegramCredsPath = "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"
$telegramCreds = & "$PSScriptRoot\..\utils\Get-TelegramCredentials.ps1" -Path $telegramCredsPath

# Build configuration
$config = @{
    # Display name for this server (auto-detected or explicit)
    ServerName = $serverName

    # Path to M.E.Doc logs directory (contains Planner.log and update_YYYY-MM-DD.log)
    # IMPORTANT: This must be the DIRECTORY, not a file path
    # The system automatically searches for both Planner.log and update_YYYY-MM-DD.log in this directory
    MedocLogsPath = "D:\MedocSRV\LOG"

    # Telegram Bot API token (from encrypted credentials file)
    BotToken = $telegramCreds.BotToken

    # Telegram Chat ID or Channel ID (from encrypted credentials file)
    ChatId = $telegramCreds.ChatId

    # ==================== OPTIONAL SETTINGS ====================

    # Checkpoint file path (stores last run time for duplicate prevention)
    # DEFAULT: Auto-generated in $env:ProgramData\MedocUpdateCheck\checkpoints\
    #   - Filename: last_run_{SANITIZED_SERVERNAME}.txt
    #   - Example: last_run_SERVER-01.txt
    # OPTIONAL: Set custom location (uncomment to use):
    # LastRunFile = "$env:ProgramData\MedocUpdateCheck\checkpoints\last_run_custom.txt"
    # RECOMMENDATION: Leave commented to use auto-generated checkpoint file

    # Log file encoding code page (for reading M.E.Doc logs)
    # DEFAULT: 1251 (Windows-1251 / Cyrillic - used by M.E.Doc)
    # Other values:
    #   - 65001 = UTF-8
    #   - 1252 = Windows-1252 (Western European)
    # CHANGE ONLY IF: Your M.E.Doc installation uses different encoding
    EncodingCodePage = 1251

    # Event Log source name (for Windows Event Viewer)
    # DEFAULT: "M.E.Doc Update Check"
    # CHANGE ONLY IF: You want different Event Log source name
    # RECOMMENDATION: Keep default unless you have specific requirements
    EventLogSource = "M.E.Doc Update Check"
}
