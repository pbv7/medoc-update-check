#Requires -Version 7.0

<#
.SYNOPSIS
    Get encrypted Telegram credentials for M.E.Doc Update Check

.DESCRIPTION
    Decrypts CMS-encrypted Telegram credentials from file and returns BotToken and ChatId.
    This shared script is sourced by Config files to load credentials.

.PARAMETER Path
    Full path to encrypted credentials file (telegram.cms)

.OUTPUTS
    [hashtable] with BotToken and ChatId properties, or $null on error

.EXAMPLE
    $creds = & "$PSScriptRoot\Get-TelegramCredentials.ps1" -Path "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"
    $config.BotToken = $creds.BotToken
    $config.ChatId = $creds.ChatId

.NOTES
    Encryption: CMS (Cryptographic Message Syntax) with LocalMachine certificate
    Certificate: DocumentEncryptionCert type, CN=M.E.Doc Update Check Credential Encryption
    Key Usage: DataEncipherment, KeyEncipherment (required for CMS)
    KeyExportPolicy: NonExportable (private key cannot be extracted)
    Validity: 5 years from creation date
    Storage: Cert:\LocalMachine\My (readable by SYSTEM user)
#>

param([string]$Path)

if (-not (Test-Path $Path)) {
    Write-Error "Credentials file not found: $Path"
    return $null
}

try {
    # Read encrypted CMS message
    $encrypted = Get-Content -Path $Path -Raw -Encoding UTF8

    # Decrypt using certificate's private key (LocalMachine store)
    $decrypted = Unprotect-CmsMessage -Content $encrypted

    # Parse JSON to get credentials
    $credentials = $decrypted | ConvertFrom-Json

    return @{
        BotToken = $credentials.BotToken
        ChatId   = $credentials.ChatId
    }
} catch {
    Write-Error "Failed to decrypt credentials: $_"
    return $null
}
