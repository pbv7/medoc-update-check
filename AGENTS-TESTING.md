# Testing Guide for Agents

Complete testing instructions and best practices for the M.E.Doc Update Check project,
including test data, Pester syntax, enum usage, and validation procedures.

## Running Tests

### All Tests

```powershell
./tests/Run-Tests.ps1
```

### Specific Test File

```powershell
Invoke-Pester -Path tests/MedocUpdateCheck.Tests.ps1 -PassThru
```

### Single Test by Pattern

```powershell
Invoke-Pester -Path tests/MedocUpdateCheck.Tests.ps1 `
  -FullyQualifiedName "*should detect successful update*"
```

## Test Coverage

**Current Status:** Run `./tests/Run-Tests.ps1` to verify test coverage (output shows
"Tests Passed: X")

Breakdown by category:

- **Unit Tests:** Message formatting, checkpoint operations, log parsing, encoding,
  error handling
- **Integration Tests:** Dual-log validation, configuration validation, module exports,
  Invoke-MedocUpdateCheck workflows

## Test Data & Encoding

All test data files in `tests/test-data/` are **Windows-1251 encoded** (required for M.E.Doc
Cyrillic log support).

### Dual-Log Test Structure

Each test scenario consists of a directory with both `Planner.log` and `update_YYYY-MM-DD.log`:

```text
dual-log-success/           - All 3 success flags present
dual-log-no-update/         - No update entries in Planner.log
dual-log-missing-updatelog/ - Update triggered but log file missing
dual-log-missing-flag1/     - Missing infrastructure validation flag
dual-log-missing-flag2/     - Missing service restart flag
dual-log-missing-flag3/     - Missing version confirmation flag
dual-log-wrong-version/     - Version number mismatch
```

### If Modifying Test Data

1. Create files with proper Windows-1251 encoding using PowerShell:

   ```powershell
   $encoding = [System.Text.Encoding]::GetEncoding(1251)
   $text = "Your content here"
   [System.IO.File]::WriteAllBytes($Path, $encoding.GetBytes($text))
   ```

2. Include both Planner.log and update_*.log for functional tests
3. Ensure Cyrillic characters are properly encoded
4. Re-run tests to verify: `./tests/Run-Tests.ps1`

## Test Assertions

**Current Pester Version:** 5.7.1

**Syntax Details:**

```powershell
# Property existence check (5.7.1+)
($result.Keys -contains "Success") | Should -Be $true

# Boolean assertion
$result.Success | Should -Be $true

# String contains
$output | Should -Match "pattern"
```

## Test Artifact Cleanup (AfterAll)

Test suites automatically clean up temporary checkpoint files after all tests complete,
regardless of pass/fail/skip outcome.

### Why Cleanup Matters

- ✅ Prevents accumulation of temporary files in test-data directory
- ✅ Working directory stays clean after test runs
- ✅ Allows repeated test runs without artifact pollution
- ✅ Best practice for professional test suites

### Implementation

The `AfterAll` block in `tests/MedocUpdateCheck.Tests.ps1` automatically removes:

- All `checkpoint-*.txt` files generated during test execution
- Recursively from all test-data subdirectories
- Preserves actual test fixtures (`Planner.log`, `update_*.log` files)

### When Adding New Tests

If your test creates temporary files:

1. Use unique filenames with `[guid]::NewGuid()` to avoid conflicts
2. Rely on `AfterAll` for cleanup, OR
3. Use try/finally for immediate cleanup if the file is critical

**Example (relying on AfterAll):**

```powershell
It "Should handle custom checkpoint path" {
    $tempCheckpoint = Join-Path $testDataDir ("checkpoint-test-{0}.txt" `
        -f ([guid]::NewGuid()))

    $result = Invoke-MedocUpdateCheck -Config @{
        ServerName    = "TestServer"
        MedocLogsPath = $logsDir
        LastRunFile   = $tempCheckpoint
        BotToken      = "token"
        ChatId        = "123"
    }

    # File created during test, auto-cleaned by AfterAll
}
```

## Variable Scoping in Tests

**CRITICAL:** Pester has strict scoping rules.

**Wrong:**

```powershell
BeforeAll {
    $testDataDir = "tests/test-data"
}

It "should parse log" {
    $path = "$testDataDir/dual-log-success"  # Error: $testDataDir is null
}
```

**Correct:**

```powershell
BeforeAll {
    $script:testDataDir = "tests/test-data"
}

It "should parse log" {
    $logsDir = "$script:testDataDir/dual-log-success"  # Works!
}
```

## Using Enums in Tests

The MedocEventId enum is defined in the module for centralized event ID management. To use
enum values in tests, follow this pattern:

### Step 1: Import Module at Compile Time

At the very top of the test file (before any other code), add the `using module` directive:

```powershell
# Import module at compile time to make enum types available
using module "..\lib\MedocUpdateCheck.psm1"
```

This makes the `MedocEventId` enum available throughout the test file.

### Step 2: Reference Enum Values Directly in Tests

Use the enum values directly in test assertions and when creating test data:

```powershell
# In test assertions
$result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)

# In mock/test data creation
@{
    Status  = "NoUpdate"
    ErrorId = [MedocEventId]::NoUpdate
    Message = "No update operation found in logs"
}

# When comparing with Event Log integers
$eventRecord.EventId | Should -Be ([int][MedocEventId]::Success)
```

### Step 3: Available Enum Values

All `MedocEventId` enum members can be referenced:

```powershell
[MedocEventId]::Success                     # 1000 - Update successful
[MedocEventId]::NoUpdate                    # 1001 - No update detected
[MedocEventId]::ConfigMissingKey            # 1100 - Missing config key
[MedocEventId]::ConfigInvalidValue          # 1101 - Invalid config value
[MedocEventId]::PlannerLogMissing           # 1200 - Planner.log not found
[MedocEventId]::UpdateLogMissing            # 1201 - update_*.log not found
[MedocEventId]::LogsDirectoryMissing        # 1202 - Logs directory not found
[MedocEventId]::CheckpointDirCreationFailed # 1203 - Checkpoint dir creation failed
[MedocEventId]::EncodingError               # 1204 - Encoding error reading logs
[MedocEventId]::Flag1Failed                 # 1300 - Infrastructure validation failed
[MedocEventId]::Flag2Failed                 # 1301 - Service restart failed
[MedocEventId]::Flag3Failed                 # 1302 - Version confirmation failed
[MedocEventId]::MultipleFlagsFailed         # 1303 - Multiple flags missing
[MedocEventId]::TelegramAPIError            # 1400 - Telegram API error
[MedocEventId]::TelegramSendError           # 1401 - Telegram message send failed
[MedocEventId]::CheckpointWriteError        # 1500 - Checkpoint write failed
[MedocEventId]::GeneralError                # 1900 - Unexpected error
```

### Why Use Enums Instead of Hardcoding Numbers?

- **Type Safety**: PowerShell validates enum member names at compile time
- **Maintainability**: If event ID values change, all tests automatically use the new values
- **Documentation**: Enum names self-document what each ID represents
- **Prevents Errors**: No risk of typos with hardcoded numbers (e.g., 1002 instead of 1001)

## Setup Commands for CI/CD

**Note for Agents:** These commands are executed by GitHub Actions in a clean Windows sandbox
environment, NOT on local development machines. Do NOT execute these without user permission.

### GitHub Actions CI/CD Setup (Automatic)

The `.github/workflows/tests.yml` handles all setup automatically:

```powershell
# These run in clean Windows sandbox - no local system pollution
# Tests run on PowerShell 7 (latest)
Install-Module Pester -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Force
```

**Environment:** Clean Windows runner with PowerShell 7+, discarded after workflow completion.

### Local Development (Requires User Decision & PowerShell 7+)

**IMPORTANT:** Local testing requires PowerShell 7 or later. Verify your PowerShell version:

```powershell
# Check your PowerShell version
$PSVersionTable.PSVersion
# Expected output: 7.x or higher
```

If user requests local testing, suggest running this (requires user approval):

```powershell
# BEFORE suggesting, ask user permission
# "Would you like to install Pester and PSScriptAnalyzer locally for testing?"

# Only if user approves:
Install-Module Pester -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Force

# Then run tests:
./tests/Run-Tests.ps1
```

**Environment:** User's local Windows system with PowerShell 7+ - test before committing.

### Checking Existing Installation

Before suggesting installation, check if modules are available:

```powershell
# Check Pester
if (Get-Module -ListAvailable -Name Pester) {
    Write-Host "Pester already installed"
} else {
    Write-Host "Pester not found - user should install if testing locally"
}

# Check PSScriptAnalyzer
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    Write-Host "PSScriptAnalyzer already installed"
} else {
    Write-Host "PSScriptAnalyzer not found - optional for development"
}
```

## Syntax Validation

**All code changes must be validated with PowerShell 7 before committing.** This ensures
compatibility and catches syntax errors.

**IMPORTANT:** There are TWO types of validation tools with different purposes:

| Tool | Purpose | Required? | What It Checks |
|------|---------|-----------|---|
| **Validate-Scripts.ps1** | Syntax checking | ✅ Always | Catches parsing errors, missing brackets, invalid keywords |
| **PSScriptAnalyzer** | Code quality | ⚠️ Recommended | Best practices, style, security, performance |

### 1. Validate PowerShell Version

Always use PowerShell 7+ for validation:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
# Expected output: 7.x or higher
```

### 2. Syntax Validation (Required)

**Use the built-in validation utility - ALWAYS RUN THIS:**

```powershell
# Validates all .ps1 and .psm1 files in the project for syntax errors
# Safe: Does NOT execute any code
pwsh ./utils/Validate-Scripts.ps1

# With verbose output
pwsh ./utils/Validate-Scripts.ps1 -Verbose
```

#### What Validate-Scripts.ps1 Checks

- ✓ Valid PowerShell syntax (no parsing errors)
- ✓ Balanced brackets, quotes, parentheses
- ✓ Valid keywords and cmdlet names
- ✓ All files scan from project root
- ✓ No false positives (uses PowerShell's internal parser)

#### Alternative: Manual Syntax Validation

Single file:

```powershell
pwsh -NoProfile -Command {
    $content = Get-Content -Path './Run.ps1' -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $content, [ref]$null, [ref]$null)
    Write-Host "✓ Syntax valid"
}
```

All scripts:

```powershell
pwsh -NoProfile -Command {
    $scripts = Get-ChildItem -Path '.' -Filter '*.ps1', '*.psm1' -Recurse |
        Where-Object { $_.FullName -notmatch '\.git' }

    $scripts | ForEach-Object {
        Write-Host "Checking: $($_.Name)"
        $content = Get-Content -Path $_.FullName -Raw
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) {
            Write-Host "  ❌ ERROR: $($parseErrors[0].Message)"
            exit 1
        }
        Write-Host "  ✓ Valid"
    }
    Write-Host "✓ All scripts valid"
}
```

### 3. Code Quality (PSScriptAnalyzer)

**Optional but highly recommended for production code:**

```powershell
# Check if PSScriptAnalyzer is installed
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    pwsh -NoProfile -Command {
        Import-Module PSScriptAnalyzer -Force
        $issues = Invoke-ScriptAnalyzer -Path './lib' -Recurse
        if ($issues) {
            Write-Host "⚠️ PSScriptAnalyzer issues found:"
            $issues | Format-Table
        } else {
            Write-Host "✓ No PSScriptAnalyzer issues"
        }
    }
} else {
    Write-Host "PSScriptAnalyzer not installed. Install with:"
    Write-Host "  pwsh -Command 'Install-Module PSScriptAnalyzer -Force'"
}
```

#### What PSScriptAnalyzer Checks

- ⚠️ Code style (naming conventions, spacing)
- ⚠️ Best practices (deprecated cmdlets, unsafe patterns)
- ⚠️ Security (hardcoded credentials, eval usage)
- ⚠️ Performance (inefficient loops, unnecessary conversions)

#### Expected Warnings in This Project

**These warnings are acceptable and expected** - they do not indicate problems:

| Warning | Where | Why It Occurs | Why It's OK |
|---------|-------|---|---|
| **PSAvoidUsingWriteHost** | Test files, Run-Tests.ps1 | CLI utilities and tests use `Write-Host` for colored output | `Write-Host` is necessary for interactive status messages with colors and formatting |
| **PSUseBOMForUnicodeEncodedFile** | Multiple files | Files contain non-ASCII characters (Cyrillic comments/text) | Code works perfectly; BOM is optional in Windows-1251 encoding |
| **PSReviewUnusedParameter** | Test mock functions | Mock functions must accept parameters for signature compatibility | Parameters must match function being mocked even if unused |
| **PSUseShouldProcessForStateChangingFunctions** | MedocUpdateCheck.psm1 | `New-OutcomeObject` is a test helper, not a production state-changing function | Helper functions don't need ShouldProcess support |

**CI/CD Behavior:**

- **Local validation** (`./utils/Validate-Scripts.ps1`): Only fails on **Errors**, not warnings
- **GitHub Actions** (`Run PSScriptAnalyzer` step): Same behavior - only fails on **Errors**,
  not warnings
- **Test files excluded**: `*.Tests.ps1` files are excluded from analyzer (intentional)

**Note:** PSScriptAnalyzer is designed for library code. This project uses CLI utilities that
legitimately need direct console control for user interaction. All warnings are style-related
and do not affect functionality or security.

### 4. Complete Pre-commit Validation Workflow

Run this before committing changes:

```powershell
# After making code changes:

# 1. Verify PowerShell 7+
Write-Host "Step 1: Checking PowerShell version..."
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'

# 2. Validate syntax (REQUIRED - always run)
Write-Host "`nStep 2: Validating script syntax..."
pwsh ./utils/Validate-Scripts.ps1

# 3. Run unit tests
Write-Host "`nStep 3: Running unit tests..."
./tests/Run-Tests.ps1

# 4. Check code quality (optional but recommended)
Write-Host "`nStep 4: Checking code quality..."
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    pwsh -NoProfile -Command {
        Import-Module PSScriptAnalyzer -Force
        Invoke-ScriptAnalyzer -Path './lib' -Recurse
    }
} else {
    Write-Host "PSScriptAnalyzer not installed (optional)"
}

# If all pass, commit
Write-Host "`n✅ All validations passed! Ready to commit."
git add .
git commit -m "Your commit message"
```

### Validation Checklist

- ✓ PowerShell 7+ is being used
- ✓ All scripts have valid syntax (Validate-Scripts.ps1)
- ✓ All tests pass (./tests/Run-Tests.ps1)
- ⚠️ Code quality passes (PSScriptAnalyzer - optional)
- ⚠️ All scripts include `#Requires -Version 7.0` (checked by script)

## Common Testing Pitfalls

### Pitfall 1: DateTime Parameter with Null

**Problem:**

```powershell
function Get-Updates([datetime]$SinceTime = $null) { }
# Error: Cannot convert null to type System.DateTime
```

**Solution:**

```powershell
# Remove type constraint - let logic handle null check
function Get-Updates($SinceTime) {
    if ($SinceTime -and $SinceTime -gt [datetime]::MinValue) {
        # Filter by date
    }
}
```

### Pitfall 2: Test Variables Not Visible

**Problem:**

```powershell
BeforeAll {
    $logPath = "tests/test-data/sample.txt"
}
It "test" {
    Get-Content $logPath  # Error: $logPath is $null
}
```

**Solution:**

```powershell
BeforeAll {
    $script:logPath = "tests/test-data/sample.txt"  # Use $script: prefix
}
It "test" {
    Get-Content $script:logPath  # Works!
}
```

### Pitfall 3: Test Data Encoding Mismatch

**Problem:**

```powershell
# Test data encoding issue: logs must be Windows-1251
$result = Test-UpdateOperationSuccess -MedocLogsPath "dual-log-success"
# If encoding is wrong, patterns won't match
```

**Solution:**

```powershell
# Ensure test data directories use Windows-1251 encoding
# In tests, create files with proper encoding
$result = Test-UpdateOperationSuccess -MedocLogsPath "dual-log-success"

# To fix test file encoding to Windows-1251 (PowerShell native - all platforms):
$encoding = [System.Text.Encoding]::GetEncoding(1251)
$content = Get-Content -Path sample-log.txt -Raw
[System.IO.File]::WriteAllBytes("sample-log.txt", $encoding.GetBytes($content))
```

**Alternative for macOS/Linux (if iconv is available):**

```bash
iconv -f UTF-8 -t WINDOWS-1251 sample-log.txt > sample-log.txt.tmp && mv sample-log.txt.tmp sample-log.txt
```

**Why PowerShell is preferred:** Works on all platforms (Windows, macOS, Linux) without
external tool dependencies. The iconv approach requires the tool to be installed on the system.

### Pitfall 4: Event Log Access on macOS/Linux

**Problem:**

```powershell
# This warns on non-Windows systems
Write-EventLogEntry -Message "Test"
# WARNING: Could not write to Event Log
```

**Expected Behavior:** Warnings are normal and expected on non-Windows. Tests continue
normally. This is not an error.

### Pitfall 5: Pester Assertion Syntax

**Problem:**

```powershell
$result | Should -HaveKey "Success"  # Wrong syntax for 5.7.1
# Error: ParameterBindingException
```

**Solution:**

```powershell
($result.Keys -contains "Success") | Should -Be $true  # Correct for 5.7.1
```

---

**For more information:**

- See [AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md) for code style and language features
- See [AGENTS-SECURITY.md](AGENTS-SECURITY.md) for testing security practices
