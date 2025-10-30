# Deployment Checklist for M.E.Doc Update Check

This document provides a step-by-step checklist for deploying M.E.Doc Update Check to production servers.

**Related Documentation:**

- **Quick overview?** See [README.md](README.md)
- **Security & credentials details?** See [SECURITY.md](SECURITY.md)
- **Testing & validation?** See [TESTING.md](TESTING.md)
- **Troubleshooting?** See [README.md - Troubleshooting](README.md#troubleshooting) and [SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference)

---

## 1. Quick Start: Getting the Code

Choose one method to obtain the latest release:

### Option A: Download Automatically (Recommended for Remote Servers)

Run this on the target server to download and extract the latest release:

```powershell
# Choose location for operational scripts
New-Item -ItemType Directory -Path 'C:\Apps' | Out-Null   # If missing
Set-Location 'C:\Apps'

# Download and extract latest release
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/pbv7/medoc-update-check/releases/latest'
$version = $release.tag_name
$zipUrl = $release.zipball_url
$zipName = "medoc-update-check-$version.zip"

Invoke-WebRequest -Uri $zipUrl -OutFile $zipName
Expand-Archive -Path $zipName -DestinationPath . -Force

# Find extracted folder and rename it
$extractedFolder = Get-ChildItem -Directory |
    Where-Object { $_.Name -match 'pbv7-medoc-update-check' } |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1

if ($extractedFolder) {
    Move-Item -Path $extractedFolder.FullName -Destination "./medoc-update-check" -Force
    Write-Host "✅ Extracted: $($extractedFolder.Name) → medoc-update-check"
} else {
    Write-Host "❌ Error: No extracted folder found"
}

# Cleanup zip file
Remove-Item $zipName -Force
```

### Option B: Download Manually

Visit [Latest Release page](https://github.com/pbv7/medoc-update-check/releases/latest), download the ZIP file, and extract manually.

---

## 2. Pre-Deployment Requirements

**Complete these steps BEFORE deploying to any server.**

### ☐ 2.1 Telegram Bot & Chat ID Setup

You need a Telegram bot token and chat ID for notifications.

#### Create Telegram Bot

```powershell
# Instructions:
# 1. Open Telegram → Search for @BotFather
# 2. Send: /newbot
# 3. Follow prompts to create bot
# 4. Copy Bot Token (format: 123456:ABCD...)
# 5. Save to secure location (NOT in code or configs)
```

#### Get Telegram Chat ID

```powershell
# Instructions:
# 1. Send a test message to your bot
# 2. Visit: https://api.telegram.org/bot{YOUR_BOT_TOKEN}/getUpdates
# 3. Find: "chat":{"id":YOUR_CHAT_ID}
# 4. Save Chat ID (positive for private, negative for channel)
```

**References:**

- See [SECURITY.md - Telegram Bot Token](SECURITY.md#1-telegram-bot-token) for detailed instructions
- See [README.md - Getting Telegram Credentials](README.md#getting-telegram-credentials) for visual guide
- See [SECURITY.md - Telegram Chat ID](SECURITY.md#2-telegram-chat-id) for detailed instructions

### ☐ 2.2 Environment Checklist

Verify your environment meets requirements:

- ☐ Windows Server (2016 or later)
- ☐ PowerShell 7.0 or later installed

**Check PowerShell version:**

```powershell
pwsh -Command '$PSVersionTable.PSVersion'
# Expected output: 7.x or higher
```

If not installed, follow [Microsoft's Installation Guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

- ☐ Access to M.E.Doc logs directory on target server
- ☐ Network access to Telegram API (api.telegram.org)
- ☐ Administrator access to target server (for setup only)

### ☐ 2.3 Task Scheduler Principal

For automated scheduling, the script runs as:

- **SYSTEM user** (Recommended)
  - No credential management needed
  - Works for local log file access on the server
  - Highest privilege level for Task Scheduler

---

## 3. Single Server Deployment

Follow these steps sequentially for each server.

### ☐ Step 1: Copy Project Files

Get the code to the target server using one of these methods:

#### Method A: From Local Machine via Network Share

Remote deployment from your local machine:

```powershell
# From your local machine, copy to target server
robocopy "C:\Source\MedocUpdateCheck" "\\TARGET_SERVER\C$\Script\MedocUpdateCheck" /E

# Or use RDP/File Explorer to copy manually
```

#### Method B: Download on Target Server

If you already downloaded on the target server (see Section 1, Option A):

```powershell
# If you already downloaded using Option A above, this step is complete
# Verify files exist in C:\Apps\medoc-update-check
```

**Verify files copied correctly:**

- ☐ `Run.ps1` exists
- ☐ `lib\MedocUpdateCheck.psm1` exists
- ☐ `configs\Config.template.ps1` exists
- ☐ `utils\Setup-Credentials.ps1` exists
- ☐ `utils\Setup-ScheduledTask.ps1` exists

**References:**

- See [README.md - Quick Start - Step 1](README.md#1-copy-folder-to-server)

### ☐ Step 2: Setup Credentials Securely

Run on the target server as Administrator:

```powershell
# Open PowerShell as Administrator
cd C:\Apps\medoc-update-check

# Interactive mode (prompts for credentials)
.\utils\Setup-Credentials.ps1

# OR non-interactive mode
.\utils\Setup-Credentials.ps1 -BotToken "YOUR_BOT_TOKEN" -ChatId "YOUR_CHAT_ID"
```

#### Verify Setup

- ☐ Script completes without errors
- ☐ Certificate created: `Cert:\LocalMachine\My` (CN=M.E.Doc Update Check Credential Encryption)
- ☐ File created: `$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms`
- ☐ Output shows "✅ Credentials Setup Complete!"

#### What It Does

- ✅ Creates self-signed certificate in LocalMachine store (if missing)
- ✅ Encrypts credentials with CMS using certificate public key
- ✅ Works with SYSTEM user in Task Scheduler
- ✅ Restricts file permissions (SYSTEM + Administrators only)

**References:**

- See [SECURITY.md - Secure Credential Storage](SECURITY.md#secure-credential-storage-system-user-compatible)
- See [README.md - Quick Start - Step 2](README.md#2-setup-credentials-system-user-compatible)

### ☐ Step 3: Configure Server Settings

Run on the target server as Administrator:

Copy and customize the config template for your server:

```powershell
# Change to the medoc-update-check folder
cd C:\Apps\medoc-update-check

# Copy the template using your server's hostname automatically
# No need to manually type your server name - it uses $env:COMPUTERNAME
cp configs\Config.template.ps1 "configs\Config-$env:COMPUTERNAME.ps1"

# Then edit the config file with correct paths
# Update this line with actual path to M.E.Doc logs directory
MedocLogsPath = "D:\MedocSRV\LOG"

# Optional: Set custom server name (if not using auto-detect)
# Uncomment and modify:
# $serverName = "MY_CUSTOM_SERVER_NAME"

# Leave credentials as-is (auto-loaded from encrypted file)
# DO NOT edit BotToken or ChatId here
```

#### How It Works

The `$env:COMPUTERNAME` variable automatically gets your server's hostname, so the config filename will match your server name:

- If server name is `MAINOFFICE-01` → creates `Config-MAINOFFICE-01.ps1`
- If server name is `WAREHOUSE-DB` → creates `Config-WAREHOUSE-DB.ps1`
- If server name is `BRANCH-02` → creates `Config-BRANCH-02.ps1`

This automatically creates descriptive filenames that identify which config belongs to which server without manual typing.

#### Configuration Verification

- ☐ MedocLogsPath is correct
- ☐ Path is accessible from SYSTEM user context
- ☐ File contains no plain text credentials

#### ServerName Options

- ☐ Auto-detect from `$env:COMPUTERNAME` (default)
- ☐ Auto-detect from `$env:MEDOC_SERVER_NAME` if set
- ☐ Explicit override in config (uncomment line)

**References:**

- See [SECURITY.md - Server Name Auto-Detection](SECURITY.md#server-name-auto-detection)
- See [README.md - Quick Start - Step 3](README.md#3-configure-for-your-servers)

### ☐ Step 4: Test Manually

Run the script as Administrator to verify it works:

```powershell
cd C:\Apps\medoc-update-check
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"
```

#### Expected Results

- ☐ Script runs without errors
- ☐ Telegram message received in your chat
- ☐ Event Log entry created (Event ID 1000 = success, or 1001 for no update)

#### Troubleshooting Steps

- If no Telegram message: Check Event Log for errors (Event ID 1400-1401 for Telegram errors)
- If credential error: Verify Setup-Credentials.ps1 completed successfully
- For complete EventID reference, see [SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference)
- See [README.md - Troubleshooting](README.md#troubleshooting)

#### Verify Event Log

```powershell
# Check for successful message send (PowerShell 7+)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 1
```

**References:**

- See [README.md - Step 5: Test Scheduled Task](README.md#step-5-test-scheduled-task)
- See [README.md - Troubleshooting](README.md#troubleshooting)

### ☐ Step 5: Create Scheduled Task

Run as Administrator:

#### PowerShell 7+ Required

Before running the setup script, verify PowerShell 7+ is installed:

```powershell
pwsh -Command '$PSVersionTable.PSVersion'
# Expected output: 7.x or higher
```

If not installed, follow [Microsoft's Installation Guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

The setup script will automatically detect PowerShell 7+ and create the task to use it. If
PowerShell 7+ is not found, the script will fail with a clear error message.

#### Setup Command

```powershell
cd C:\Apps\medoc-update-check

# Automated setup (runs as SYSTEM user with highest privileges)
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Optional: Specify custom execution time
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1" -ScheduleTime "14:30"
```

#### Task Verification

- ☐ Output shows "✅ Task Scheduler Setup Complete!"
- ☐ Task appears in Task Scheduler
- ☐ Task is scheduled for correct time

#### Task Details

- ✅ Daily scheduled task
- ✅ Runs at specified time (default: 08:00)
- ✅ Runs as SYSTEM user with highest privileges
- ✅ Auto-restarts if server reboots

**References:**

- See [README.md - Step 6: Set Up Automated Scheduling](README.md#step-6-set-up-automated-scheduling)

### ☐ Step 6: Final Verification

#### Verify Task Scheduler Configuration

```powershell
# 1. Find the task "M.E.Doc Update Check"
# 2. Right-click → Properties → Check all settings
# 3. Right-click → Run to test immediately
```

#### Check Event Log

After running the task, wait 30 seconds then verify the script executed:

```powershell
# View all recent events from M.E.Doc Update Check
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 3
```

#### Example: Event ID 1000 (Successful Update)

If an update WAS detected, you'll see Event ID 1000:

```text
TimeCreated  : 10/28/2025 08:05:23 AM
ProviderName : M.E.Doc Update Check
Id           : 1000
LevelDisplayName : Information
Message      : Server=MY-MEDOC-SERVER | Status=UPDATE_OK | FromVersion=11.02.183 | ToVersion=11.02.184 | UpdateStarted=28.10.2025 05:15:23 | UpdateCompleted=28.10.2025 05:17:20 | Duration=97 | CheckTime=28.10.2025 08:05:23
```

#### Success Indicators

- ☐ Task Scheduler task is created and configured
- ☐ Event Log shows entry from M.E.Doc Update Check (any Event ID: 1000, 1001, 1002, etc.)
- ☐ Event message contains correct server name
- ☐ For updates: Event ID 1000 shows UPDATE_OK status with version details

**References:**

- See [README.md - Example Telegram Messages](README.md#example-telegram-messages)

---

## 4. Multiple Servers Deployment

### ☐ Repeat Single Server Steps for Each Server

For each additional server, repeat all steps from Section 3:

1. ☐ Copy files to the server
2. ☐ Run Setup-Credentials.ps1 on the server
3. ☐ Create and customize Config file (automatic naming with `$env:COMPUTERNAME`)
4. ☐ Test manually on the server
5. ☐ Create scheduled task on the server

### ☐ Optional: Stagger Execution Times

If monitoring multiple servers, stagger task execution to avoid simultaneous API calls:

```powershell
# Server 1 at 05:10 AM
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-MainOffice.ps1" -ScheduleTime "05:10"

# Server 2 at 05:15 AM
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-Warehouse.ps1" -ScheduleTime "05:15"

# Server 3 at 05:20 AM
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-Branch.ps1" -ScheduleTime "05:20"
```

**References:**

- See [README.md - Deploying to Multiple Servers](README.md#deploying-to-multiple-servers)

---

## 5. Post-Deployment Monitoring

### ☐ Daily: Monitor Telegram Messages

Daily checks:

- ☐ Verify daily notifications arrive
- ☐ Check for update status (success/failure/no updates)
- ☐ Look for unusual patterns or missing days

### ☐ Weekly: Check Event Log

Review recent events from all monitored servers:

```powershell
# Get all events from last 7 days
$sevenDaysAgo = (Get-Date).AddDays(-7)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    StartTime = $sevenDaysAgo
} -MaxEvents 100

# Get only errors (if any) - Level 2 = Error
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 2
} -MaxEvents 20
```

For detailed Event Log query guidance, see [TESTING.md - Event Log Test](TESTING.md#7-event-log-test).

#### What to Look For

- ☐ Event ID 1000 appears regularly (all verification flags confirmed)
- ☐ No error Event IDs in unexpected patterns
- ☐ Checkpoint files updated regularly in ProgramData
- ☐ See [SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference) for complete monitoring strategy

### ☐ Monthly: Review Configuration

Verify everything is still configured correctly:

```powershell
# Verify credentials file still exists (CMS encrypted)
Test-Path "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"

# Verify checkpoint files (created automatically)
Get-Item "$env:ProgramData\MedocUpdateCheck\checkpoints\last_run_*"
```

### ☐ Quarterly: Test Failure Scenarios

Verify alerting works by testing failure conditions:

- ☐ Temporarily stop M.E.Doc service → verify error notification
- ☐ Block Telegram API → verify error logged
- ☐ Rename log file → verify "file not found" error

**References:**

- See [README.md - Troubleshooting](README.md#troubleshooting)
- See [SECURITY.md - Audit Trail](SECURITY.md#audit-trail)

### ☐ Credential Rotation (If Needed)

If bot token needs rotation:

```powershell
# 1. Create new bot in Telegram BotFather
# 2. Run Setup-Credentials.ps1 with new token
.\utils\Setup-Credentials.ps1 -BotToken "NEW_TOKEN" -ChatId "YOUR_CHAT_ID" -Force

# 3. Delete old bot from BotFather
# 4. Verify next scheduled run sends message
```

**References:**

- See [SECURITY.md - Secret Rotation](SECURITY.md#secret-rotation)

---

## 6. Reference Sections

### Exit Codes for Task Scheduler Alerts

`Run.ps1` returns distinct exit codes for monitoring and automation:

#### Exit Code Reference

- **0** — Update check completed normally (Success or NoUpdate)
  - Routine operation, no action required
  - Logs written to Event Log with info level

- **1** — Operational or configuration error
  - Configuration validation failed (missing required keys, invalid values)
  - File system error (logs directory missing, checkpoint write failed)
  - Telegram transport error (API unreachable, invalid credentials)
  - Requires investigation and remediation

- **2** — Update detected but validation failed
  - Update operation found in logs
  - One or more required validation flags missing or version mismatch
  - Critical condition requiring immediate investigation
  - May indicate incomplete update or infrastructure issue

#### Recommended Alerting Strategy

- Configure Task Scheduler to alert/restart on exit codes 1 and 2
- Exit code 0 is expected for normal operations (Success or NoUpdate)
- See [README.md - Exit Codes](README.md#exit-codes) for user-focused documentation
- For full API details, see `Get-ExitCodeForOutcome` in [lib/MedocUpdateCheck.psm1](lib/MedocUpdateCheck.psm1)

### Troubleshooting Quick Links

| Problem | Reference |
|---|---|
| No Telegram messages | [README.md - No Messages in Telegram](README.md#no-messages-in-telegram) |
| Script won't run from Task Scheduler | [README.md - Script Won't Run from Task Scheduler](README.md#script-wont-run-from-task-scheduler) |
| Wrong update status reported | [README.md - Wrong Update Status Reported](README.md#wrong-update-status-reported) |
| Module load errors | [README.md - Module Load Errors](README.md#module-load-errors) |
| Credential errors | [SECURITY.md - Sensitive Data Status](SECURITY.md#sensitive-data-status) |

### Documentation Map

| Document | Purpose | Link |
|---|---|---|
| **README.md** | Quick start and basic configuration | [Full deployment guide](README.md) |
| **SECURITY.md** | Credential management and security | [Security procedures](SECURITY.md) |
| **TESTING.md** | Testing procedures and validation | [Testing guide](TESTING.md) |
| **CONTRIBUTING.md** | Code standards for developers | [Contributing guide](CONTRIBUTING.md) |
| **AGENTS.md** | AI agent instructions | [Agent guide](AGENTS.md) |

### Deployment Success Checklist

#### All Tasks Complete When

- ☐ All pre-deployment steps completed (Telegram bot, chat ID)
- ☐ Files copied to server
- ☐ Credentials setup completed and verified
- ☐ Configuration file updated with correct paths
- ☐ Manual test successful (Telegram message received)
- ☐ Scheduled task created and configured
- ☐ Final verification passed
- ☐ Event Log shows Event ID 1000 (success)

#### Ready for Production When

- ☐ 3 consecutive daily runs with successful messages
- ☐ No errors in Event Log
- ☐ Checkpoint files auto-created in ProgramData
- ☐ Server name displays correctly in Telegram messages
- ☐ Update detection working (verified with real M.E.Doc update)

---

## Support & Questions

For help with specific issues, refer to:

- **Installation issues**: See [README.md - Quick Start](README.md#quick-start)
- **Security concerns**: See [SECURITY.md](SECURITY.md)
- **Credential problems**: See [SECURITY.md - Credentials You Need to Provide](SECURITY.md#credentials-you-need-to-provide)
- **Testing & validation**: See [TESTING.md](TESTING.md)
- **API/Event Log details**: See [README.md - Error Handling](README.md#error-handling)

---

**Authors:** See [README.md](README.md#authors) for list of authors and contributors

**License:** See [LICENSE](LICENSE) file for details

**Note:** For release versions and history, check git tags: `git tag -l` or `git describe --tags`
