# M.E.Doc Update Status Check

[![Automated Tests](https://github.com/pbv7/medoc-update-check/actions/workflows/tests.yml/badge.svg)](https://github.com/pbv7/medoc-update-check/actions/workflows/tests.yml)

Automated script to monitor M.E.Doc server updates and send Telegram notifications.

## ⚠️ PowerShell 7+ Required

**This tool requires PowerShell 7.0 or later.** PowerShell 5.1 is not supported.

**Why?** PowerShell 5.1 reached end-of-support in 2019. PowerShell 7+ is actively maintained by Microsoft with security updates and modern features.

**Installation:** Follow Microsoft's official [PowerShell Installation Guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

**Verify installation:**

```powershell
pwsh -Command '$PSVersionTable.PSVersion'
# Expected output: 7.x or higher
```

If PowerShell 7+ is not found when running `Setup-ScheduledTask.ps1`, the script will fail with a clear error directing you to install it.

## ⚠️ Testing & Platform Support Note

**Intended Platform:** Windows (M.E.Doc servers in production)

**Development & Testing:** Primarily on macOS and Linux with cross-platform PowerShell 7

**Testing Coverage:**

- ✅ Comprehensive testing on macOS/Linux (CI/CD pipeline)
- ⚠️ Limited testing on Windows (production usage only on developer's servers)
- ⚠️ Windows-specific features (Event Log, Task Scheduler) need broader user validation

**If you use this on Windows servers:** Please report any issues you encounter.
Windows-specific behavior (Event Log integration, Task Scheduler execution, SYSTEM user
context, CMS certificate handling) may benefit from additional testing in your environment
before wide deployment.

See [TESTING.md - Platform Support](TESTING.md) for detailed notes on cross-platform behavior.

---

## 📚 Documentation Map

This project has comprehensive documentation. Choose your entry point based on your role:

| Your Role | Start Here | Learn |
|-----------|-----------|-------|
| **Want to deploy quickly?** | [DEPLOYMENT.md](DEPLOYMENT.md) | Step-by-step setup guide with all deployment options |
| **Want to test changes?** | [TESTING.md](TESTING.md) | Test procedures, message formats, test data |
| **Want to contribute code?** | [CONTRIBUTING.md](CONTRIBUTING.md) | Development guidelines, commit standards, testing |
| **Concerned about security?** | [SECURITY.md](SECURITY.md) | Credential handling, Event Log, best practices |
| **AI coding agent?** | [AGENTS.md](AGENTS.md) | Quick reference (also [CLAUDE.md](CLAUDE.md)) + 5 specialized guides |
| **Need quick overview?** | [README.md](README.md) (you are here) | Project overview, features, example messages |

### AI Agent Guides (For Claude, Copilot, Cursor, Codeium, etc.)

Start with [AGENTS.md](AGENTS.md) (or [CLAUDE.md](CLAUDE.md) symlink), then navigate to
specialized guides as needed:

- **[AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md)** - Code style, naming conventions,
  PS7+ features, removed cmdlets
- **[AGENTS-TESTING.md](AGENTS-TESTING.md)** - Testing procedures, Pester syntax, enum usage
- **[AGENTS-SECURITY.md](AGENTS-SECURITY.md)** - Security best practices, PII concerns,
  credential handling
- **[AGENTS-DOCUMENTATION.md](AGENTS-DOCUMENTATION.md)** - Documentation maintenance, avoiding
  stale docs
- **[AGENTS-TOOLS-AND-WORKFLOW.md](AGENTS-TOOLS-AND-WORKFLOW.md)** - Tool selection, git
  workflow, CI/CD

---

## Folder Structure

```text
MedocUpdateCheck/
├── Run.ps1                          # Main entry point (universal, don't edit)
├── lib/
│   └── MedocUpdateCheck.psm1        # Core reusable module (universal)
├── configs/                         # Configuration files (per-server)
│   └── Config.template.ps1          # Template for new servers (copy and customize)
├── utils/                           # Utility scripts
│   └── Setup-ScheduledTask.ps1      # Task Scheduler automation helper
├── tests/                           # Automated tests
│   ├── Run-Tests.ps1                # Test runner script
│   ├── MedocUpdateCheck.Tests.ps1   # Pester test cases
│   ├── test-data/                   # Sample log files
│   └── README.md                    # Testing guide
├── last_run_server01.txt            # Checkpoint for server 1 (auto-created)
├── last_run_server02.txt            # Checkpoint for server 2 (auto-created)
├── SECURITY.md                      # Security & credentials guide
├── CODE_OF_CONDUCT.md               # Community guidelines
├── LICENSE                          # Apache 2.0 license
├── NOTICE                           # Attribution & dependencies
├── TESTING.md                       # Comprehensive testing guide
└── README.md                        # This file
```

## Quick Start

For complete step-by-step deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

### 1. Get the Code

Choose one method:

- **Automatic download on target server:** Use the API-based approach in [DEPLOYMENT.md - Section 1, Option A](DEPLOYMENT.md#option-a-download-automatically-recommended-for-remote-servers)
- **Manual download:** Download from [Latest Release](https://github.com/pbv7/medoc-update-check/releases/latest)
- **Copy from local machine:** Use robocopy or RDP file transfer

### 2. Setup Credentials (SYSTEM User Compatible)

**IMPORTANT:** Store sensitive credentials (BotToken, ChatId) securely. Credentials are
encrypted with CMS (Cryptographic Message Syntax) using a self-signed LocalMachine
certificate and can be read by SYSTEM user in Task Scheduler.

Run as Administrator on the target server:

```powershell
cd C:\Apps\medoc-update-check
.\utils\Setup-Credentials.ps1
```

This will:

- ✅ Create self-signed certificate in LocalMachine store (if missing)
- ✅ Prompt for Bot Token and Chat ID
- ✅ Encrypt credentials using CMS with 2048-bit RSA key
- ✅ Save to `$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms`
- ✅ Restrict file permissions (SYSTEM + Administrators only)
- ✅ Certificate auto-rotates if expiring (< 30 days)

**Non-interactive setup** (for scripted deployment):

```powershell
.\utils\Setup-Credentials.ps1 -BotToken "123456:ABC..." -ChatId "-1002825825746"
```

### 3. Configure for Your Servers

Choose the number of servers you need to monitor:

#### Single Server Setup

Copy and edit the template with your actual server hostname:

```powershell
# Copy using your server's hostname automatically
cp configs/Config.template.ps1 "configs/Config-$env:COMPUTERNAME.ps1"
```

The config file includes:

- **Hybrid ServerName auto-detection** (uses environment variable or computer name)
- **Automatic credential loading** from encrypted credentials file

```powershell
# ServerName auto-detection (default, recommended)
# Strategy: Check in order (first match wins):
# 1. $env:MEDOC_SERVER_NAME environment variable (if set by admin/automation)
# 2. $env:COMPUTERNAME - Windows hostname (fallback)
# 3. Explicit override (uncomment if you need custom name):
# $serverName = "MY_SERVER_NAME"

# Credentials are automatically loaded from encrypted CMS file:
# $env:ProgramData\MedocUpdateCheck\credentials\telegram.cms
```

Minimal config needed:

```powershell
$config = @{
    ServerName = $env:COMPUTERNAME  # Auto-detected
    MedocLogsPath = "D:\MedocSRV\LOG"  # Directory containing both Planner.log and update_*.log
    BotToken = $telegramCreds.BotToken  # Loaded from encrypted file
    ChatId = $telegramCreds.ChatId      # Loaded from encrypted file

    # Optional: checkpoint file location
    # If not specified, uses $env:ProgramData\MedocUpdateCheck\checkpoints\
    # LastRunFile = "$env:ProgramData\MedocUpdateCheck\checkpoints\last_run_server01.txt"
}
```

#### Multiple Servers Setup

For each server you want to monitor:

1. **Copy template with server hostname:**

   ```powershell
   # Copy using your server's hostname automatically
   cp configs/Config.template.ps1 "configs/Config-$env:COMPUTERNAME.ps1"
   ```

2. **Edit with your server settings:**

   ```powershell
   # Edit: MedocLogsPath (path to M.E.Doc logs directory), any server-specific options
   ```

3. **Create Task Scheduler task:**

   ```powershell
   .\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"
   ```

Repeat for each server. Example:

```powershell
# Server 1 - On MAINOFFICE server:
cp configs/Config.template.ps1 "configs/Config-$env:COMPUTERNAME.ps1"
# ... edit the config file ...
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Server 2 - On WAREHOUSE server:
cp configs/Config.template.ps1 "configs/Config-$env:COMPUTERNAME.ps1"
# ... edit the config file ...
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"
```

Each server needs:

- Its own config file (copy from template, customize)
- A separate Task Scheduler task that calls the specific config
- (Checkpoint files are auto-created in: `$env:ProgramData\MedocUpdateCheck\checkpoints\`)

For detailed Task Scheduler setup, see [DEPLOYMENT.md - Step 5: Create Scheduled Task](DEPLOYMENT.md#-step-5-create-scheduled-task).

## Configuration

Each server config is created by copying `configs/Config.template.ps1` and customizing it for your server.

### Required Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `ServerName` | Display name in Telegram messages | `"YOUR_SERVER_NAME"` |
| `MedocLogsPath` | Path to M.E.Doc logs directory | `"D:\MedocSRV\LOG"` (contains both Planner.log and update_*.log) |
| `BotToken` | Telegram bot API token from BotFather | `"NUMERIC_ID:ALPHANUMERIC_TOKEN"` (keep private!) |
| `ChatId` | Telegram chat or channel ID | `"YOUR_CHAT_ID_HERE"` (positive or negative number) |

### Optional Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `LastRunFile` | Auto-generated | Checkpoint file path for tracking processed updates (prevents duplicate notifications). If not provided, auto-generated in `$env:ProgramData\MedocUpdateCheck\checkpoints\last_run_SANITIZED_SERVERNAME.txt` |
| `EncodingCodePage` | 1251 | Log file encoding (1251=Windows-1251, 65001=UTF-8) |
| `EventLogSource` | "M.E.Doc Update Check" | Windows Event Log source name |

### LastRunFile Auto-Generation

When `LastRunFile` is not specified, the script automatically generates the checkpoint filename by sanitizing the `ServerName`:

- **Sanitization Rule:** Non-alphanumeric characters (except hyphens) are replaced with underscores
  - Example: `MEDOC-SRV01` → `last_run_MEDOC-SRV01.txt` (hyphen preserved)
  - Example: `MEDOC@SRV#01` → `last_run_MEDOC_SRV_01.txt` (@ and # replaced)
  - Example: `СервМедок` (Cyrillic) → `last_run________________.txt` (each character replaced)

- **Directory:** `$env:ProgramData\MedocUpdateCheck\checkpoints\`
- **Auto-created:** Directory and file are automatically created on first run
- **Permissions:** Restricted to SYSTEM user and Administrators

This ensures ServerName can contain special characters without causing file system errors.

## Getting Telegram Credentials

For comprehensive instructions on obtaining and securely storing Telegram credentials, see [SECURITY.md - Credentials You Need to Provide](SECURITY.md#credentials-you-need-to-provide).

### 1. Create Bot with BotFather

- Open Telegram and find [@BotFather](https://t.me/botfather)
- Send `/newbot`
- Follow instructions to create bot
- Copy the **Bot Token** (format: `NUMERIC_ID:ALPHANUMERIC_TOKEN` - KEEP THIS PRIVATE!)

### 2. Get Chat ID

#### Option A: Private Chat

- Send message to your bot
- Visit: `https://api.telegram.org/bot{YOUR_BOT_TOKEN}/getUpdates`
- Look for `"chat":{"id":YOUR_CHAT_ID}` in the response

#### Option B: Channel/Group

- Add bot to channel/group as administrator
- Send message to channel
- Visit: `https://api.telegram.org/bot{YOUR_BOT_TOKEN}/getUpdates`
- Channel ID format: negative number (e.g., `-1002825825746`)
- Copy the chat ID from response and use in Config.ps1

**Next:** Use `Setup-Credentials.ps1` to securely encrypt these values (see [SECURITY.md](SECURITY.md#secure-credential-storage-system-user-compatible))

## Error Handling

### Console Errors (when run manually)

```powershell
# Run with your config using server's hostname
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Or with verbose output
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1" -Verbose
```

### Windows Event Log (when run from Task Scheduler)

All actions are logged to Windows Event Log. View events in Event Viewer:

```text
Event Viewer → Windows Logs → Application → Filter by Source: "M.E.Doc Update Check"
```

**Event ID Reference:**

For complete Event ID reference with troubleshooting steps, see [SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference).

**Event ID Categories:**

- **1000-1099** - Normal flow (success, no update)
- **1100-1199** - Configuration errors (missing keys, invalid values)
- **1200-1299** - Environment/filesystem errors (missing logs, directory issues)
- **1300-1399** - Update validation failures (missing flags)
- **1400-1499** - Notification errors (Telegram API, send failures)
- **1500-1599** - Checkpoint/state persistence errors
- **1900+** - Unexpected/general errors

### PowerShell Event Log Queries

For comprehensive Event Log query examples (view recent, errors, specific dates, etc.), see [TESTING.md - Event Log Query Examples](TESTING.md#event-log-query-examples).

## Deploying to Multiple Servers

### Same Folder, Multiple Configs (Recommended)

When monitoring multiple M.E.Doc servers from one location:

```powershell
# Copy folder once to shared location or local folder
robocopy "C:\Source\MedocUpdateCheck" "\\YOUR_SERVER_NAME\C$\Script\MedocUpdateCheck" /E
```

Then create multiple Task Scheduler tasks, each pointing to a different config:

```powershell
# Task 1: Main Office at 5:10 AM
Register-ScheduledTask -TaskName "M.E.Doc Check - MainOffice" `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Script\MedocUpdateCheck\Run.ps1" -ConfigPath ".\configs\Config-MainOffice.ps1"' `
        -WorkingDirectory 'C:\Script\MedocUpdateCheck') `
    -Trigger (New-ScheduledTaskTrigger -Daily -At 5:10AM) `
    -RunLevel Highest

# Task 2: Warehouse at 5:15 AM
Register-ScheduledTask -TaskName "M.E.Doc Check - Warehouse" `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Script\MedocUpdateCheck\Run.ps1" -ConfigPath ".\configs\Config-Warehouse.ps1"' `
        -WorkingDirectory 'C:\Script\MedocUpdateCheck') `
    -Trigger (New-ScheduledTaskTrigger -Daily -At 5:15AM) `
    -RunLevel Highest
```

### Each Server on Its Own Computer

Copy the entire folder to each server and use the default config:

```powershell
# Copy to MainOffice server
robocopy "C:\Source\MedocUpdateCheck" "\\MAINOFFICE\C$\Script\MedocUpdateCheck" /E

# Copy to Warehouse server
robocopy "C:\Source\MedocUpdateCheck" "\\WAREHOUSE\C$\Script\MedocUpdateCheck" /E

# On each server, copy Config.template.ps1 to Config-$env:COMPUTERNAME.ps1 (automatic hostname) and customize
# Then create one Task Scheduler task per server using the customized config
```

### Future - Refactor to Shared Module

When ready to manage code from one location:

- Place `lib/MedocUpdateCheck.psm1` on SMB share
- Each server keeps only `Run.ps1` and `configs/`
- Module references network path
- Single code update affects all servers

## Troubleshooting

### Script Won't Run from Task Scheduler

- ✓ Check `last_run.txt` has write permissions
- ✓ Check log file path is accessible from that server
- ✓ Check bot token and chat ID are correct
- ✓ Run task as SYSTEM or elevated account

### No Messages in Telegram

- Check bot token in Config.ps1 is correct and not expired
- Check chat ID is correct (test manually with curl or Postman)
- Verify bot has permission to send messages to the chat/channel
- Check Windows Event Log for errors (Event ID 1002, 1003)
- Test API manually: Replace `{TOKEN}` and `{CHAT_ID}` with actual values:

  ```bash
  curl https://api.telegram.org/bot{YOUR_BOT_TOKEN}/sendMessage -d chat_id={YOUR_CHAT_ID} -d text="test"
  ```

### Wrong Update Status Reported

- Check log file path is correct
- Check log file encoding matches (1251 vs 65001)
- Manually review `D:\MedocSRV\LOG\Planner.log`

### Module Load Errors

- Ensure `lib` folder exists with `MedocUpdateCheck.psm1`
- Check file is not corrupted
- Try: `Test-ModuleManifest ".\lib\MedocUpdateCheck.psm1"`

## Manual Testing

```powershell
# Navigate to script folder
cd "C:\Script\MedocUpdateCheck"

# Test configuration loads correctly
. ".\Config.ps1"
$config

# Test module loads
Import-Module ".\lib\MedocUpdateCheck.psm1" -Force
Get-Module MedocUpdateCheck

# Test update check function (dual-log validation)
Test-UpdateOperationSuccess -MedocLogsPath "D:\MedocSRV\LOG"

# Run entire check with server's hostname
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Check Event Log (PowerShell 7+)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 5
```

## Log File Requirements

### Expected Log Format

M.E.Doc uses two log files with different timestamp formats:

#### Planner.log (Update Planning Log)

```text
dd.MM.yyyy H:mm:ss Event Text
25.09.2025 5:00:00 Нові оновлення відсутні
25.09.2025 5:00:00 Завантаження оновлення ezvit.11.02.183-11.02.184.upd
25.09.2025 5:07:12 Операція виконана успішно
```

**Timestamp format:** 4-digit year (DD.MM.YYYY)

#### update_*.log (Update Execution Log)

```text
dd.MM.yy H:mm:ss.mmm XXXXXXXX LEVEL Message
25.09.25 11:32:14.150 00000001 INFO    IsProcessCheckPassed DI: True, AI: True
25.09.25 11:45:15.200 00000001 INFO    Службу ZvitGrp запущено з підвищенням прав
25.09.25 11:47:15.300 00000001 INFO    Версія програми - 184
```

**Timestamp format:** 2-digit year (DD.MM.YY) with milliseconds
**Log fields:** 2-digit year, milliseconds, 8-digit ID, log level, message

**Note:** The different timestamp formats are intentional - Planner.log uses 4-digit years
while update_*.log uses 2-digit years. Both represent the same calendar dates when parsed
(e.g., 25.09.2025 and 25.09.25 both mean 25 September 2025).

### Encoding

- Default: Windows-1251 (Cyrillic)
- Override in Config.ps1 if different

## Example Telegram Messages

Telegram messages use English with structured data for clarity and international compatibility. Emoji provide quick visual status indication.

For detailed message format examples, see [TESTING.md - Message Format Reference](TESTING.md#message-format-reference).

### ✅ Update Successful

```text
✅ UPDATE OK | MY-MEDOC-SERVER
Version: 11.02.183 → 11.02.184
Started: 28.10.2025 05:15:23
Completed: 28.10.2025 05:17:20
Duration: 1 min 57 sec
Checked: 28.10.2025 12:33:45
```

### ❌ Update Failed

When any of the three success flags are missing, Telegram notification shows:

```text
❌ UPDATE FAILED | MY-MEDOC-SERVER
Version: 11.02.183 → 11.02.184
Started: 28.10.2025 11:32:14
Failed at: 28.10.2025 11:47:15
Flag1 (Infrastructure): ✗
Flag2 (Service Restart): ✓
Flag3 (Version Confirmed): ✓
Reason: Missing success flags
Checked: 28.10.2025 11:50:06
```

The message lists the status of each validation flag (✓ = passed, ✗ = failed) to help identify
the root cause. Windows Event Log receives additional details through separate flag fields
(Flag1, Flag2, Flag3) for automated alerting.

### ℹ️ No Updates

```text
ℹ️ NO UPDATE | MY-MEDOC-SERVER
Checked: 28.10.2025 12:33:45
```

## Module Functions

The M.E.Doc Update Check module exports 6 public functions for use in custom scripts:

### Core Functions

**`Test-UpdateOperationSuccess`** - Analyzes M.E.Doc logs to determine if an update succeeded

Returns status object with fields:

- `Status`: "Success", "NoUpdate", or "Error"
- `ErrorId`: MedocEventId enum value (1000-1900+) for categorizing the result
- For **Success**: Also includes Version info, Timestamps, and Flag details
- For **NoUpdate**: Minimal (just Status + ErrorId)
- For **Error**: Status + ErrorId + error Message

Supports checkpoint filtering (since parameter) to avoid processing same updates twice.

**`Invoke-MedocUpdateCheck`** - Main orchestration function

- Calls Test-UpdateOperationSuccess to get update status
- Formats messages for Telegram and Event Log based on status
- Writes to Windows Event Log with appropriate EventId (using MedocEventId enum)
- Sends Telegram notification with formatted message
- Returns $true on success, $false on error

### Formatting Functions

**`Format-UpdateTelegramMessage`** - Creates Telegram notification text based on status

Returns based on status:

- **Success**: `✅ UPDATE OK | ServerName\nVersion: X → Y\nStarted: time\nCompleted: time\nDuration: X min Y sec\nChecked: time`
- **NoUpdate**: `ℹ️ NO UPDATE | ServerName\nChecked: time` (informational, not an error)
- **Error**: `❌ UPDATE FAILED | ServerName\nVersion: X → Y\nValidation Failures: [missing flags]\nReason: [error]\nChecked: time`

**`Format-UpdateEventLogMessage`** - Creates Event Log entry text based on status

Returns key=value format based on status:

- **Success**: `Server=X | Status=UPDATE_OK | FromVersion=X | ToVersion=Y | UpdateStarted=time | UpdateCompleted=time | Duration=X | CheckTime=time`
- **NoUpdate**: `Server=X | Status=NO_UPDATE | CheckTime=time`
- **Error**: `Server=X | Status=UPDATE_FAILED | FromVersion=X | ToVersion=Y | Flag1=value | Flag2=value | Flag3=value | Reason=[error] | CheckTime=time`

### Utility Functions

**`Get-VersionInfo`** - Extracts version information from M.E.Doc logs

- Parses version strings like "11.02.185-11.02.186.upd"
- Returns object with FromVersion and ToVersion properties
- Used internally by Test-UpdateOperationSuccess

**`Write-EventLogEntry`** - Writes messages to Windows Event Log with structured EventId

- Accepts Message (required) and EventId (MedocEventId enum value preferred, defaults to 1000)
- Creates event source if missing (requires admin)
- Logs with appropriate level (Information/Warning/Error)
- Respects platform limitations (non-Windows systems safely skip Event Log)
- EventLog entries use centralized MedocEventId enum for consistent event filtering and monitoring

### Event ID Reference (Quick Lookup)

All Event Log entries use standardized EventIDs for monitoring and troubleshooting. For complete details, see [SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference):

**Quick Reference:**

| ID | Status | Meaning |
|---|---|---|
| **1000** | ✅ Info | Update completed successfully |
| **1001** | ℹ️ Info | No update detected (normal) |
| **1100-1101** | ❌ Error | Configuration errors |
| **1200-1204** | ❌ Error | Filesystem/environment errors |
| **1300-1303** | ❌ Error | Update validation failures |
| **1400-1401** | ❌ Error | Telegram/notification errors |
| **1500** | ❌ Error | Checkpoint write failed |
| **1900** | ❌ Error | Unexpected/general error |

**For detailed explanations and troubleshooting steps for each EventID, see [SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference).**

---

## Features

- ✅ Analyzes M.E.Doc log files
- ✅ Determines update success/failure
- ✅ Sends Telegram notifications
- ✅ Checkpoint-based filtering (avoids duplicates)
- ✅ Windows Event Log integration
- ✅ Graceful error handling
- ✅ Configurable encoding (Windows-1251, UTF-8, etc.)
- ✅ Configurable update timeout
- ✅ Single-server deployment model
- ✅ Ready for SMB-based shared module (future iteration)

## Documentation

For different audiences, see:

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Step-by-step deployment checklist for production (start
  here!)
- **[SECURITY.md](SECURITY.md)** - Security procedures, credential management, and best
  practices
- **[TESTING.md](TESTING.md)** - How to run tests and validate the system
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - How to contribute to this project (code standards,
  testing, documentation, git practices - for developers and community members)

## Version & Release History

For detailed release notes and version history, check [GitHub Releases](https://github.com/pbv7/medoc-update-check/releases).

View available versions:

```powershell
# See all released versions
git tag -l

# See current version
git describe --tags
```

---

## Glossary

Common terms used throughout this project and documentation:

- **M.E.Doc** - Ukrainian enterprise accounting and tax software (target application being monitored)

- **Server / Target Server** - Windows server running M.E.Doc software that we monitor for updates

- **Update** - M.E.Doc software version change (e.g., from version 11.02.183 to 11.02.184)

- **Event Log / Application Event Log** - Windows Application Event Log where script writes status messages (viewable in Event Viewer)

- **Telegram** - Messaging platform used to send notifications about updates (separate from Event Log)

- **Telegram Message** - Human-readable notification sent via Telegram with emoji and structured text (e.g., "✅ UPDATE OK")

- **Event Log Message** - Structured key=value format message written to Windows Event Log (machine-readable, for compliance)

- **Checkpoint / Checkpoint File** - Stores timestamp of last successful run to prevent
  duplicate Telegram notifications

- **Config File** - Server-specific configuration file (Config-ComputerName.ps1) containing
  server name, Telegram credentials, log file paths

- **CMS / Cryptographic Message Syntax** - Certificate-based encryption method used to encrypt
  Telegram credentials at machine level (supported by Windows Task Scheduler SYSTEM user)

- **Self-signed Certificate** - X.509 certificate generated locally for encrypting
  credentials; stored in LocalMachine certificate store with 5-year validity and
  NonExportable private key

- **Task Scheduler** - Windows service that runs this script on a schedule (daily, weekly, etc.)

- **SYSTEM User** - Special Windows account used by Task Scheduler for running scheduled tasks with elevated permissions

- **Windows-1251 Encoding** - Cyrillic character encoding used by M.E.Doc logs (not UTF-8)

- **PowerShell 7+** - Modern PowerShell version (required, not PowerShell 5.1)

- **Get-WinEvent** - PowerShell 7+ cmdlet for reading Event Log (replacement for deprecated Get-EventLog)

---

## Authors

- **Bohdan Potishuk** - Lead developer
- **Dmytro Kravchuk** - Co-author

## License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) file for details.

This project includes a [NOTICE](NOTICE) file with additional information about dependencies and credits.

### Exit Codes

`Run.ps1` returns exit codes for Task Scheduler alerting:

- **0** — Update check completed normally (Success or NoUpdate)
- **1** — Operational or configuration error
- **2** — Update detected but validation failed

Operators should configure alerts on exit codes 1 and 2. For detailed documentation, see [DEPLOYMENT.md - Exit Codes for Scheduling/Monitoring](DEPLOYMENT.md#exit-codes-for-schedulingmonitoring).
