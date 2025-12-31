# Testing Guide for M.E.Doc Update Check

This document describes how to test the M.E.Doc Update Check project, including manual testing procedures and automated Pester tests.

## Platform Support & Testing Coverage

**Development & Comprehensive Testing:** macOS and Linux with cross-platform PowerShell 7

**Production Platform:** Windows (M.E.Doc servers)

**Testing Coverage:**

- ✅ **Comprehensive:** Core logic tested on macOS/Linux (log parsing, update detection, message formatting)
- ✅ **Comprehensive:** Telegram integration tested on macOS/Linux
- ⚠️ **Limited:** Windows-specific features (Event Log, Task Scheduler, CMS certificate handling, SYSTEM user context)
- ⚠️ **Limited:** Production validation only on developer's own Windows servers

**What This Means for Users:**

- Core functionality is well-tested and reliable on all platforms
- Windows-specific features work but have limited broad testing
- Before deploying to production, test thoroughly in your Windows environment

**For Contributors:**

When testing changes: Always run tests on macOS/Linux (matches CI/CD) - `./tests/Run-Tests.ps1`.
For Windows-specific code changes, test on actual Windows Server before submission.

---

## Prerequisites

- PowerShell 7.0 or later
- Pester module (for automated tests): `Install-Module Pester -Force`
- Administrator privileges (for Event Log tests)

## Manual Testing

### 1. Module Loading Test

Verify that the module loads correctly without errors:

```powershell
cd C:\Script\MedocUpdateCheck

# Test module import
Import-Module ".\lib\MedocUpdateCheck.psm1" -Force
Get-Module MedocUpdateCheck

# Verify functions are available
Get-Command Test-UpdateOperationSuccess
Get-Command Write-EventLogEntry
Get-Command Invoke-MedocUpdateCheck
```

### 2. Configuration Loading Test

Test that configuration files load correctly:

```powershell
# Load configuration (use Config.template.ps1 or your custom config)
. ".\configs\Config.template.ps1"

# Verify config was loaded
$config

# Test with specific keys
$config.ServerName
$config.MedocLogsPath
$config.BotToken
$config.ChatId
```

### 3. Test-UpdateOperationSuccess Function

Test the update detection function with 2-marker validation (Planner.log + update_YYYY-MM-DD.log).

**Note:** All results return status objects with `Status` field and `ErrorId` (MedocEventId enum value):

```powershell
# Test with successful update (both markers present)
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\success-both-markers"
$result.Status          # Should be "Success"
$result.ErrorId         # Should be [MedocEventId]::Success (1000)
$result.Success         # Should be $true
$result.TargetVersion   # Should show version number
$result.UpdateTime      # Should show update time

# Test with no updates
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\failure-no-update-detected"
$result.Status          # Should be "NoUpdate" (returns status object, not $null)
$result.ErrorId         # Should be [MedocEventId]::NoUpdate (1001)

# Test with missing version marker
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\failure-missing-version-marker"
$result.Status          # Should be "Failed"
$result.ErrorId         # Should be [MedocEventId]::UpdateValidationFailed (1302)
$result.MarkerVersionConfirm     # Should be $false
$result.MarkerCompletionMarker   # Should be $true

# Test with missing completion marker
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\failure-missing-completion-marker"
$result.Status          # Should be "Failed"
$result.ErrorId         # Should be [MedocEventId]::UpdateValidationFailed (1302)
$result.OperationFound  # Should be $false
```

### 4. Checkpoint Filtering Test

Test that the function respects checkpoint times (avoids reprocessing):

```powershell
# Create a checkpoint time before the update
$checkpoint = [datetime]::ParseExact("23.10.2025 00:00:00", "dd.MM.yyyy HH:mm:ss", $null)

# Search with checkpoint - should find the update
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\success-both-markers" -SinceTime $checkpoint
$result.Success    # Should be $true

# Create checkpoint after the update time
$checkpoint2 = [datetime]::ParseExact("25.10.2025 23:59:59", "dd.MM.yyyy HH:mm:ss", $null)
$result2 = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\success-both-markers" -SinceTime $checkpoint2
$result2.Status    # Should be "NoUpdate" (no update after checkpoint)
```

### 5. Encoding Test

Test different log file encodings:

```powershell
# Windows-1251 (Cyrillic, default - required for M.E.Doc logs)
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\success-both-markers" -EncodingCodePage 1251
$result.Success    # Should be $true

# UTF-8 (for testing compatibility)
$result = Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\success-both-markers" -EncodingCodePage 65001
$result            # Should handle without error
```

### 6. Run.ps1 Entry Point Test

Test the main entry point script:

```powershell
cd C:\Script\MedocUpdateCheck

# Run with your config using server's hostname
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Run with verbose output
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1" -Verbose
```

### 7. Event Log Test

Check that entries are written to Windows Event Log.

**Requirement:** PowerShell 7.0 or later (project requirement)

Use `Get-WinEvent` to query the Event Log:

```powershell
# View recent events from M.E.Doc Update Check source (PowerShell 7+)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 10

# Filter by event level (Information = 4, Warning = 3, Error = 2)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 4  # Information (Success / NoUpdate)
} -MaxEvents 5

# Check for errors (Level 2 = Error)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 2
} -MaxEvents 20

# Check for success and no-update messages (Level 4 = Information)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 4
} -MaxEvents 10
```

**Event Log Message Format:**

The script writes messages to Event Log in key=value format for easy parsing:

**Success message (Event ID 1000):**

```text
Server=MY-MEDOC-SERVER | Status=UPDATE_OK | FromVersion=11.02.183 | ToVersion=11.02.184 | UpdateStarted=28.10.2025 05:15:23 | UpdateCompleted=28.10.2025 05:17:20 | Duration=97 | CheckTime=28.10.2025 12:33:45
```

**Failure message (Event ID 1302):**

```text
Server=MY-MEDOC-SERVER | Status=UPDATE_FAILED | FromVersion=11.02.183 | ToVersion=11.02.184 | UpdateStarted=28.10.2025 05:15:23 | Reason=Missing required markers: Version confirmation | CheckTime=28.10.2025 12:33:45
```

**No update message (Event ID 1001):**

```text
Server=MY-MEDOC-SERVER | Status=NO_UPDATE | CheckTime=28.10.2025 12:33:45
```

**Event ID Reference:**

For the complete and authoritative Event ID reference table, see
[SECURITY.md - Event ID Reference](SECURITY.md#event-id-reference). The Event ID enum is
centralized in the codebase (`lib/MedocUpdateCheck.psm1`) to ensure consistency across all
Event Log entries and function return values.

**Quick Reference for Common Events:**

| Event ID | Meaning | Action |
|---|---|---|
| **1000** | ✅ Update successful - Both markers confirmed | Monitor daily - normal |
| **1001** | ℹ️ No update detected since checkpoint | Check next scheduled run |
| **1100-1199** | Configuration errors (missing keys, invalid values) | Fix Config.ps1, compare with template |
| **1200-1299** | Filesystem/environment errors (missing logs, directory issues) | Verify paths and permissions |
| **1302** | Update validation failures (missing required markers) | Review M.E.Doc update logs |
| **1400-1401** | Telegram notification errors | Verify credentials and network |
| **1500** | Checkpoint file write failed | Check disk space and permissions |
| **1900** | Unexpected error | Check script logs for details |

**Troubleshooting:**

- **1000-1001**: Normal operation. Events appear regularly per schedule.
- **1100-1199**: Config incomplete. Compare Config.ps1 with Config.template.ps1.
- **1200-1299**: File access issues. Verify MedocLogsPath and ProgramData permissions.
- **1302**: Update validation failed. Review M.E.Doc server logs (Planner.log and update_*.log).
- **1400-1401**: Telegram issues. Verify bot token, chat ID, and network connectivity.
- **1500+**: Disk space or permission issues. Check ProgramData directory.

See [SECURITY.md - Monitoring Strategy](SECURITY.md#monitoring-strategy) for detailed troubleshooting by Event ID.

### 8. Telegram Integration Test

Test Telegram notification (requires valid credentials):

```powershell
# Before testing, ensure your custom config has valid Telegram credentials

# Run the script with server's hostname
.\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Check if message was received on Telegram
# (Manually verify the message appears in Telegram)

# Check Event Log for success (PowerShell 7+)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1000
} -MaxEvents 1
```

### 9. Configuration Validation Test

Test that missing configuration is caught:

```powershell
# Test with incomplete config
$badConfig = @{
    ServerName = "TestServer"
    MedocLogsPath = "C:\nonexistent"
}

Invoke-MedocUpdateCheck -Config $badConfig
# Should error and log event ID 1100 (missing required config key) or 1101 (invalid logs directory path)
```

### 10. Task Scheduler Setup Test

Test automated Task Scheduler setup:

```powershell
# Run setup script as Administrator
cd C:\Script\MedocUpdateCheck
.\utils\Setup-ScheduledTask.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"

# Verify task was created
Get-ScheduledTask -TaskName "M.E.Doc Update Check"

# Check task properties
Get-ScheduledTask -TaskName "M.E.Doc Update Check" | Select-Object *
Get-ScheduledTask -TaskName "M.E.Doc Update Check" | Get-ScheduledTaskInfo

# Run task manually to test
Start-ScheduledTask -TaskName "M.E.Doc Update Check"
```

### 11. Credential Setup and Certificate Validation Test

Test the credential encryption setup and certificate validation logic:

```powershell
# Test credential setup (interactive - prompts for input)
cd C:\Script\MedocUpdateCheck
.\utils\Setup-Credentials.ps1

# Verify encrypted credentials file was created
Test-Path "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"
# Should return $true

# Check certificate was created in LocalMachine store
Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {
    $_.Subject -eq "CN=M.E.Doc Update Check Credential Encryption"
}
# Should show certificate with subject matching the expected value

# Verify certificate has proper CMS properties
$cert = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {
    $_.Subject -eq "CN=M.E.Doc Update Check Credential Encryption"
} | Sort-Object NotAfter -Descending | Select-Object -First 1

# Check certificate properties
$cert.Subject              # Should be "CN=M.E.Doc Update Check Credential Encryption"
$cert.NotAfter             # Should be ~5 years from creation date
$cert.Thumbprint           # Should be displayed
$cert.PrivateKey           # Should be accessible (not null)
$cert.PublicKey            # Should be RSA 2048-bit
```

**Testing Certificate Upgrade Scenario (Old Certificates):**

```powershell
# This tests the automatic certificate validation and regeneration
# (Advanced - simulates upgrading from older release)

# The Get-MedocCredentialCertificate function automatically:
# 1. Checks certificate expiration (regenerates if < 30 days left)
# 2. Verifies private key is accessible
# 3. Validates Document Encryption EKU is present (OID: 1.3.6.1.4.1.311.80.1)
# 4. Validates KeyEncipherment key usage is present
# 5. Regenerates if any requirements are missing

# To test upgrade scenario:
# 1. Create an old certificate without proper EKU/KeyUsage
# 2. Run Setup-Credentials.ps1 again
# 3. Verify it detects missing requirements and regenerates new certificate
# 4. Verify new certificate has all proper CMS properties

# Watch for warning messages like:
# "⚠️  Existing certificate doesn't meet CMS encryption requirements"
# "    Missing:"
# "      • Document Encryption EKU (1.3.6.1.4.1.311.80.1)"
# "      • KeyEncipherment key usage"
```

**Testing Credential Decryption:**

```powershell
# Test that credentials can be decrypted using the helper script
$credPath = "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"

# Call the script with the call operator (&)
$creds = & ".\utils\Get-TelegramCredentials.ps1" -Path $credPath

# Verify credentials were decrypted
$creds.BotToken    # Should contain bot token
$creds.ChatId      # Should contain chat ID

# These values should match what was encrypted during Setup-Credentials
```

---

## Script Validation with Validate-Scripts.ps1

**Purpose:** Validate PowerShell scripts for syntax errors and code quality issues before running tests or committing code.

**Location:** `utils/Validate-Scripts.ps1`

### Quick Start

```powershell
# Validate all scripts (syntax only - fast)
./utils/Validate-Scripts.ps1

# Validate with code quality analysis (slower)
./utils/Validate-Scripts.ps1  # Automatically detects and runs PSScriptAnalyzer if available

# Skip code quality checks for faster validation
./utils/Validate-Scripts.ps1 -SkipAnalyzer

# Show detailed output including AST types and analyzer details
./utils/Validate-Scripts.ps1 -Verbose

# Exclude additional file patterns
./utils/Validate-Scripts.ps1 -ExcludePattern "*.backup", "archive/*"
```

### What It Validates

#### Syntax Validation (Always Runs)

- PowerShell parsing errors (missing brackets, invalid keywords, syntax mistakes)
- Uses PowerShell's built-in parser (100% accurate)
- No false positives

#### Code Quality Analysis (Optional)

- Runs automatically if PSScriptAnalyzer module is installed
- Flags best practice violations, security issues, style inconsistencies
- Can be skipped with `-SkipAnalyzer` for faster validation
- Configured to accept expected warnings (e.g., `Write-Host` in CLI utilities)

### Output Examples

#### Syntax-Only Validation (50-200ms)

```text
PowerShell Script Validator
==================================================

Scanning for PowerShell scripts...
Found 12 script(s)

Validating syntax...
✓ lib/MedocUpdateCheck.psm1
✓ utils/Validate-Scripts.ps1
✓ tests/MedocUpdateCheck.Tests.ps1

==================================================
Validation Summary:
  ✓ Syntax Passed:  12
  ✗ Syntax Failed:  0
  ⏱️ Time: 145.23ms

All validations passed! ✅
```

#### With Code Quality Analysis (4000-5000ms)

```text
PowerShell Script Validator
==================================================

PSScriptAnalyzer detected - running quality validation

Scanning for PowerShell scripts...
Found 12 script(s)

Validating syntax...
✓ lib/MedocUpdateCheck.psm1
✓ utils/Validate-Scripts.ps1

Running PSScriptAnalyzer...
  Found 3 errors, 215 warnings

==================================================
Validation Summary:
  ✓ Syntax Passed:  12
  ✗ Syntax Failed:  0
  ⚠️ Analyzer Issues:
      • Errors:      0
      • Warnings:    215
      • Information: 8
  ⏱️ Time: 4905.44ms

All validations passed! ✅
```

### Pre-Commit Validation Workflow

Before committing code changes:

```powershell
# Step 1: Validate syntax
./utils/Validate-Scripts.ps1

# Step 2: Run tests
./tests/Run-Tests.ps1

# Step 3: (If passing) commit changes
git add .
git commit -m "Your commit message"
```

### Integration with CI/CD

GitHub Actions automatically runs this validation in `.github/workflows/tests.yml`:

- Validates all scripts before tests
- Ensures only syntactically correct code reaches test suite
- Provides early feedback on syntax errors

**See Also:** [AGENTS.md - Validating Changes with PowerShell 7](AGENTS.md#validating-changes-with-powershell-7-pwsh)

---

## Automated Testing with Pester

### Installation

Install Pester if not already installed:

```powershell
Install-Module Pester -Force -SkipPublisherCheck
```

### Test Setup & Module-Driven Enums

The test file uses `using module "..\lib\MedocUpdateCheck.psm1"` at the top to import the module at compile time. This is **critical** because:

1. **Enum Type Safety** - Ensures the `MedocEventId` enum is available for type assertions in tests
2. **Keeps Enums in Sync** - Tests automatically use the latest enum definitions from the module
3. **Prevents Drift** - If EventIDs are added/changed in the module, tests fail immediately rather than silently using stale values
4. **Single Source of Truth** - EventID definitions live in one place (the module), tests
   automatically reflect changes

#### How It Works

The `using module` directive (different from `Import-Module`) imports the module at **Pester
compile time** before any tests run. This makes the `MedocEventId` enum type available for
use throughout the test file:

```powershell
# At the top of MedocUpdateCheck.Tests.ps1
using module "..\lib\MedocUpdateCheck.psm1"

# Later in tests, directly reference enum values
$result.ErrorId | Should -Be ([MedocEventId]::Success)        # Type-safe
$result.ErrorId | Should -Be ([MedocEventId]::UpdateValidationFailed)  # Auto-validates against actual enum
```

The `Import-Module` in `BeforeAll` is separate and necessary for runtime function calls.

#### Why This Matters

- **If `using module` is removed:** Tests will fail immediately with "Cannot find type [MedocEventId]" error
- **If EventIDs change in the module:** All affected tests will fail during the run, preventing silent test invalidation
- **If new EventIDs are added:** Tests can be written using the new values without manual synchronization

**Don't optimize this away** - The duplicate `Import-Module` in `BeforeAll` is intentional (one
for compile-time types via `using`, one for runtime module functions). Both are required.

### Running All Tests

Run all tests with verbose output:

```powershell
cd C:\Script\MedocUpdateCheck
Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" -Verbose
```

### Running Specific Test Groups

Run only Test-UpdateOperationSuccess tests:

```powershell
Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" -Verbose `
    -FullNameFilter "*Test-UpdateOperationSuccess*"
```

Run only unit tests:

```powershell
Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" -Verbose `
    -FullNameFilter "*Unit Tests*"
```

### Running with Output

Generate test report:

```powershell
Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" `
    -OutputFormat NUnitXml -OutputFile "tests/test-results.xml"
```

Generate JUnit format (for CI/CD):

```powershell
Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" `
    -OutputFormat JUnitXml -OutputFile "tests/junit-results.xml"
```

### Test Coverage

#### Using Run-Tests.ps1 Test Runner (Recommended)

The project includes a test runner script that matches CI/CD behavior with coverage reporting:

**Basic test run:**

```powershell
./tests/Run-Tests.ps1
```

**With code coverage measurement:**

```powershell
./tests/Run-Tests.ps1 -Coverage
```

This displays:

- Test summary (Passed/Failed/Skipped counts)
- Code coverage percentage for production code (lib/ + Run.ps1)
- Color-coded coverage status:
  - 🟢 Green: 80%+ (excellent)
  - 🟡 Yellow: 60-79% (good)
  - 🔴 Red: <60% (needs improvement)

**With coverage and verbose output:**

```powershell
./tests/Run-Tests.ps1 -Coverage -Verbose
```

**Filter tests and measure coverage:**

```powershell
./tests/Run-Tests.ps1 -Coverage -Filter "*UpdateOperation*"
```

**Parameters:**

- `-Coverage` - Enable code coverage measurement
- `-Verbose` - Show detailed test output
- `-Filter "pattern"` - Run only tests matching pattern (use wildcards: `*` for any chars, `?` for single char, or exact match)
- `-PassThru` - Return test results object for further processing

#### Direct Pester Invocation

For advanced usage, call Pester directly:

```powershell
$results = Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" -PassThru
$results.TestResult | Where-Object { $_.Result -eq "Failed" }
```

### Event Log Verification in Tests

**Important:** Event Log testing uses mocks and works on all platforms (Windows, macOS, Linux).

#### Why Mocking Event Log?

The project uses mocks for `Write-EventLogEntry` to:

- ✅ Test on macOS and Linux (Event Log only exists on Windows)
- ✅ Verify correct EventId and message values are passed
- ✅ Avoid permissions issues on Windows
- ✅ Make tests fast and deterministic
- ✅ Test error paths without needing real errors

#### How Event Log Mocking Works

```powershell
# In test setup (BeforeEach):
$script:capturedLogEvents = @()

Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
    param($Message, $EventType, $EventId, $EventLogSource, $EventLogName)
    $script:capturedLogEvents += [pscustomobject]@{
        Message   = $Message
        EventType = $EventType
        EventId   = $EventId
        Source    = $EventLogSource
    }
}

# Then in test:
$result = Invoke-MedocUpdateCheck -Config $config

# Verify Event Log was called:
$logEntry = $script:capturedLogEvents |
    Where-Object { $_.EventId -eq ([int][MedocEventId]::EncodingError) }
$logEntry | Should -Not -BeNullOrEmpty
$logEntry.EventType | Should -Be "Error"
```

**Key Points:**

- Mock is scoped to the module (`-ModuleName MedocUpdateCheck`)
- Captured events are stored in `$script:capturedLogEvents`
- Tests verify both EventId and EventType are correct
- Works identically on all platforms

#### Error Path Coverage

All error paths are tested to ensure they log to Event Log with correct EventId:

| Error Path | EventId | Type | Test |
|---|---|---|---|
| PlannerLogMissing | 1200 | Error | ✅ Line 233-252 |
| EncodingError | 1204 | Error | ✅ Line 254-280 |
| UpdateLogMissing | 1201 | Error | ✅ Integration test |
| ConfigInvalidValue | 1101 | Error | ✅ Integration test |
| TelegramSendError | 1401 | Error | ✅ Line 282-304 |
| Success | 1000 | Information | ✅ Integration test |
| NoUpdate | 1001 | Information | ✅ Integration test |

#### Writing New Event Log Tests

When adding tests that verify Event Log entries:

1. **Set up mock in BeforeEach:**

   ```powershell
   Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
       param($Message, $EventType, $EventId, [string]$EventLogSource, [string]$EventLogName)
       $script:capturedLogEvents += [pscustomobject]@{
           Message = $Message
           EventType = $EventType
           EventId = $EventId
       }
   }
   ```

2. **Run function and verify:**

   ```powershell
   $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -ErrorAction SilentlyContinue

   # Verify Event Log entry
   $logEntry = $script:capturedLogEvents |
       Where-Object { $_.EventId -eq ([int][MedocEventId]::EncodingError) } |
       Select-Object -Last 1
   $logEntry | Should -Not -BeNullOrEmpty
   $logEntry.EventType | Should -Be "Error"
   ```

3. **Assert message content if needed:**

   ```powershell
   $logEntry.Message | Should -Match "pattern describing the error"
   ```

#### Platform-Specific Notes

**Windows:**

- Tests run with mocked Event Log (doesn't hit real Event Log)
- In production, code actually writes to Windows Event Log
- Validation happens in production environment

**macOS/Linux:**

- Tests run with mocked Event Log
- Event Log function gracefully handles unsupported platform (writes warning, continues)
- Focus is on message formatting and logging calls, not platform integration

### Platform-Specific Tests (Windows-Only Features)

#### About Platform-Specific Tests

The project includes tests for Windows-only features that are intentionally skipped on
macOS/Linux. This reflects the reality that while core update detection logic is
cross-platform, some operational features (credential encryption, task scheduling) depend on
Windows APIs.

**Current Status:**

- ✅ 237 tests passing on Windows CI
- ❌ 3 tests failing on Windows CI (known Pester limitation - see below)
- ✅ 236 tests passing on macOS/Linux
- ⏭️ 2 tests skipped on non-Windows (intentional, documented)

#### Known Issues: Pester InModuleScope Mocking on Windows

**Problem:** Three EventLog error handling tests consistently fail on Windows CI with
`ParameterBindingException`, despite:

- ✅ Passing on macOS/Linux
- ✅ Using identical mock syntax to working tests
- ✅ Having all required mocks present

**Affected Tests:**

- "Should warn when creating source fails" (see "Write-EventLogEntry - Error handling" context)
- "Should warn when event log handle creation fails" (see "Write-EventLogEntry - Error handling" context)
- "Should fail when checkpoint directory cannot be created" (see "Invoke-MedocUpdateCheck - Notification pipeline" context)

**Root Cause:** When Pester mocks functions inside `InModuleScope` on Windows and a mocked
function is called, Windows PowerShell's parameter binding resolution for functions that wrap
.NET APIs (like `System.Diagnostics.EventLog`) triggers a `ParameterBindingException`.
This is a known Pester limitation on Windows.

**Research Evidence:**

- [Pester Issue #1554](https://github.com/pester/Pester/issues/1554):
  "Using a param-block inside MockWith behaves strangely"
- [Pester Issue #1308](https://github.com/pester/Pester/issues/1308):
  "Cannot execute mock - ParameterBindingException"
- [Pester Issue #305](https://github.com/pester/Pester/issues/305):
  "Cannot retrieve dynamic parameters"

**Attempted Fixes (all failed):**

1. ❌ Added missing mocks (following pattern from working test)
2. ❌ Changed mocks to return values instead of throwing errors
3. ❌ Removed/added param blocks in various combinations
4. ❌ Changed mock syntax (with/without `-MockWith` parameter)
5. ❌ Made ParameterFilter more specific for checkpoint test

**Impact Assessment:**

- ✅ Core EventLog functionality IS tested (working test at line 544 passes on all platforms)
- ✅ Production code works correctly on Windows (validated manually)
- ❌ Edge case error handling tests fail due to Pester limitation
- ℹ️ Failing tests cover scenarios: source creation failure, handle creation failure,
  checkpoint directory errors

**Workaround:** These tests are documented as known failures in the codebase. The functionality
they test is validated manually on Windows servers before deployment. See test file comments
for full details.

**Status:** Unresolved platform-specific Pester limitation. See test file "Known Issues" comment block.

**Test Platform Coverage Matrix:**

| Test Category | Windows | macOS | Linux | Notes |
|---|---|---|---|---|
| **Core Update Detection** | ✅ All | ✅ All | ✅ All | Log parsing, marker validation, 2-marker system |
| **Message Formatting** | ✅ All | ✅ All | ✅ All | Event log messages, notification text |
| **Configuration Validation** | ✅ All | ✅ All | ✅ All | Parameter validation, file path checks |
| **Telegram Integration** | ✅ All | ✅ All | ✅ All | Mocked API calls, message formatting |
| **Event Log Writing** | ✅ All (mocked) | ✅ All (mocked) | ✅ All (mocked) | Cross-platform mocking works everywhere |
| **CMS Credential Encryption** | ✅ 3 tests | ⏭️ 3 skip | ⏭️ 3 skip | Real encrypt/decrypt tests; Windows certificate APIs required |
| **Certificate Validation** | ✅ Multiple | ⏭️ Skip | ⏭️ Skip | Setup-Credentials.ps1 validation logic |
| **Task Scheduler Setup** | ✅ 1 test | ⏭️ 1 skip | ⏭️ 1 skip | Windows Task Scheduler COM API required |

#### CMS Credential Encryption Tests (Windows-Only)

**Why Skipped on Non-Windows:**

PowerShell's CMS (Cryptographic Message Syntax) cmdlets depend on Windows Certificate Store and Windows PKI:

- `Protect-CmsMessage` - Requires Windows Certificate Store
- `Unprotect-CmsMessage` - Requires access to private keys in LocalMachine\My
- Certificate operations - Depend on Windows Certificate Provider

**What These Tests Cover:**

The "Certificate encryption and decryption workflow" context tests actual encryption functionality:

- ✅ Real credential encryption using `Protect-CmsMessage`
- ✅ Real credential decryption using `Unprotect-CmsMessage`
- ✅ JSON payload integrity verification
- ✅ Certificate presence verification in LocalMachine store
- ✅ Certificate property validation (subject, expiration, private key)
- ✅ Graceful handling when certificate doesn't exist yet

**Test Skip Details:**

```powershell
# See "Certificate encryption and decryption workflow" context in tests/MedocUpdateCheck.Tests.ps1
It "Should encrypt and decrypt credential data successfully" -Skip:(
    $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
) {
    # Real encryption/decryption test - skipped on non-Windows
    # Reason: Requires Windows Certificate Store and private key access
}
```

**Running on Windows:**

```powershell
# All 13 CMS tests run normally on Windows
./tests/Run-Tests.ps1

# Filter to run only CMS tests:
Invoke-Pester -Path ./tests/MedocUpdateCheck.Tests.ps1 `
    -FullNameFilter "*CMS*"
```

**Behavior on Non-Windows (Development/CI):**

- ⏭️ Tests are skipped (marked as "-Skip")
- ✅ No test failures
- ✅ Test count accurate (skip counted correctly)
- 📝 Clear documentation in test file explains why

#### Task Scheduler Tests (Windows-Only)

**Why Skipped on Non-Windows:**

Windows Task Scheduler is exclusively Windows-based:

- No equivalent on macOS (uses LaunchAgents) or Linux (uses cron/systemd)
- Depends on Windows Registry for task configuration
- Depends on Task Scheduler COM API (Windows only)
- PowerShell cmdlets (`Get-ScheduledTask`, `Register-ScheduledTask`) only work on Windows

**What These Tests Cover:**

- Administrator privilege requirement validation
- PowerShell 7+ version detection
- Task creation with proper script path
- Task persistence validation
- Running as SYSTEM user context

**Test Skip Details:**

```powershell
# See "Setup-ScheduledTask.ps1 - Task Scheduler Integration" describe block in tests/Utilities.Tests.ps1
Describe "Setup-ScheduledTask.ps1 - Task Scheduler Integration" {
    Context "Administrative requirements" {
        It "Should require Administrator privileges" -Skip:(-not $IsWindows) {
            # Gracefully skip: Task Scheduler is Windows-only feature
        }
    }
}
```

**Running on Windows:**

```powershell
# All Task Scheduler tests run normally on Windows
./tests/Run-Tests.ps1

# Filter to run only setup tests:
Invoke-Pester -Path ./tests/Utilities.Tests.ps1 `
    -FullNameFilter "*Setup*"
```

**Behavior on Non-Windows (Development/CI):**

- ⏭️ Tests are skipped (marked as "-Skip")
- ✅ No test failures
- ✅ Test count accurate
- 📝 Clear documentation in test file explains why

#### Mocking Event Log Works on All Platforms

**Important Distinction:**

Event Log functionality is NOT skipped - it's **mocked on all platforms**:

```powershell
# Event Log mocking (works on Windows, macOS, Linux)
Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
    # Capture the call without actually accessing Windows Event Log
}
```

**Why Mocking Works Cross-Platform:**

- ✅ Tests verify the correct EventId and message are passed
- ✅ Tests don't depend on Windows Event Log existing
- ✅ Identical behavior on all platforms
- ✅ No platform-specific skips needed for Event Log tests

#### CI/CD Interpretation Guide

When running tests in CI/CD pipelines, interpret results correctly:

**On Windows CI/CD:**

```text
Tests Passed:  196
Tests Skipped: 0          ← All tests run, nothing skipped
Tests Failed:  0
```

**On Linux/macOS CI/CD (e.g., GitHub Actions runners):**

```text
Tests Passed:  194        ← All portable tests pass
Tests Skipped: 2          ← CMS + Task Scheduler (expected & documented)
Tests Failed:  0          ← No failures
```

**What This Means:**

- ✅ Skipped tests are **expected and documented** (not failures)
- ✅ Core functionality is well-tested on all platforms
- ⚠️ Windows-specific features only validated on Windows
- 📝 Each skip has clear documentation explaining the reason

#### Adding New Platform-Specific Tests

When adding tests for Windows-only features:

1. **Use conditional skip syntax:**

   ```powershell
   It "Should do something Windows-specific" -Skip:(-not $IsWindows) {
       # Test code here - skipped on non-Windows
   }
   ```

2. **Add documentation explaining why:**

   ```powershell
   Describe "Windows-Only Feature Tests" {
       # PLATFORM COMPATIBILITY: Windows only
       # This feature uses Windows-specific API that doesn't exist on other platforms
       # Reason: [Explain which APIs/features are Windows-only]

       It "Should test the feature" -Skip:(-not $IsWindows) {
           # Test
       }
   }
   ```

3. **Update the platform matrix** in this documentation

4. **Run tests on all platforms** to verify:
   - Windows: All tests pass
   - macOS/Linux: Correct tests are skipped with clear reason

## Test Data

Test data directories are provided in `tests/test-data/`. Each contains M.E.Doc logs in Windows-1251 encoding:

- **success-both-markers** - Update completes with both V and C markers present
- **failure-missing-version-marker** - Version marker missing (operation completed but version not confirmed)
- **failure-missing-completion-marker** - Completion marker missing (operation incomplete)
- **failure-no-update-detected** - No update operation found in logs
- **failure-no-update-log** - Planner shows update trigger but update_*.log file is missing (treated as FAILED)

These directories use realistic M.E.Doc log format with Windows-1251 encoding and Ukrainian
messages. See `tests/test-data/README.md` for detailed documentation of each scenario.

### Test Artifacts Cleanup

The test suite automatically cleans up temporary checkpoint files (`checkpoint-*.txt`) after each test run completes, regardless of pass/fail/skip outcome.

**Why:** Prevents accumulation of test artifacts in the working directory and maintains clean repository state.

**What happens:**

- Temporary checkpoint files created during `Invoke-MedocUpdateCheck` tests are removed
- Actual test fixtures (`.log` files) are preserved
- Cleanup runs in the `AfterAll` block, guaranteeing cleanup even if tests fail

**Git protection:** Test artifacts are also excluded by `.gitignore` as a secondary safeguard.

**For developers:** You don't need to manually clean checkpoint files; the test suite handles this automatically.

## Continuous Integration

To integrate testing into your CI/CD pipeline (GitHub Actions, Azure Pipelines, etc.):

```powershell
# Example CI/CD script
$ErrorActionPreference = "Stop"
Install-Module Pester -Force
$results = Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" `
    -OutputFormat JUnitXml -OutputFile "results.xml" -PassThru
exit $results.FailedCount
```

## Test Categories

### Unit Tests

- `Test-UpdateOperationSuccess` - Log parsing and update detection
- `Write-EventLogEntry` - Event logging
- Parameter validation
- Error handling

### Integration Tests

- `Invoke-MedocUpdateCheck` - Full workflow
- Configuration validation
- File operations
- External dependencies (Telegram API)

### Manual Tests

- Module loading
- Configuration files
- Task Scheduler integration
- Event Log verification
- Telegram notifications

## Get-WinEvent Examples

**View all recent events:**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 20
```

**View only success events (Level 0):**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 0
} -MaxEvents 10
```

**View only errors (Level 2):**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 2
} -MaxEvents 20
```

**View specific event ID (e.g., 1000 = success):**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1000
} -MaxEvents 5
```

**View events from last 24 hours:**

```powershell
$yesterday = (Get-Date).AddDays(-1)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    StartTime = $yesterday
}
```

**Event Level Reference:**

| Level | Meaning | Used by script |
|-------|---------|---|
| 0 | Success (informational) | ✅ Success messages |
| 2 | Error | ✅ Error events |
| 3 | Warning | ⚠️ Warning events |
| 4 | Information | ℹ️ Info messages |

## Troubleshooting Tests

### Test Execution Issues

If tests fail to run:

```powershell
# Verify Pester is installed
Get-Module Pester -ListAvailable

# Update Pester
Update-Module Pester

# Run with ExecutionPolicy Bypass
powershell -ExecutionPolicy Bypass -Command "Invoke-Pester -Path tests/MedocUpdateCheck.Tests.ps1 -Verbose"
```

### Module Import Issues

If module fails to import during tests:

```powershell
# Clear any cached modules
Remove-Module MedocUpdateCheck -ErrorAction SilentlyContinue

# Verify module syntax
Test-ModuleManifest ".\lib\MedocUpdateCheck.psm1" -ErrorAction Continue

# Check module file
Get-Content ".\lib\MedocUpdateCheck.psm1" -Head 20
```

### Log File Issues

If sample logs aren't found:

```powershell
# Verify test-data directory exists
Test-Path "tests/test-data/"

# List available test logs
Get-ChildItem "tests/test-data/" -Filter "*.txt"

# Create missing logs manually if needed
```

## Performance Testing

To measure script performance:

```powershell
# Time the update check function
$timer = Measure-Command {
    Test-UpdateOperationSuccess -MedocLogsPath ".\tests\test-data\success-both-markers"
}
$timer.TotalMilliseconds   # Should be < 100ms for typical logs

# Time full workflow
$timer = Measure-Command {
    .\Run.ps1 -ConfigPath ".\configs\Config-$env:COMPUTERNAME.ps1"
}
$timer.TotalSeconds        # Should be < 5 seconds
```

## Adding New Tests

To add tests for new functionality:

1. Add test data to `tests/test-data/`
2. Add test cases to `tests/MedocUpdateCheck.Tests.ps1`
3. Follow Pester conventions (Describe, Context, It blocks)
4. Run tests locally before committing
5. Verify all tests pass: `Invoke-Pester`

Example adding a test:

```powershell
Describe "New Feature - Unit Tests" {
    Context "Specific scenario" {
        It "Should do something specific" {
            # Arrange
            $expected = "something"

            # Act
            $result = Some-Command

            # Assert
            $result | Should -Be $expected
        }
    }
}
```

## Best Practices

✅ **DO:**

- Run tests before deploying to production
- Keep test data realistic and varied
- Use meaningful test names
- Test both success and failure scenarios
- Document manual testing procedures

❌ **DON'T:**

- Use real Telegram credentials in tests
- Use real server log files for testing
- Skip testing error scenarios
- Leave test failures unresolved
- Commit tests that use absolute paths

## Test Coverage Analysis

### Current Test Coverage: EXCELLENT ✅

The project has comprehensive automated test coverage. Run tests to verify:

```powershell
./tests/Run-Tests.ps1
```

#### Coverage Breakdown

| Component | Tests | Status | Notes |
|-----------|-------|--------|-------|
| **Dual-Log Validation** | 14 | ✅ Excellent | Success, failure, missing flags, timeout scenarios |
| **Message Formatting (Telegram)** | 9 | ✅ Excellent | Version, date/time, duration, flag details |
| **Message Formatting (Event Log)** | 9 | ✅ Excellent | Key=value structure, flag details, SIEM compatibility |
| **Enhanced Fields** | 6 | ✅ Excellent | Version extraction, timestamp extraction, duration calculation |
| **Checkpoint Operations** | 12 | ✅ Excellent | Filename generation, timestamp parsing, edge cases |
| **Encoding Validation** | 3 | ✅ Good | Standard and invalid codepage handling |
| **Configuration Validation** | 6 | ✅ Good | Required keys, structure validation |
| **Error Handling** | 2 | ✅ Good | Missing files and error scenarios |
| **Write-EventLogEntry** | 2 | ⚠️ Fair | Basic parameter validation |
| **Module Exports** | 5 | ✅ Good | All 6 functions exported (including Format-* functions) |
| **Timestamp Regex Pattern Validation** | 3 | ✅ Excellent | 4-digit year (Planner.log), 2-digit year (update_*.log), format distinction |
| **Timestamp Format Handling** | 3 | ✅ Excellent | Milliseconds, log ID/level handling, line iteration |
| **Timestamp Edge Cases** | 3 | ✅ Excellent | Single-line files, UpdateTime consistency, checkpoint filtering |
| **Misc/Integration** | 27 | ✅ Excellent | Combined scenario testing, Invoke-MedocUpdateCheck |
| **Total** | Check with `./tests/Run-Tests.ps1` | **EXCELLENT** | Comprehensive 2-marker + timestamp regex coverage, production-ready |

#### Code Coverage Metrics (Production vs Setup Code)

### Important: Understanding Coverage Percentage

The overall coverage percentage reported by the workflow includes both testable production code and untestable setup tools. To understand coverage properly:

### Breakdown by Component Type

| Component | Type | Testability | Notes |
|-----------|------|-------------|-------|
| **lib/MedocUpdateCheck.psm1** | Production | ✅ Fully tested | Core business logic (log parsing, update detection) |
| **lib/ConfigValidation.psm1** | Production | ✅ Fully tested | Configuration validation functions |
| **Run.ps1** | Production | ⚠️ Indirect | Entry point orchestrator (covered via lib tests) |
| **Production Code Average** | - | **✅ Excellent** | Run `./tests/Run-Tests.ps1` to check current % |
| **utils/Setup-Credentials.ps1** | Setup Tool | ❌ Not testable | Interactive CLI + Windows certificates (requires manual testing) |
| **utils/Setup-ScheduledTask.ps1** | Setup Tool | ❌ Not testable | Admin-only task creation (system-level operation) |
| **utils/Get-TelegramCredentials.ps1** | Helper | ⚠️ Indirect | Decryption helper (tested via config loading) |
| **utils/Validate-Config.ps1** | Wrapper | ⚠️ Indirect | Validation wrapper (lib functions are tested) |
| **utils/Validate-Scripts.ps1** | Meta-tool | ❌ Not testable | Syntax validator (validates other code) |
| **configs/Config.template.ps1** | Template | ❌ N/A | Template file (not executable code) |

### Why Utils Have 0% Coverage (By Design)

Setup and utility scripts are **intentionally excluded** from CI/CD coverage metrics.
Here's detailed technical analysis of why they can't be unit-tested with Pester:

#### 1. Setup-Credentials.ps1 (Interactive Setup Tool)

**What it does:**

- Creates self-signed X.509 certificate in Windows LocalMachine store
- Prompts user interactively for Telegram bot token and chat ID
- Encrypts credentials using CMS (Cryptographic Message Syntax)
- Writes encrypted file with restricted permissions

**Why it CAN'T be easily tested:**

- ❌ Requires Administrator privileges (blocked in sandboxes/CI runners)
- ❌ Interactive user input (Read-Host prompts - can't mock reliably)
- ❌ Creates real Windows certificates (persists in system, requires cleanup)
- ❌ Uses CMS encryption (.NET crypto APIs - can't safely mock)
- ❌ Modifies file permissions (system state change, requires admin)
- ❌ Windows-specific (certificate stores don't exist on Linux/macOS)

**Why this can't be "easily implemented":**

- Would need full Windows environment with certificate infrastructure
- Mocking .NET Security.Cryptography is complex and fragile
- CI/CD runners can't have admin privileges (security risk)
- Mocks would be so extensive they'd test the mocks, not the code
- Cleanup would be complicated (removing test certs, permissions)

#### 2. Setup-ScheduledTask.ps1 (Admin Task Creation)

**What it does:**

- Creates Windows Task Scheduler job for automated updates
- Requires Administrator elevation check
- Sets execution context to SYSTEM user
- Configures PowerShell 7 as execution engine

**Why it CAN'T be easily tested:**

- ❌ Requires Administrator context (gates entire function)
- ❌ Creates Task Scheduler jobs (system-level operation, not sandboxable)
- ❌ Task Scheduler uses COM objects (Windows-specific, hard to mock)
- ❌ Cleanup requires deleting tasks (side effects on system)
- ❌ Only runs on Windows (CI/CD may use Linux runners)
- ❌ Behavior varies by Windows version (XP, 7, 10, 11, Server editions)

**Why this can't be "easily implemented":**

- Would need to mock Windows.System.Diagnostics.ScheduledTask COM objects
- COM mocking is fragile and version-dependent
- Requires actual admin elevation (security concern for CI/CD)
- Task creation persists on disk (cleanup failures leave artifacts)
- Testing on Linux/macOS impossible (platform-specific feature)

#### 3. Validate-Scripts.ps1 (Meta-Analysis Tool)

**What it does:**

- Scans all .ps1 and .psm1 files in project
- Uses PowerShell AST parser to check syntax without executing
- Optionally runs PSScriptAnalyzer for code quality
- Reports errors/warnings to console

**Why it CAN'T be easily tested:**

- ❌ Purpose is to ANALYZE OTHER CODE (not business logic)
- ❌ Heavily file I/O bound (reads entire project file tree)
- ❌ Works on current file structure (tests need fake file trees)
- ❌ Output is console formatting (testing output is brittle)
- ❌ Tool validates ITSELF - circular testing dependency

**Why this can't be "easily implemented":**

- Tool is itself a meta-validation script (part of CI pipeline, not production)
- Unit testing validators is lower priority than production logic
- Would require creating fake file trees for test scenarios
- Testing console output is fragile (formatting-dependent)

#### 4. Get-TelegramCredentials.ps1 (Credential Helper)

**What it does:**

- Reads encrypted CMS credential file from disk
- Decrypts using LocalMachine certificate's private key
- Returns plain-text credentials as hashtable

**Why it CAN'T be easily tested:**

- ❌ Depends on production certificate (created by Setup-Credentials.ps1)
- ❌ Reads real filesystem file (production path in $env:ProgramData)
- ❌ Decrypts actual CMS messages (can't mock .NET crypto safely)
- ❌ Works only with SYSTEM user + LocalMachine cert (context-specific)
- ❌ File permissions are production-specific

**Why this can't be "easily implemented":**

- Would need real credential file + valid certificate to decrypt
- Can't mock Unprotect-CmsMessage safely (it's .NET framework call)
- Testing requires encrypted test credentials (circular dependency)
- Better tested indirectly: mock credential loading at higher level

#### 5. Validate-Config.ps1 (Validation Wrapper)

**What it does:**

- Orchestration script that calls lib/ConfigValidation.psm1 functions
- Validates configuration file syntax and values
- Outputs results with colored console formatting

**Why it CAN'T be easily tested:**

- ❌ Wrapper script around lib functions (not core logic)
- ❌ Heavy console I/O formatting (colored output, status messages)
- ❌ File system dependent (reads actual config files)
- ❌ Exit codes signal success/failure (testing exit codes is brittle)

**Why this can't be "easily implemented":**

- The REAL validation logic is already tested in lib/ConfigValidation.psm1
- Wrapper just orchestrates: call functions → format output → exit
- Testing would duplicate lib/ConfigValidation tests + console tests
- Low value: if lib is tested, wrapper works (just a CLI layer)

### Alternative Validation for Utils

Since unit testing isn't practical, utils are validated through:

- ✅ Syntax validation (Validate-Scripts.ps1 ensures no parsing errors)
- ✅ Code quality analysis (PSScriptAnalyzer checks best practices)
- ✅ Code review (manual inspection during PR review)
- ✅ Manual testing (user testing on actual Windows before deployment)

### Understanding Overall Coverage Percentage

The overall coverage percentage reported includes setup scripts that are intentionally not unit-tested. To get accurate picture:

- **Production code coverage:** Check lib/ files (should be 80%+) ✅
- **Overall reported coverage:** Includes untestable setup tools (will appear lower)
- **What this means:** Lower overall % is expected and normal, not a sign of poor testing

Run `./tests/Run-Tests.ps1` to see current metrics. Focus on production code (lib/) coverage for code quality assessment.

#### What's Tested Well ✅

1. **Log Parsing & Detection** (14 tests)
   - Successful update completion
   - Failed updates
   - Timeout scenarios
   - Checkpoint-based filtering
   - Windows-1251 encoding support
   - Parameter validation

2. **Timestamp Regex Pattern Validation** (9 tests)
   - Planner.log with 4-digit year format (DD.MM.YYYY)
   - update_*.log with 2-digit year format (DD.MM.YY)
   - Distinction between different timestamp formats
   - Milliseconds handling in update_*.log
   - Log ID and INFO level parsing
   - Full line iteration for duration calculation
   - Single-line file edge cases
   - UpdateTime vs UpdateStartTime consistency
   - Checkpoint timestamp format compatibility

3. **Error Handling** (8 tests)
   - Missing log files
   - Missing parameters
   - Invalid parameter values
   - API errors (mocked)

4. **Configuration** (5 tests)
   - Required keys validation
   - Default values application
   - Missing config rejection

#### What's NOT Tested ⚠️

1. **Integration Tests** - Only 5% coverage
   - No full workflow tests (log parsing → notification → checkpoint)
   - Checkpoint file creation/updates untested
   - Notification content not verified

2. **Real-World Scenarios**
   - Large log files (>1MB)
   - Network timeouts
   - File permission errors
   - Clock skew or time changes
   - Concurrent executions

3. **End-to-End Testing**
   - Actual Telegram bot integration (requires real credentials)
   - Scheduled task execution
   - Real M.E.Doc log files

### Test Quality Metrics

**Unit Tests:** 57/72 (79%)

- Individual function testing (log parsing, message formatting, checkpoint operations, encoding, error handling)
- Parameter validation
- Error scenarios
- Edge cases (timestamps, special characters, marker validation)
- ✅ Excellent coverage

**Integration Tests:** 15/72 (21%)

- Dual-log scenario testing (success, failure, missing flags, timeout)
- Multi-function workflows
- Configuration validation
- Module exports
- Invoke-MedocUpdateCheck workflows
- ✅ Comprehensive coverage

**End-to-End Tests:** 0/72 (0%)

- Real service integration (Telegram API, Event Log)
- User scenario simulation
- Manual testing required
- ✗ Not automated (mocked in unit tests)

### Deployment Readiness

| Metric | Status | Comment |
|--------|--------|---------|
| Core logic tested | ✅ Yes | All critical paths covered |
| Error cases covered | ✅ Yes | Graceful failures verified |
| Parameter validation | ✅ Yes | Invalid inputs rejected |
| Real-world ready | ⚠️ Partial | Needs manual testing before production |
| Safe to deploy | ✅ Yes | With post-deployment monitoring |

### Recommended Future Improvements

**High Priority** (Would catch real bugs):

1. Add 5-10 integration tests for full workflow
2. Add checkpoint file operation tests
3. Add notification content validation tests
4. Add Invoke-MedocUpdateCheck error scenario tests

**Medium Priority** (Nice to have):

1. Add edge case tests (large files, rapid updates)
2. Add performance tests
3. Add mock-based Telegram verification tests

**Low Priority** (Cosmetic):

1. Add actual Event Log writing tests
2. Add module reload scenario tests
3. Add multi-version PowerShell tests

### Conclusion

The test suite is **adequate for production deployment** with the following caveats:

- ✅ Core business logic is thoroughly tested
- ✅ Parameter validation is complete
- ⚠️ Integration between components should be manually verified
- ⚠️ Real-world scenarios require manual testing before deploying to critical systems

See [Test Data section](#test-data) below for test data format and specifications.

## Message Format Reference

The script uses a dual-format message system to optimize for different destinations:

### Telegram Messages (Human-Readable Format)

Messages sent to Telegram use emoji and structured text for quick visual scanning:

#### Telegram Success Example

```text
✅ UPDATE OK | MY-MEDOC-SERVER
Version: 11.02.183 → 11.02.184
Started: 28.10.2025 05:15:23
Completed: 28.10.2025 05:17:20
Duration: 1 min 57 sec
Checked: 28.10.2025 12:33:45
```

#### Telegram Failure Example

```text
❌ UPDATE FAILED | MY-MEDOC-SERVER
Version: 11.02.183 → 11.02.184
Started: 28.10.2025 11:32:14
Failed at: 28.10.2025 11:47:15
Markers: ✗ Version (V), ✓ Completion (C)
Reason: Missing version confirmation in update log
Checked: 28.10.2025 11:50:06
```

#### Telegram No Update Example

```text
ℹ️ NO UPDATE | MY-MEDOC-SERVER
Checked: 28.10.2025 12:33:45
```

### Event Log Messages (Structured Format)

Messages written to Windows Event Log use key=value format for machine-readability and compliance:

#### Event Log Success Example

```text
Server=MY-MEDOC-SERVER | Status=UPDATE_OK | FromVersion=11.02.183 | ToVersion=11.02.184 | StartTime=05:15:23 | Duration=1.95m | CheckTime=28.10.2025 12:33:45
```

#### Event Log Failure Example

```text
Server=MY-MEDOC-SERVER | Status=UPDATE_FAILED | FromVersion=11.02.183 | ToVersion=11.02.184 | StartTime=11:32:14 | FailureReason=TIMEOUT_15_MINUTES | CheckTime=28.10.2025 11:35:06
```

#### Event Log No Update Example

```text
Server=MY-MEDOC-SERVER | Status=NO_UPDATE | CheckTime=28.10.2025 12:33:45
```

### Return Status Objects & EventID Handling

All major functions return status objects (hashtables) with consistent structure:

#### Status Object Structure

Every call to `Test-UpdateOperationSuccess` returns an object with these fields:

- **`Status`** (string): One of `"Success"`, `"NoUpdate"`, or `"Error"`
- **`ErrorId`** (MedocEventId enum): Numeric ID for categorizing the result (1000-1900+)
- **Additional fields** (vary by status):
  - Success: `Success`, `TargetVersion`, `UpdateTime`, `MarkerVersionConfirm`, `MarkerCompletionMarker`
  - NoUpdate: Only Status + ErrorId (minimal)
  - Error: `Message` explaining what went wrong

#### EventID Reference (MedocEventId Enum)

The module uses a centralized enum for event categorization. Use these IDs when querying Event Log or understanding return values:

| Category | EventID | Enum Member | Meaning |
|----------|---------|-------------|---------|
| **Success** | 1000 | `Success` | Update completed successfully |
| **Normal** | 1001 | `NoUpdate` | No update detected (informational) |
| **Configuration** | 1100 | `ConfigMissingKey` | Configuration key missing |
| **Configuration** | 1101 | `ConfigInvalidValue` | Configuration value invalid |
| **Environment** | 1200 | `PlannerLogMissing` | Planner.log not found |
| **Environment** | 1201 | `UpdateLogMissing` | update_YYYY-MM-DD.log not found |
| **Environment** | 1202 | `LogsDirectoryMissing` | Logs directory not found |
| **Environment** | 1203 | `CheckpointDirCreationFailed` | Failed to create checkpoint directory |
| **Environment** | 1204 | `EncodingError` | Error reading logs with Windows-1251 encoding |
| **Validation** | 1302 | `Failed` | Missing required markers (version or completion) |
| **Notification** | 1400 | `TelegramAPIError` | Telegram API error |
| **Notification** | 1401 | `TelegramSendError` | Failed to send Telegram message |
| **Checkpoint** | 1500 | `CheckpointWriteError` | Failed to write checkpoint file |
| **General** | 1900 | `GeneralError` | Unexpected error (catch-all) |

#### Example: Using EventID in Queries

```powershell
# View successful updates only (EventID 1000)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1000  # Success
} -MaxEvents 10

# View validation failures (EventID 1302)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1302  # Failed (missing markers)
} -MaxEvents 10

# View no-update events (EventID 1001 - informational, not errors)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1001  # NoUpdate
} -MaxEvents 10
```

### Version Parsing

The script parses version strings from M.E.Doc logs using the `Get-VersionInfo` function. M.E.Doc logs use a standard format with hyphen as separator:

- **Format**: `ezvit.{FromVersion}-{ToVersion}.upd`
- **Example**: `ezvit.11.02.183-11.02.184.upd` → FromVersion: `11.02.183`, ToVersion: `11.02.184`

See [lib/MedocUpdateCheck.psm1](lib/MedocUpdateCheck.psm1#L16-L54) for implementation details.

## Event Log Query Examples

Use these PowerShell commands to view and troubleshoot messages written to Windows Event Log. All examples require PowerShell 7+ (Get-WinEvent).

### View Recent Events (Last 20)

Most useful for checking recent activity:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 20
```

### View Only Success Events

To see only successful updates:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1000
} -MaxEvents 20
```

### View Only Error Events

To see only errors or failures:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    Level = 2  # Error level
} -MaxEvents 20
```

### View Specific Event ID

To see specific event type (replace 1000 with needed ID):

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    ID = 1000
} -MaxEvents 1
```

### View Events from Last Hour

To see events from the last 60 minutes:

```powershell
$oneHourAgo = (Get-Date).AddHours(-1)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    StartTime = $oneHourAgo
} -MaxEvents 20
```

### View Events from Specific Date

To see events from a specific date:

```powershell
$date = Get-Date "2025-10-28"
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
    StartTime = $date
    EndTime = $date.AddDays(1)
} -MaxEvents 20
```

## Message Formatting

The project provides message formatting functions for Telegram and Event Log output.

### Format-UpdateTelegramMessage

Generates human-readable Telegram messages with emoji support and full version/timestamp information.

**Success Output:**

```text
✅ UPDATE OK | MY-MEDOC-SERVER
Version: 11.02.185 → 11.02.186
Started: 23.10.2025 05:00:00
Completed: 23.10.2025 05:45:23
Duration: 45 min 23 sec
Checked: 28.10.2025 22:33:26
```

**Failure Output (shows which validations failed):**

```text
❌ UPDATE FAILED | MY-MEDOC-SERVER
Version: 11.02.185 → 11.02.186
Started: 23.10.2025 05:00:00
Failed at: 23.10.2025 05:25:15
Markers: ✗ Version (V), ✓ Completion (C)
Reason: Missing version confirmation in update log
Checked: 28.10.2025 22:33:26
```

**No Update Output:**

```text
ℹ️ NO UPDATE | MY-MEDOC-SERVER
Checked: 28.10.2025 22:33:26
```

### Format-UpdateEventLogMessage

Generates structured key=value messages for Event Log and SIEM tool integration.

**Success Output:**

```text
Server=MY-MEDOC-SERVER | Status=UPDATE_OK | FromVersion=11.02.185 | ToVersion=11.02.186 | UpdateStarted=23.10.2025 05:00:00 | UpdateCompleted=23.10.2025 05:45:23 | Duration=2723 | CheckTime=28.10.2025 22:33:26
```

**Failure Output (includes validation flag details):**

```text
Server=MY-MEDOC-SERVER | Status=UPDATE_FAILED | FromVersion=11.02.185 | ToVersion=11.02.186 | UpdateStarted=23.10.2025 05:00:00 | Reason=Missing required markers: Version confirmation | CheckTime=28.10.2025 22:33:26
```

---

## Checkpoint Filtering: How Duplicate Prevention Works

### Overview

The checkpoint mechanism prevents duplicate Telegram notifications when running the update
check multiple times per day. The function only sends notifications for updates detected
*after* the last run.

### Checkpoint Mechanism

1. **First Run (No Checkpoint)**

   When you run the update check for the first time:

   - No checkpoint file exists
   - The function processes all M.E.Doc log entries
   - Updates detected are logged and notifications sent
   - Checkpoint file is created with current timestamp

   ```text
   Timeline: [No checkpoint] → [Log entries] → [Detect update] → [Send notification] → [Create checkpoint]
   ```

2. **Subsequent Runs (Checkpoint Exists)**

   When you run the update check again:

   - Checkpoint file exists with timestamp from last run
   - The function filters log entries using `SinceTime` parameter
   - Only entries *after* the checkpoint time are processed
   - Duplicate updates are skipped (already processed)
   - Checkpoint file is updated with new timestamp

   ```text
   Timeline: [Old checkpoint time] <--- Filter starts here ---> [New log entries] → [No old updates] → [Update checkpoint]
   ```

### Example Scenario

**10:00 AM** - First run:

```text
- Planner.log has entry: "23.10.2025 05:00:00 Update started..."
- No checkpoint exists
- Function processes this entry
- Sends notification: "Update successful"
- Creates checkpoint with timestamp: 10:00 AM

Checkpoint file contents: "10:00:00"
```

**11:00 AM** - Second run (same server, within one hour):

```text
- Planner.log still has: "23.10.2025 05:00:00 Update started..."
- Checkpoint says: Last checked at 10:00 AM
- Function filters: Show only log entries after 10:00 AM
- Result: Old update entry is filtered out
- No notification sent (already notified)
- Checkpoint remains: 10:00 AM

Result: NO duplicate notification sent ✅
```

**Next Day** - Third run (different update):

```text
- Planner.log now has: "24.10.2025 03:00:00 Update started..."
- Checkpoint says: Last checked at 10:00 AM (previous day)
- Function filters: Show only log entries after 10:00 AM
- Result: New update entry is found
- Sends notification: "Update successful (24.10.2025)"
- Checkpoint updated: to today 10:00 AM

Result: New update is notified (not a duplicate) ✅
```

### Configuration

The checkpoint location is configurable:

```powershell
# Default: Uses $env:ProgramData\MedocUpdateCheck\checkpoints\
$config = @{
    ServerName    = "MyServer"
    MedocLogsPath = "C:\M.E.Doc\logs"
    # LastRunFile not specified → automatic checkpoint location
    BotToken      = "..."
    ChatId        = "..."
}

# Custom: Specify exact checkpoint file location
$config = @{
    ServerName    = "MyServer"
    MedocLogsPath = "C:\M.E.Doc\logs"
    LastRunFile   = "D:\Backups\MedocCheck_LastRun.txt"  # Explicit path
    BotToken      = "..."
    ChatId        = "..."
}
```

### Checkpoint File Format

The checkpoint file is simple text containing a single timestamp:

```text
28.10.2025 22:33:26
```

- Format: `dd.MM.yyyy HH:mm:ss`
- Updated after each successful notification
- Created automatically on first run
- Can be manually deleted to force reprocessing of old updates

---

## Configuration Validation Reference

All configuration parameters are validated before processing. This table shows all validation rules and recovery strategies.

| Parameter | Rule | Recovery |
|-----------|------|----------|
| **ServerName** | Non-empty, max 255 chars, alphanumeric/dash/space only | Edit config file, ensure valid hostname |
| **MedocLogsPath** | Directory must exist and be readable | Verify M.E.Doc is installed, check path permissions |
| **BotToken** | Non-empty, minimum 20 characters | Regenerate token from BotFather, check formatting |
| **ChatId** | Numeric (integer, positive or negative) | Get chat ID from `/getids` or use `@username` |
| **EncodingCodePage** | Valid Windows codepage (e.g., 1251, 65001) | Use default 1251 (Windows-1251), or valid codepage number |
| **LastRunFile** | Parent directory created if missing | Check disk space, verify permissions on parent directory |
| **EventLogSource** | Valid, max 123 chars (optional, has default) | Use default "M.E.Doc Update Check" or custom name |

### Event Log Entry IDs for Validation Failures

When a validation error occurs, the function logs a specific Event ID:

| Issue | Event ID | Level | Action Required |
|-------|----------|-------|-----------------|
| Missing config key | 1100 | Error | Add missing key to config |
| Invalid config value | 1101 | Error | Fix the value (see validation table above) |
| Invalid EncodingCodePage | 1101 | Warning | Falls back to default 1251 automatically |
| Logs directory missing | 1202 | Error | Install M.E.Doc or verify path |
| Checkpoint dir creation failed | 1203 | Error | Check disk permissions and free space |

### Testing Configuration Validation

Test your configuration locally before deployment:

```powershell
# Import module
Import-Module "./lib/MedocUpdateCheck.psm1" -Force

# Test basic config
$testConfig = @{
    ServerName    = "TEST-SERVER"
    MedocLogsPath = "C:\M.E.Doc\logs"
    BotToken      = "123456:ABCDEFGHIJKLMNOPQRSTUVWxyz"
    ChatId        = "12345"
}

# Try running (will fail at Telegram step, but validates config first)
Invoke-MedocUpdateCheck -Config $testConfig

# If you see "Missing required config key" or similar, fix the config
```

---

## Test Scenarios: Real-World Workflows

This section describes four realistic test scenarios and expected behavior for each.

### Scenario 1: First Run - Initial Detection

**Setup:** Server has M.E.Doc with logs, no checkpoint file exists

**Steps:**

1. Run update check for first time
2. Function reads M.E.Doc logs
3. Finds completed update from this morning
4. Detects both required markers (version confirmation and completion)
5. Sends Telegram notification
6. Creates checkpoint file

**Expected Result:**

- Notification received with update details ✅
- Checkpoint file created ✅
- Event Log: Success (ID 1000) ✅

**What Gets Logged:**

```text
Event ID: 1000 (Success)
Level: Information
Message: "Update check completed successfully. Update confirmed: 11.02.185 → 11.02.186"
```

### Scenario 2: Normal Operation - Subsequent Check (No New Updates)

**Setup:** Server has checkpoint from previous day, no new updates today

**Steps:**

1. Run update check (second or later time)
2. Function loads checkpoint (knows about yesterday's update)
3. Reads logs, filters entries after checkpoint time
4. No new updates found (all are older than checkpoint)
5. Sends "no update" notification (or skips if configured)
6. Updates checkpoint timestamp

**Expected Result:**

- No error (normal operation) ✅
- Event Log: NoUpdate (ID 1001) ✅
- Checkpoint time advanced ✅

**What Gets Logged:**

```text
Event ID: 1001 (NoUpdate)
Level: Information
Message: "No update detected since last check at 28.10.2025 22:33:26"
```

### Scenario 3: Update Failed - Missing Success Flag

**Setup:** Server has update log but validation failed

**Steps:**

1. Run update check
2. Function finds update entry in Planner.log
3. Finds corresponding update_YYYY-MM-DD.log
4. Checks for 2 critical markers:
   - ✅ Marker V found: Version confirmation present
   - ✅ Marker C found: Completion marker present
5. Marks update as SUCCESS or FAILED based on marker presence
6. Sends appropriate notification
7. Logs with outcome Event ID

**Expected Result:**

- Notification received with appropriate status (SUCCESS, FAILED, or NO UPDATE) ✅
- Correct outcome classification ✅
- Event Log: Correct ErrorId based on marker status ✅

**What Gets Logged:**

```text
Event ID: 1000 (Success) or 1302 (Failed) or 1001 (NoUpdate)
Level: Information or Error
Message: Describing the outcome and reason
```

### Scenario 4: Checkpoint Directory Creation Fails

**Setup:** Checkpoint directory on read-only volume or permission denied

**Steps:**

1. Run update check
2. Function attempts to create checkpoint directory
3. Permission denied (no write access)
4. Function logs error to Event Log
5. Function continues (graceful degradation)
6. Processes update detection
7. If update found, notification sent
8. Checkpoint file not saved (but update still processed)

**Expected Result:**

- Update check still completes ✅
- Notification sent (if update found) ✅
- Event Log: CheckpointDirCreationFailed (ID 1203) ✅
- Next run may duplicate notification (checkpoint not saved) ⚠️

**What Gets Logged:**

```text
Event ID: 1203 (CheckpointDirCreationFailed)
Level: Error
Message: "Failed to create checkpoint directory: Access to the path 'C:\ProgramData\...' is denied."
```

### Scenario 5: Missing M.E.Doc Logs Directory

**Setup:** M.E.Doc not installed or path misconfigured

**Steps:**

1. Run update check
2. Function validates MedocLogsPath exists
3. Path not found
4. Logs error and returns $false
5. No Telegram notification sent (validation failed)

**Expected Result:**

- Function returns $false ✅
- Event Log: LogsDirectoryMissing (ID 1202) ✅
- No notification sent (config issue, not update issue) ✅

**What Gets Logged:**

```text
Event ID: 1202 (LogsDirectoryMissing)
Level: Error
Message: "M.E.Doc logs directory not found: C:\M.E.Doc\logs"
```

---

## Warning vs Error Event Log Entries

The function distinguishes between warnings (non-critical) and errors (critical failures). Understanding this difference helps with monitoring and troubleshooting.

### Error Events (Level: Error)

**Characteristics:**

- Indicate validation failures or runtime problems
- Function returns $false (operation failed)
- Notification NOT sent (or sent with failure status)
- Require attention and remediation

**Common Error Event IDs:**

| ID | Name | Cause | Action |
|----|------|-------|--------|
| 1100 | ConfigMissingKey | Config file missing required key | Add key to config.ps1 |
| 1101 | ConfigInvalidValue | Invalid config parameter | Fix the value |
| 1202 | LogsDirectoryMissing | M.E.Doc path not found | Verify installation path |
| 1203 | CheckpointDirCreationFailed | Can't write checkpoint | Check disk permissions |
| 1302 | Failed | Missing required markers | Check update logs for V and C markers |
| 1400 | TelegramAPIError | Telegram API rejected message | Check bot token, chat ID |
| 1401 | TelegramSendError | Network error sending message | Check internet connection |

**Example Error in Event Log:**

```text
Event ID: 1202
Level: Error
Message: "M.E.Doc logs directory not found: C:\Invalid\Path"
Source: M.E.Doc Update Check
Time: 28.10.2025 22:33:26

→ Action: Update config.MedocLogsPath to correct location
```

### Warning Events (Level: Warning)

**Characteristics:**

- Indicate potential issues that don't stop processing
- Function may still return $true (operation mostly succeeded)
- Non-critical (application continues)
- Informational - for awareness, not urgent action

**Common Warning Event IDs:**

| ID | Name | Cause | Action |
|----|------|-------|--------|
| 1101 | ConfigInvalidValue (Warning) | Invalid EncodingCodePage | Falls back to 1251 automatically |

**Example Warning in Event Log:**

```text
Event ID: 1101
Level: Warning
Message: "EncodingCodePage 9999 may be invalid. Using default 1251 instead."
Source: M.E.Doc Update Check
Time: 28.10.2025 22:33:26

→ Action: Optional - verify EncodingCodePage is correct (will work with default)
```

### Informational Events (Level: Information)

**Characteristics:**

- Indicate successful operations
- Normal operational events
- No action required

**Common Informational Event IDs:**

| ID | Name | Example |
|----|------|---------|
| 1000 | Success | "Update check completed successfully..." |
| 1001 | NoUpdate | "No update detected since last check" |

### Monitoring Recommendations

**For Critical Alerts (Errors only):**

```powershell
# Monitor Event Log for critical failures
Get-WinEvent -FilterHashtable @{
    LogName      = "Application"
    ProviderName = "M.E.Doc Update Check"
    Level        = 2  # 2 = Error only
} | Where-Object { $_.EventId -in 1100, 1202, 1302, 1400 }
```

**For Operational Tracking (All levels):**

```powershell
# Track all M.E.Doc Update Check events
Get-WinEvent -FilterHashtable @{
    LogName      = "Application"
    ProviderName = "M.E.Doc Update Check"
} | Format-Table TimeCreated, Level, EventId, Message
```

---

## See Also

- [Pester Documentation](https://pester.dev/)
- [PowerShell Testing Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/learn/ps101/09-functions)
- [lib/MedocUpdateCheck.psm1](lib/MedocUpdateCheck.psm1) - Module source code
- [README.md](README.md) - User documentation
- [CONTRIBUTING.md](CONTRIBUTING.md) - Developer guidelines
