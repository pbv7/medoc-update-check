#Requires -Version 7.0

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText',
    '',
    Justification = 'This is an interactive setup script. User credentials are entered as plaintext via CLI (unavoidable). ConvertTo-SecureString is used only to immediately encrypt credentials via CMS and save to disk. The plaintext exposure window is minimal (RAM only during setup execution).'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Setup utility requires colored console output for status messages and user feedback. Write-Host is appropriate for interactive setup operations.'
)]

<#
.SYNOPSIS
    Setup credentials for M.E.Doc Update Check (SYSTEM-compatible)

.DESCRIPTION
    Encrypts Telegram bot token and chat ID using CMS (Cryptographic Message Syntax)
    with a self-signed machine certificate stored in LocalMachine certificate store.

    Credentials are stored as encrypted CMS message at:
    $env:ProgramData\MedocUpdateCheck\credentials\telegram.cms

    This approach:
    - Works with SYSTEM user in Task Scheduler (LocalMachine certificate store)
    - Uses certificate-based encryption with 2048-bit RSA key
    - Private key is non-exportable (cannot be stolen or extracted)
    - Credentials stored as encrypted JSON for transparency
    - Certificate auto-created on first run, auto-rotates if expiring

.PARAMETER BotToken
    Telegram bot token (format: NUMERIC_ID:ALPHANUMERIC_TOKEN)

.PARAMETER ChatId
    Telegram chat/channel ID

.PARAMETER Force
    Overwrite existing credentials without confirmation

.EXAMPLE
    .\Setup-Credentials.ps1
    # Interactive mode - prompts for credentials and creates certificate if needed

.EXAMPLE
    .\Setup-Credentials.ps1 -BotToken "123456:ABC..." -ChatId "-1002825825746"
    # Non-interactive mode - useful for scripted deployment

.NOTES
    Requires Administrator privileges
    Creates/uses self-signed certificate in LocalMachine\My store
    Certificate subject: CN=M.E.Doc Update Check Credential Encryption
    Certificate lifetime: 5 years from creation date
    Credentials are encrypted with certificate's public key using CMS
    Only SYSTEM user (and Administrators) can decrypt with private key

    Certificate Lifecycle:
    - Certificates with Document Encryption EKU + KeyEncipherment usage are reused
    - Certificates expiring within 30 days are automatically regenerated
    - Certificates from previous releases lacking CMS requirements are silently regenerated
    - A certificate with any of these issues triggers automatic regeneration with proper warnings
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$BotToken,

    [Parameter(Mandatory = $false)]
    [string]$ChatId,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import validation helpers
$configValidationPath = Join-Path -Path $PSScriptRoot -ChildPath "../lib/ConfigValidation.psm1"
Import-Module $configValidationPath -Force

# Verify Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "ERROR: This script must be run as Administrator"
    exit 1
}

Write-Host "M.E.Doc Update Check - Credential Setup" -ForegroundColor Cyan
Write-Host ("=" * 50)
Write-Host ""

# ==================== HELPER FUNCTIONS ====================

function Get-MedocCredentialCertificate {
    <#
    .SYNOPSIS
        Get or create self-signed certificate for CMS encryption

    .DESCRIPTION
        Searches LocalMachine certificate store for M.E.Doc credential encryption certificate.
        Validates that existing certificates meet CMS encryption requirements:
        - Has Document Encryption Extended Key Usage (EKU): 1.3.6.1.4.1.311.80.1
        - Has KeyEncipherment key usage

        If found and valid: returns it
        If expiring (< 30 days): creates new one
        If CMS requirements not met (e.g., old cert from earlier release): creates new one
        If private key not accessible: creates new one
        If not found: creates new one
    #>

    $certSubject = "CN=M.E.Doc Update Check Credential Encryption"

    # Search for existing certificate
    $certs = Get-ChildItem -Path "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $certSubject }

    if ($certs) {
        # Use most recent certificate
        $cert = $certs | Sort-Object NotAfter -Descending | Select-Object -First 1

        # Check if still valid
        $daysUntilExpiration = ($cert.NotAfter - (Get-Date)).Days

        if ($daysUntilExpiration -le 0) {
            Write-Warning "Certificate has expired (NotAfter: $($cert.NotAfter)). Creating new certificate..."
            return New-MedocCredentialCertificate
        } elseif ($daysUntilExpiration -lt 30) {
            Write-Warning "Certificate expiring soon ($daysUntilExpiration days remaining). Creating new certificate..."
            return New-MedocCredentialCertificate
        }

        # Check if private key is accessible
        try {
            $null = $cert.PrivateKey
        } catch {
            Write-Warning "Certificate found but private key not accessible. Creating new certificate..."
            return New-MedocCredentialCertificate
        }

        # Check if certificate meets CMS requirements (Document Encryption EKU + KeyEncipherment usage)
        # This is critical for upgrades: old certs from v1.x lack these requirements
        $hasDocumentEncryptionEku = $false
        $hasKeyEnciphermentUsage = $false

        # Check Enhanced Key Usage (EKU) for Document Encryption
        if ($cert.Extensions) {
            foreach ($ext in $cert.Extensions) {
                if ($ext.Oid.Value -eq "2.5.29.37") {  # EKU OID
                    $ekuExt = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$ext
                    foreach ($oid in $ekuExt.EnhancedKeyUsages) {
                        # Document Encryption EKU: 1.3.6.1.4.1.311.80.1
                        if ($oid.Value -eq "1.3.6.1.4.1.311.80.1") {
                            $hasDocumentEncryptionEku = $true
                            break
                        }
                    }
                }
            }
        }

        # Check Key Usage for KeyEncipherment
        if ($cert.Extensions) {
            foreach ($ext in $cert.Extensions) {
                if ($ext.Oid.Value -eq "2.5.29.15") {  # Key Usage OID
                    $keyUsageExt = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]$ext
                    if ($keyUsageExt.KeyUsages -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment) {
                        $hasKeyEnciphermentUsage = $true
                    }
                }
            }
        }

        # If certificate doesn't meet CMS requirements, create new one
        if (-not $hasDocumentEncryptionEku -or -not $hasKeyEnciphermentUsage) {
            $missingDetails = @()
            if (-not $hasDocumentEncryptionEku) {
                $missingDetails += "Document Encryption EKU (1.3.6.1.4.1.311.80.1)"
            }
            if (-not $hasKeyEnciphermentUsage) {
                $missingDetails += "KeyEncipherment key usage"
            }
            Write-Warning "Existing certificate doesn't meet CMS encryption requirements (missing: $($missingDetails -join ', ')). Creating new certificate..."
            return New-MedocCredentialCertificate
        }

        Write-Host "✓ Using existing certificate (expires in $daysUntilExpiration days)" -ForegroundColor Green
        return $cert
    }

    # No certificate found - create new one
    Write-Host "ℹ️  No credential encryption certificate found" -ForegroundColor Cyan
    Write-Host "    Creating self-signed certificate..." -ForegroundColor Cyan
    return New-MedocCredentialCertificate
}

function New-MedocCredentialCertificate {
    <#
    .SYNOPSIS
        Create new self-signed certificate for CMS encryption

    .DESCRIPTION
        Creates certificate with:
        - Type: DocumentEncryptionCert (required for CMS encryption)
        - Subject: CN=M.E.Doc Update Check Credential Encryption
        - Store: Cert:\LocalMachine\My (accessible by SYSTEM user)
        - Lifetime: 5 years
        - Key: 2048-bit RSA, NonExportable
        - Key Usage: DataEncipherment, KeyEncipherment (both required for CMS)
        - EKU: Document Encryption (automatically set by -Type DocumentEncryptionCert)
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        $certSubject = "CN=M.E.Doc Update Check Credential Encryption"
        $notAfter = (Get-Date).AddYears(5)

        # Check ShouldProcess before creating certificate
        if (-not $PSCmdlet.ShouldProcess($certSubject, "Create new self-signed certificate")) {
            return $null
        }

        $cert = New-SelfSignedCertificate `
            -Subject $certSubject `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -Type DocumentEncryptionCert `
            -KeyUsage DataEncipherment, KeyEncipherment `
            -KeyExportPolicy NonExportable `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -NotAfter $notAfter

        Write-Host "✓ Created new certificate (Thumbprint: $($cert.Thumbprint))" -ForegroundColor Green
        Write-Host "  Valid until: $notAfter" -ForegroundColor Green

        return $cert
    } catch {
        Write-Error "ERROR: Failed to create certificate: $_"
        exit 1
    }
}

# ==================== MAIN SCRIPT ====================

# Create credentials directory
$credDir = "$env:ProgramData\MedocUpdateCheck\credentials"
if (-not (Test-Path $credDir)) {
    try {
        New-Item -ItemType Directory -Path $credDir -Force | Out-Null
        Write-Host "✓ Created credentials directory: $credDir"
    } catch {
        Write-Error "ERROR: Failed to create credentials directory: $_"
        exit 1
    }
}

# Path for encrypted credential file
$credFile = Join-Path $credDir "telegram.cms"

# Check if credentials exist
if ((Test-Path $credFile) -and -not $Force) {
    Write-Host "⚠️  Existing encrypted credentials found"
    $response = Read-Host "Replace existing credentials? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Cancelled"
        exit 0
    }
}

Write-Host ""

# Get credentials if not provided as parameters
if (-not $BotToken) {
    Write-Host "Enter Telegram Bot Token:"
    Write-Host "Format: NUMERIC_ID:ALPHANUMERIC_TOKEN"
    Write-Host "Example: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890"
    Write-Host ""
    $BotTokenSecure = Read-Host "Bot Token" -AsSecureString

    # Validate by temporarily converting to plain text
    $plainTextForValidation = $BotTokenSecure | ConvertFrom-SecureString -AsPlainText
    $botTokenValidation = Test-BotToken -BotToken $plainTextForValidation
    if (-not $botTokenValidation.Valid) {
        Write-Error "ERROR: $($botTokenValidation.ErrorMessage)"
        Clear-Variable plainTextForValidation
        exit 1
    }
    Clear-Variable plainTextForValidation  # Remove plain text from memory
} else {
    # Validate Bot Token from parameter
    $botTokenValidation = Test-BotToken -BotToken $BotToken
    if (-not $botTokenValidation.Valid) {
        Write-Error "ERROR: $($botTokenValidation.ErrorMessage)"
        exit 1
    }
    $BotTokenSecure = ConvertTo-SecureString -String $BotToken -AsPlainText -Force
}

if (-not $ChatId) {
    Write-Host ""
    Write-Host "Enter Telegram Chat ID:"
    Write-Host "For private chat: positive number (e.g., 123456789)"
    Write-Host "For channel: negative number (e.g., -1002825825746)"
    Write-Host ""
    $ChatId = Read-Host "Chat ID"
}

# Validate Chat ID
$chatIdValidation = Test-ChatId -ChatId $ChatId
if (-not $chatIdValidation.Valid) {
    Write-Error "ERROR: $($chatIdValidation.ErrorMessage)"
    exit 1
}

# Convert chat ID to SecureString for processing (PII)
$ChatIdSecure = ConvertTo-SecureString -String $ChatId -AsPlainText -Force

# Get or create certificate for encryption
Write-Host ""
$cert = Get-MedocCredentialCertificate

# Encrypt credentials using CMS
Write-Host ""
Write-Host "Encrypting credentials with CMS..."

try {
    # Convert SecureStrings to plain text (only kept in memory during encryption)
    $botTokenPlain = [System.Net.NetworkCredential]::new('', $BotTokenSecure).Password
    $chatIdPlain = [System.Net.NetworkCredential]::new('', $ChatIdSecure).Password

    # Create JSON structure with credentials
    $credentialsJson = @{
        BotToken = $botTokenPlain
        ChatId   = $chatIdPlain
    } | ConvertTo-Json -Depth 2

    # Encrypt using CMS (certificate's public key)
    # -To parameter requires certificate object, not thumbprint string
    $encrypted = Protect-CmsMessage `
        -To $cert `
        -Content $credentialsJson

    # Save encrypted credentials to file
    Set-Content -Path $credFile -Value $encrypted -Encoding UTF8

    Write-Host "✓ Credentials encrypted and saved"
} catch {
    Write-Error "ERROR: Failed to encrypt and save credentials: $_"
    exit 1
}

# Set restrictive file permissions (only SYSTEM and Administrators can read)
Write-Host "Setting file permissions..."
try {
    $acl = Get-Acl -Path $credFile
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance

    # Remove all existing permissions
    $acl.Access | ForEach-Object {
        $null = $acl.RemoveAccessRule($_)
    }

    # Add SYSTEM (SID: S-1-5-18)
    $systemSID = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-18")
    $systemRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $systemSID,
        "FullControl",
        "Allow"
    )
    $acl.AddAccessRule($systemRule)

    # Add Administrators group (SID: S-1-5-32-544)
    $adminSID = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
    $adminRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $adminSID,
        "FullControl",
        "Allow"
    )
    $acl.AddAccessRule($adminRule)

    Set-Acl -Path $credFile -AclObject $acl
    Write-Host "✓ File permissions set (SYSTEM + Administrators only)"
} catch {
    Write-Warning "WARNING: Could not set restricted permissions: $_"
}

Write-Host ""
Write-Host "✅ Credentials Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Encrypted credentials file:"
Write-Host "  $credFile"
Write-Host ""
Write-Host "Encryption certificate:"
Write-Host "  Subject: $($cert.Subject)"
Write-Host "  Thumbprint: $($cert.Thumbprint)"
Write-Host "  Valid until: $($cert.NotAfter)"
Write-Host "  Location: Cert:\LocalMachine\My"
Write-Host "  Key: 2048-bit RSA (NonExportable)"
Write-Host ""

exit 0
