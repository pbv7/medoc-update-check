# Security & Credentials Guide

## PowerShell 7+ Requirement

**This project requires PowerShell 7.0 or later.**

### Why PowerShell 7+?

1. **Security**: PowerShell 5.1 reached end-of-support in 2019. No more security updates.
2. **Maintenance**: Microsoft actively maintains only PowerShell 7+
3. **Best Practices**: Enforces modern security patterns (CMS encryption, secure credential handling)
4. **Performance**: Faster startup and execution times

### Verify PowerShell Version

```powershell
pwsh -Command '$PSVersionTable.PSVersion'
# Expected: 7.x or higher
```

### Installation

Follow Microsoft's official
[PowerShell Installation Guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

### Event Log Monitoring

This project uses `.NET classes` for Event Log integration, which works with PowerShell 7+ and is required by Task Scheduler automation.

To view Event Log entries, use `Get-WinEvent`:

```powershell
# ✅ PowerShell 7+ - works on Windows Server
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 10
```

See [TESTING.md - PowerShell 7+ Event Log Cmdlet Changes](TESTING.md#powershell-7-event-log-cmdlet-changes) for comprehensive examples.

---

## Secure Credential Storage (SYSTEM User Compatible)

**IMPORTANT:** Credentials (BotToken, ChatId) should NEVER be stored in plain text in config
files. This project uses CMS (Cryptographic Message Syntax) encryption with a self-signed
LocalMachine certificate for secure storage compatible with Task Scheduler running as SYSTEM
user.

### How It Works

1. **Admin runs setup** (once per server):

   ```powershell
   cd C:\Script\MedocUpdateCheck
   .\utils\Setup-Credentials.ps1
   ```

2. **Script automatically**:
   - Searches for existing credential encryption certificate in `Cert:\LocalMachine\My`
   - **Validates certificate meets CMS requirements** (upgrade scenario):
     - Has Document Encryption EKU (OID: 1.3.6.1.4.1.311.80.1)
     - Has KeyEncipherment key usage
     - If either requirement is missing (e.g., certificate from earlier release), generates new certificate
   - Checks certificate expiration and auto-rotates if expiring (< 30 days)
   - Creates new self-signed certificate if missing (subject: `CN=M.E.Doc Update Check Credential Encryption`)
   - Certificate has 5-year validity and NonExportable private key
   - Encrypts credentials using certificate's public key (CMS format)
   - Stores encrypted credentials in: `$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms`
   - Sets restrictive file permissions (SYSTEM + Administrators only)

3. **Config file loads credentials** automatically:
   - `Config.template.ps1` and custom config files read encrypted credentials automatically
   - Decrypts CMS message using certificate's private key from LocalMachine store
   - Never exposes plain text tokens in config
   - Works when running as SYSTEM in Task Scheduler

### Why CMS Encryption with Self-Signed Certificate?

| Method | User Context | Works with SYSTEM | Key Protection | SYSTEM Accessible |
|--------|---|---|---|---|
| Environment variables | User | ❌ No (user-specific) | None | ❌ No |
| SecureString (user-key) | User | ❌ No (user-specific) | User DPAPI | ❌ No |
| DPAPI (LocalMachine) | Machine | ✅ Yes | Machine DPAPI | ✅ Yes |
| **CMS with LocalMachine cert** | Machine | ✅ **YES** | **Certificate key** | ✅ **YES** |
| Plain text | Any | N/A | None | ❌ Insecure |

**CMS encryption with LocalMachine certificate** is superior because:

- Works with SYSTEM user in Task Scheduler
- Uses machine's certificate (accessible by all local system services and administrators)
- Provides encryption at rest (credentials encrypted on disk)
- Private key is NonExportable (cannot be extracted or stolen)
- Maintains file-level permissions for access control
- Certificate provides audit trail (creation, expiration, thumbprint)
- Supports certificate rotation and renewal

### Certificate Specifications

| Property | Value | Purpose |
|----------|-------|---------|
| **Subject** | `CN=M.E.Doc Update Check Credential Encryption` | Identifies certificate purpose |
| **Store Location** | `Cert:\LocalMachine\My` | Accessible by SYSTEM user |
| **Lifetime** | 5 years | Manageable rotation cycle |
| **Key Algorithm** | RSA 2048-bit | Industry standard, strong encryption |
| **Key Export Policy** | NonExportable | Prevents private key extraction |
| **Key Usage** | DataEncipherment, KeyEncipherment | Both required for CMS compatibility |
| **Extended Key Usage (EKU)** | Document Encryption (1.3.6.1.4.1.311.80.1) | Automatically set by DocumentEncryptionCert type |
| **Type** | Self-signed | No PKI infrastructure needed |

### CMS Security Threat Model & Risk Assessment

#### Threats Mitigated ✅

| Threat | Attack Scenario | CMS Protection |
|--------|---|---|
| **Credential file theft** | Attacker obtains `.cms` file from disk | ✅ Encrypted; useless without private key |
| **Plain text exposure** | Credentials visible in config files | ✅ Never exposed; decrypted only in memory |
| **Network interception** | Credentials captured during transmission | ✅ N/A; credentials only in memory on local machine |
| **User-scope DPAPI compromise** | CurrentUser DPAPI key is compromised | ✅ Uses LocalMachine scope, different key |
| **Private key theft (remote)** | Attacker tries to copy key from network | ✅ NonExportable prevents export |
| **Unauthorized decryption** | Non-admin user tries to read credentials | ✅ Certificate private key in LocalMachine store; user cannot access |

#### Residual Risks ⚠️ (Acceptable)

| Risk | Why It Occurs | Impact | Mitigation | Acceptance |
|------|---|---|---|---|
| **Local admin decrypts** | Admin has access to LocalMachine store | High | Restrict admin accounts; audit Event Log | ✅ Yes: Admins manage the system anyway |
| **Full machine compromise** | Attacker gains SYSTEM privileges | Very High | Only way to access is full machine takeover | ✅ Yes: Assume machine is trusted |
| **Certificate lost/deleted** | Admin accidentally deletes certificate | Medium | Document certificate recovery procedures | ✅ Yes: Can recreate from new cert |
| **Certificate expires (5 years)** | Lifetime ends; key becomes unusable | Medium | Document renewal procedures; set alerts | ✅ Yes: 5 years is reasonable rotation cycle |
| **Certificate on disk** | If disk is forensically analyzed | Very High | Use full-disk encryption, TPM, SecureBoot | ✅ Yes: Enterprise servers use encryption |

#### Why CMS is Sufficient for This Project

✅ **Protects against** the most common real-world threats:

- Credential file theft from disk
- Exposure via config file review
- Compromise via plain text storage
- Non-admin user access

✅ **Aligns with** Windows security best practices:

- Used by SQL Server, IIS, Exchange for credential storage
- Standard approach for service credentials
- Leverages built-in Windows cryptography

✅ **Works perfectly with** Task Scheduler SYSTEM context:

- LocalMachine certificate store readable by SYSTEM
- No special permissions or service accounts needed
- Simple, maintainable, enterprise-standard

⚠️ **Does NOT protect against**:

- Full machine compromise (acceptable; assume machine is trusted)
- Local administrator access (acceptable; admins manage the system)
- Forensic disk analysis of encrypted files (acceptable; enterprise disks use full encryption)

#### Threat Classification

| Threat Class | Coverage | Risk Level |
|---|---|---|
| **Accidental exposure** (config review, logs, etc.) | ✅ Protected | Low |
| **Malware on machine** (reads memory, not disk) | ✅ Partially protected | Medium |
| **Administrative tampering** | ⚠️ Not protected | Requires trust model acceptance |
| **Full machine compromise** | ⚠️ Not protected | Requires physical security |

**Conclusion:** CMS encryption provides industry-standard security sufficient for server-side
credential storage in enterprise environments where physical and administrative security are
assumed.

### Certificate Lifecycle Management

The `Setup-Credentials.ps1` script automatically manages certificate lifecycle to ensure credentials remain accessible:

**Certificate Validation Checks:**

When credentials are loaded or setup is run, the script validates the certificate meets these CMS requirements:

1. **Not Expired** - Certificate must have a valid NotAfter date
2. **Not Expiring Soon** - Certificates expiring within 30 days trigger automatic renewal
3. **Has Document Encryption EKU** - Extended Key Usage OID: `1.3.6.1.4.1.311.80.1` (required by CMS standard)
4. **Has KeyEncipherment Usage** - Key usage flag must include both `DataEncipherment` AND `KeyEncipherment` (required for decryption)

**Automatic Regeneration Scenarios:**

If any check fails, `Setup-Credentials.ps1` automatically regenerates a new certificate with:

- **When:** Expiring soon (<30 days), missing EKU, missing KeyEncipherment, or inaccessible private key
- **How:** New self-signed certificate created in `Cert:\LocalMachine\My` with proper CMS extensions
- **Why:** Old certificates from v1.x releases may lack proper EKU/KeyEncipherment. Rather than fail silently, the script detects and fixes this automatically
- **Result:** New certificate has 5-year validity, encrypted credentials continue working seamlessly

**Example Output During Regeneration:**

```text
⚠️  Existing certificate doesn't meet CMS encryption requirements
    Missing:
      • Document Encryption EKU (1.3.6.1.4.1.311.80.1)
      • KeyEncipherment key usage

Regenerating certificate with proper CMS requirements...
✓ New certificate created (valid 5 years)
```

**For Administrators:**

- No manual intervention required - certificates are managed automatically
- The script logs which certificates were regenerated and why
- If you see regeneration messages, it's expected behavior during upgrades (v1.x → v2.0+)
- Regeneration happens silently in non-interactive mode (no popups in Task Scheduler)

---

## Task Scheduler Principal Configuration

This project currently supports running scheduled tasks as **SYSTEM user** (the Windows SYSTEM account, not a username/password credential).

### SYSTEM User (Recommended - Local Log Files)

**When to use:**

- M.E.Doc log file is **local** on the same server (most common)
- Simple deployment with minimal credential management
- Each server runs its own independent scheduled task

**How it works:**

- Task Scheduler runs script under SYSTEM security context
- Script reads local M.E.Doc log files with full access
- Certificate-based encryption (CMS) enables credential access without passwords
- PowerShell 7+ executes with SYSTEM privileges

**Security characteristics:**

- ✅ Highest privilege on local machine (can read all local files)
- ✅ No credential rotation needed (SYSTEM account is persistent)
- ✅ Certificate encryption provides per-machine credential isolation
- ✅ Credentials stored securely in LocalMachine certificate store (readable by SYSTEM)
- ⚠️ Cannot access network shares (no domain credentials available to SYSTEM)
- ⚠️ Broadest privilege scope on local machine

**Credentials required:** None at Task Scheduler level (machine context)

---

### Future Options (Planned)

When the project adds support for remote log file monitoring or multi-server scenarios, additional principals may be documented:

- **Group Managed Service Account (gMSA)** - For domain scenarios
- **Specific domain user** - For network share access
- **Local service account** - For reduced privilege scenarios

**Current Status:** Only SYSTEM user is supported. Use [DEPLOYMENT.md](DEPLOYMENT.md#-step-5-create-scheduled-task) for setup instructions.

---

## Server Name Configuration Strategy

ServerName is used in Telegram and Event Log messages to identify which M.E.Doc server sent
the notification. The script uses intelligent detection with multiple strategies.

### Strategy 1: Default Auto-Detection (Recommended)

**When to use:** Most common scenario - monitoring each server independently

**How it works:**

1. Checks if `$env:MEDOC_SERVER_NAME` environment variable is set (by admin/automation)
2. Falls back to Windows hostname: `$env:COMPUTERNAME`
3. No configuration change needed

**Example:**

```powershell
# No changes required - just run the script
# Telegram will show: "MY-MEDOC-SERVER" (Windows hostname)
```

**Best for:**

- Single-purpose monitoring servers
- Each server has unique Windows hostname
- Minimal configuration

### Strategy 2: Environment Variable (Multi-Server from Central Location)

**When to use:** Running monitor from one central location for multiple M.E.Doc servers

**How it works:**

Set `$env:MEDOC_SERVER_NAME` before running the script

**Example:**

```powershell
# Running from central location for multiple servers
$env:MEDOC_SERVER_NAME = "MY-MEDOC-SERVER"
& "\\central\share\MedocUpdate\Run.ps1" -ConfigPath ".\configs\Config.ps1"

# Later, for different server:
$env:MEDOC_SERVER_NAME = "MEDOC-SRV02"
& "\\central\share\MedocUpdate\Run.ps1" -ConfigPath ".\configs\Config.ps1"
```

**Best for:**

- Central monitoring automation
- Multiple servers with same script
- Dynamic server identification

### Strategy 3: Explicit Override (Advanced)

**When to use:** Special naming convention or legacy setup requiring manual name

**How it works:**

Edit your config file to explicitly set ServerName

**Example:**

```powershell
# In Config-MY-MEDOC-SERVER.ps1 (or any config file):
$serverName = "CustomName-Office1"
```

**Best for:**

- Custom server naming schemes
- Legacy system integration
- Special naming requirements

**⚠️ When NOT to use:** Only if auto-detection doesn't work for you

---

**Summary:**

- **Default:** Auto-detects from `$env:MEDOC_SERVER_NAME` → `$env:COMPUTERNAME`
- **Use env var:** When monitoring multiple servers from one location
- **Override:** Only when auto-detection doesn't fit your setup

---

## Windows-1251 Encoding (Cyrillic Support)

This project handles M.E.Doc log files using Windows-1251 encoding (CP1251) for Cyrillic
characters. Understanding this is important for troubleshooting and testing.

### Why Windows-1251?

M.E.Doc is Ukrainian enterprise accounting software. Its log files use Windows-1251 encoding
(not UTF-8) to properly represent Cyrillic (Ukrainian) text. Examples from logs:

- `Завантаження оновлення` (Update download)
- `Помилка при оновленні` (Update error)
- `Успішне оновлення` (Successful update)

**If encoding is wrong:** Cyrillic text appears garbled (boxes, question marks, mojibake) and script cannot parse log entries.

### When You Need to Know This

**For Production Use:**

- Log files are read automatically with default PowerShell encoding (handles Windows-1251 correctly)
- No special configuration needed if logs are in Windows-1251

**For Testing:**

- Test data files MUST be Windows-1251 encoded (not UTF-8)
- Mismatch causes test failures and false negatives

**For Custom Development:**

- When creating test files or log samples, ensure Windows-1251 encoding
- When modifying scripts that read logs, use default encoding (not UTF-8 forced)

### Checking File Encoding

**On Windows:**

```powershell
# Check if file is Windows-1251
$file = "log.txt"
$content = Get-Content -Path $file -Encoding Default
# If Cyrillic text displays correctly → encoding is correct

# Check with BOM/encoding info (PowerShell 7+)
$content = Get-Content -Path $file -Encoding UTF8
# If Cyrillic text looks broken → file is NOT UTF-8 (probably Windows-1251)
```

**On Linux/Mac (if testing):**

```bash
# Check encoding
file log.txt
# Output example: "...Windows-1251..."

# Convert to Windows-1251
iconv -f UTF-8 -t WINDOWS-1251 input.txt > output.txt

# Verify conversion
iconv -f WINDOWS-1251 -t UTF-8 output.txt | head
```

### Converting Test Data

If you create test data in UTF-8 and need to convert:

```bash
# Step 1: Create or edit file in UTF-8
vim test-data.txt

# Step 2: Convert to Windows-1251
iconv -f UTF-8 -t WINDOWS-1251 test-data.txt -o test-data-cp1251.txt

# Step 3: Verify it worked (convert back and check)
iconv -f WINDOWS-1251 -t UTF-8 test-data-cp1251.txt | head

# Step 4: Replace original
mv test-data-cp1251.txt test-data.txt
```

### Troubleshooting Encoding Issues

**Symptom:** Test fails or script doesn't parse log entries

**Check:**

1. Is the file Windows-1251 encoded?

   ```powershell
   Get-Content -Path $file -Encoding Default  # Should show Cyrillic correctly
   ```

2. If showing garbage characters → file is wrong encoding

**Fix:**

Convert file to Windows-1251 (using iconv command above)

### Configuration

In config files, encoding is configured via:

```powershell
# Default: Uses system default (Windows-1251 on Windows systems)
# EncodingCodePage = [default]

# Or explicitly specify:
# EncodingCodePage = 1251  # Windows-1251
# EncodingCodePage = 65001 # UTF-8 (NOT recommended for M.E.Doc logs)
```

---

## Sensitive Data Status

All real credentials have been replaced with placeholder values in the repository.

### What Was Changed

| Item | Original | Replacement | Location |
|------|----------|-------------|----------|
| **Bot Token** | Real Telegram token | Never committed | Setup-Credentials.ps1 |
| **Chat ID** | Real Telegram chat ID | Never committed | Setup-Credentials.ps1 |
| **Server Names** | Example: MEDOC-SRV01 | Auto-detected or template | Config.template.ps1 |
| **File Paths** | Real paths | Placeholder paths | README.md examples |
| **Version Numbers** | Real versions (ezvit.11.02...) | Generic version format | README.md examples |

---

## Credentials You Need to Provide

### 1. Telegram Bot Token

**What it is:** API authentication token from Telegram BotFather

**Format:** `NUMERIC_ID:ALPHANUMERIC_TOKEN`

**Example (DO NOT USE):** `123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890`

**How to get:**

1. Open Telegram → [@BotFather](https://t.me/botfather)
2. Send `/newbot` command
3. Follow prompts to create new bot
4. Copy the token provided
5. **KEEP THIS PRIVATE!** This is like a password

**Where to put:** Use `Setup-Credentials.ps1` (NOT in Config.ps1)

```powershell
# SECURE: Use setup utility (stores encrypted)
.\utils\Setup-Credentials.ps1

# When prompted, enter your bot token
# It will be encrypted and saved securely
```

**DON'T do this (insecure):**

```powershell
# ❌ WRONG - Never put tokens in plain text config files
BotToken = "YOUR_BOT_TOKEN"  # INSECURE!
```

---

### 2. Telegram Chat ID

**What it is:** Unique identifier for the chat/channel to receive notifications

**Why it's encrypted (PII):** Chat ID is Personally Identifiable Information (PII) because it
uniquely identifies a person, organization, or group receiving notifications. Encrypting it
alongside the bot token (sensitive credential) protects against unauthorized access to
sensitive communication channels.

**Format:**

- Private chat: Positive number (e.g., `123456789`)
- Channel/Group: Negative number (e.g., `-1002825825746`)

**How to get (Recommended Method):**

The **getUpdates API method** works for all types of chats (private, group, or channel):

1. Send a test message to your bot or channel
2. Visit this URL (replace with your actual token):

   ```text
   https://api.telegram.org/bot{YOUR_BOT_TOKEN}/getUpdates
   ```

3. Look for the response containing: `"chat":{"id":YOUR_CHAT_ID}`
4. Copy the ID value (can be positive or negative)

**For Channels (Advanced Alternative):**

If you're having trouble with the API method for channels, you can also inspect the
browser:

1. Open your channel in Telegram Web
2. Check the URL: `https://web.telegram.org/k/?tgaddr=tg://resolve?domain=CHANNEL_NAME`
3. Right-click → Inspect → Network tab
4. Search network requests for `chat_id`

**Note:** The API method (getUpdates) is more reliable and works universally for all chat
types. Use the browser inspector only if the API method doesn't work for your specific
channel.

**Where to put:** Use `Setup-Credentials.ps1` (NOT in Config.ps1)

```powershell
# SECURE: Use setup utility (stores encrypted)
.\utils\Setup-Credentials.ps1

# When prompted, enter your chat ID
# It will be encrypted and saved securely
```

---

### 3. Server-Specific Settings

These are not sensitive and are set in config files:

| Setting | Description | Example | Auto-Detect |
|---------|-------------|---------|---|
| `ServerName` | Display name in messages | `"MY_SERVER"` | ✅ Yes (hybrid) |
| `MedocLogsPath` | Path to M.E.Doc logs directory | `"D:\MedocSRV\LOG"` | ❌ No |
| `CheckpointFile` | Checkpoint location | Auto-created in ProgramData | ✅ Yes (auto) |

---

## Security Best Practices

### ✅ DO

- ✅ Store `Config.ps1` in a **secure location** on the server
- ✅ Restrict file permissions on `Config.ps1` (readable only by SYSTEM and necessary accounts)
- ✅ Use **separate Telegram bot** per environment if possible
- ✅ Review audit logs in **Event Viewer** regularly
- ✅ Rotate Telegram bot token periodically (create new bot if compromised)
- ✅ Use **strong passwords** for server accounts running the task
- ✅ Enable **Windows Event Log** monitoring for errors

### ❌ DON'T

- ❌ Commit real credentials to git (this repo has placeholders)
- ❌ Share `Config.ps1` via email or unsecured channels
- ❌ Log credentials in Event Log (script doesn't, but verify before customizing)
- ❌ Expose bot token in script output or error messages
- ❌ Use same bot token across multiple environments
- ❌ Store credentials in script comments
- ❌ Leave bot token visible in Task Scheduler job definition

---

## File Permissions

### Recommended Permissions on Config.ps1

**Windows Server (NTFS):**

```text
SYSTEM: Full Control
Administrators: Modify
Network Service (if running task): Read & Execute
Everyone: No Access
```

**Command to set permissions:**

```powershell
# As Administrator
$path = "C:\Script\MedocUpdateCheck\Config.ps1"

# Remove inherited permissions
icacls $path /inheritance:r

# Add SYSTEM: Full Control
icacls $path /grant:r "SYSTEM:(F)"

# Add Administrators: Modify
icacls $path /grant:r "BUILTIN\Administrators:(M)"

# Verify
icacls $path
```

---

## Secret Rotation

### If Bot Token Is Compromised

1. **Immediately** create new bot with BotFather
2. Delete old bot with BotFather
3. Update `Config.ps1` with new token
4. Restart script to ensure new token is loaded
5. Check Event Log to see if old token was used after compromise

### If Chat ID Becomes Invalid

1. Leave old chat/channel
2. Get new Chat ID
3. Update `Config.ps1`
4. Test by running script manually

---

## Audit Trail & Event Log Monitoring

All actions are logged to Windows Event Log with specific Event IDs for easy monitoring and troubleshooting.

The module uses a centralized `MedocEventId` enum (defined in `lib/MedocUpdateCheck.psm1`) to
ensure consistency across all Event Log entries and function return values. This enum defines
all possible event IDs and their meanings.

### Event ID Reference

Event IDs are organized by category for easy filtering and monitoring in Windows Event Viewer. These correspond to the `MedocEventId` enum values:

#### Normal Flow (1000-1099)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1000** | Info | ✅ Success | All 3 update flags confirmed | Monitor daily - normal |
| **1001** | Info | ℹ️ No Update | No update in logs since checkpoint | Check next run |

#### Configuration Errors (1100-1199)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1100** | Error | ❌ Missing Key | Required config key absent | Fix Config.ps1, compare with Config.template.ps1 |
| **1101** | Error | ❌ Invalid Value | Invalid configuration value | Verify config key values |

#### Environment/Filesystem Errors (1200-1299)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1200** | Error | ❌ Planner.log Missing | Planner.log not found in M.E.Doc logs directory | Verify MedocLogsPath in config |
| **1201** | Error | ❌ Update Log Missing | update_YYYY-MM-DD.log not found after update trigger | Check M.E.Doc logs directory |
| **1202** | Error | ❌ Logs Dir Missing | M.E.Doc logs directory not found | Verify MedocLogsPath in config |
| **1203** | Error | ❌ Checkpoint Dir Failed | Cannot create checkpoint directory in ProgramData | Check ProgramData permissions |
| **1204** | Error | ❌ Encoding Error | Error reading logs with configured encoding | Verify EncodingCodePage setting |

#### Update Validation Failures (1300-1399)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1300** | Error | ❌ Flag 1 Failed | Infrastructure validation missing (IsProcessCheckPassed DI/AI) | Check M.E.Doc infrastructure components |
| **1301** | Error | ❌ Flag 2 Failed | Service restart unconfirmed (ZvitGrp startup) | Check service restart logs |
| **1302** | Error | ❌ Flag 3 Failed | Version not confirmed (version mismatch) | Verify update log completion |
| **1303** | Error | ❌ Multiple Flags Failed | Multiple flags missing | Full investigation required |

#### Notification Errors (1400-1499)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1400** | Error | ❌ Telegram API Error | Telegram API request rejected | Verify bot token and rate limits |
| **1401** | Error | ❌ Telegram Send Failed | Network error sending Telegram message | Check network connectivity and service status |

#### Checkpoint/State Errors (1500-1599)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1500** | Error | ❌ Checkpoint Write Failed | Cannot save checkpoint file | Check disk space and ProgramData permissions |

#### Unexpected Errors (1900+)

| ID | Level | Scenario | Meaning | Action |
|---|---|---|---|---|
| **1900** | Error | ❌ General Error | Unexpected/unhandled exception | Check script logs for details |

### Monitoring Strategy

**Daily checks** - Look for Event ID 1000:

- Indicates successful update checks
- Should appear regularly per scheduled task frequency

**Alert on errors** - Event IDs 1100+:

Configuration errors (1100-1199):

- **1100** - Config missing key: Fix Config.ps1, compare with template
- **1101** - Invalid config value: Verify config settings

Filesystem errors (1200-1299):

- **1200** - Planner.log missing: Verify MedocLogsPath in config
- **1201** - Update log missing: Check M.E.Doc logs directory
- **1202** - Logs directory missing: Verify MedocLogsPath in config
- **1203** - Checkpoint dir creation failed: Check ProgramData permissions
- **1204** - Encoding error: Verify EncodingCodePage setting

Update validation failures (1300-1399):

- **1300** - Flag 1 failed (infrastructure): Review M.E.Doc infrastructure components (DI/AI)
- **1301** - Flag 2 failed (service): Check ZvitGrp service restart logs
- **1302** - Flag 3 failed (version): Verify update log completion and version match
- **1303** - Multiple flags failed: Full investigation of update process

Notification errors (1400-1499):

- **1400** - Telegram API error: Verify bot token, check rate limits, API status
- **1401** - Telegram send error: Check network connectivity and Telegram service status

Checkpoint errors (1500-1599):

- **1500** - Checkpoint write failed: Check disk space and ProgramData permissions

Unexpected errors (1900+):

- **1900** - General error: Check logs and script execution details

**Normal patterns** - Event ID 1001:

- No update in logs since last check (normal, not an error)
- Continue monitoring on next scheduled run

**Query recent events (PowerShell 7+):**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 50
```

**Query only errors (PowerShell 7+):**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 2
} -MaxEvents 20
```

For more Event Log query examples, see [TESTING.md - Event Log Test](TESTING.md#7-event-log-test).

---

## Environment-Specific Configurations

### Development (if testing)

- Use test bot from BotFather
- Send messages to your private chat
- Safe to share code without `Config.ps1`

### Production

- Use dedicated production bot
- Send to production channel/chat
- **NEVER** share `Config.ps1`
- Store in secure location with restricted permissions

---

## Deploying Securely

When copying to new servers:

```powershell
# 1. Copy everything EXCEPT Config.ps1
robocopy "C:\Script\MedocUpdateCheck" "\\TARGET-SERVER\C$\Script\MedocUpdateCheck" /E /XF "Config.ps1"

# 2. Manually create Config.ps1 on target server with their credentials
# (Don't copy sensitive file across network)

# 3. Set restrictive permissions
Invoke-Command -ComputerName TARGET-SERVER {
    icacls "C:\Script\MedocUpdateCheck\Config.ps1" /inheritance:r
    icacls "C:\Script\MedocUpdateCheck\Config.ps1" /grant:r "SYSTEM:(F)"
}
```

---

## Repository Status

✅ **This repository contains NO real credentials**

- All Telegram tokens are placeholders
- All Chat IDs are placeholders
- All file paths are examples
- All server names are examples
- Safe to commit and share

**When customizing:**

1. Edit `Config.ps1` on the target server
2. Never commit edited `Config.ps1` to git
3. Use `.gitignore` to prevent accidental commits

Example `.gitignore`:

```gitignore
Config.ps1
last_run.txt
*.log
```

---

## Contact & Support

For security concerns or credential issues:

1. Check Event Log first (Event Viewer)
2. Review `Config.ps1` for invalid values
3. Test Telegram API manually with credentials
4. Check firewall/proxy doesn't block api.telegram.org
