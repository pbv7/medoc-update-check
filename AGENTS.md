# AGENTS.md

AI coding agents guide for the M.E.Doc Update Check project. This file provides context and instructions to help AI agents (Claude, GitHub Copilot, Cursor, Factory, etc.) work effectively on this codebase.

## Project Overview

**Project:** M.E.Doc Update Check

**Purpose:** Automated script to monitor M.E.Doc server updates and send Telegram notifications

**Language:** PowerShell 7+ (Windows native)

**Scope:** Windows-only, enterprise M.E.Doc server monitoring

**Authors:** See [README.md](README.md#authors) for list of authors and contributors

**License:** See [LICENSE](LICENSE) file for details

### Key Constraints

- **Requires PowerShell 7.0 or later** (modern, cross-platform, actively maintained by Microsoft)
- Cyrillic text support required: **Windows-1251 encoding** for M.E.Doc logs (not UTF-8)
- No external dependencies beyond PowerShell built-ins and standard modules
- Cross-platform testing: Workflow tests on Windows via GitHub Actions

## Dual-Log Update Detection Strategy

The project uses a robust three-phase validation approach to detect M.E.Doc server updates:

### Phase 1: Update Trigger Detection (Planner.log)

- Searches for "Завантаження оновлення ezvit.X.X.X-X.X.X.upd" entries
- Confirms an update was initiated on the server
- Extracts timestamp and target version number from filename

### Phase 2: Update Log File Location

- Dynamically constructs path to `update_YYYY-MM-DD.log` (DATE = update start date)
- M.E.Doc creates separate detailed logs during update process
- If log missing → update marked as FAILED

### Phase 3: Success Flag Validation (3 Mandatory Flags)

All three flags must be present for SUCCESS. Missing any flag = FAILURE:

1. **Infrastructure Validation**
   - Pattern: `IsProcessCheckPassed DI: True, AI: True`
   - Confirms: .NET infrastructure validation successful

2. **Service Restart Success**
   - Pattern: `Службу ZvitGrp запущено` (service started, accepts variations like "з підвищенням прав" - with elevated privileges)
   - Confirms: Core ZvitGrp service successfully restarted
   - Real log example: `Службу ZvitGrp запущено з підвищенням прав`

3. **Version Confirmation**
   - Pattern: `Версія програми - {TARGET_VERSION}` (program version - {number})
   - Confirms: System reports expected version number
   - Real log example: `Версія програми - 186` means v11.02.186 confirmed

## Setup Commands for CI/CD

**Note for Agents:** These commands are executed by GitHub Actions in a clean Windows sandbox environment, NOT on local development machines. Do NOT execute these without user permission.

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

### Validating Changes with PowerShell 7 (pwsh)

**All code changes must be validated with PowerShell 7 before committing.** This ensures compatibility and catches syntax errors.

**IMPORTANT:** There are TWO types of validation tools with different purposes:

| Tool | Purpose | Required? | What It Checks |
|------|---------|-----------|----------------|
| **Validate-Scripts.ps1** | Syntax checking | ✅ Always | Catches parsing errors, missing brackets, invalid keywords |
| **PSScriptAnalyzer** | Code quality | ⚠️ Recommended | Best practices, style, security, performance |

#### 1. Validate PowerShell Version

Always use PowerShell 7+ for validation:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
# Expected output: 7.x or higher
```

#### 2. Syntax Validation (Required)

**Use the built-in validation utility - ALWAYS RUN THIS:**

```powershell
# Validates all .ps1 and .psm1 files in the project for syntax errors
# Safe: Does NOT execute any code
pwsh ./utils/Validate-Scripts.ps1

# With verbose output
pwsh ./utils/Validate-Scripts.ps1 -Verbose
```

##### What Validate-Scripts.ps1 checks

- ✓ Valid PowerShell syntax (no parsing errors)
- ✓ Balanced brackets, quotes, parentheses
- ✓ Valid keywords and cmdlet names
- ✓ All files scan from project root
- ✓ No false positives (uses PowerShell's internal parser)

##### Alternative: Manual syntax validation

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

#### 3. Code Quality (PSScriptAnalyzer)

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

##### What PSScriptAnalyzer checks

- ⚠️ Code style (naming conventions, spacing)
- ⚠️ Best practices (deprecated cmdlets, unsafe patterns)
- ⚠️ Security (hardcoded credentials, eval usage)
- ⚠️ Performance (inefficient loops, unnecessary conversions)

##### Expected Warnings in This Project

**These warnings are acceptable and expected** - they do not indicate problems:

| Warning | Why It Occurs | Why It's OK |
|---------|---------------|-----------|
| **PSAvoidUsingWriteHost** | CLI utilities use `Write-Host` for colored console output | `Write-Host` is necessary for status messages with colors and formatting |
| **PSUseBOMForUnicodeEncodedFile** | Files contain non-ASCII characters (Cyrillic comments) | Code works perfectly; BOM is optional |

**Note:** PSScriptAnalyzer is designed for library code. This project uses CLI utilities that legitimately need direct console control for user interaction. All warnings are style-related and do not affect functionality or security.

#### 4. Complete Pre-commit Validation Workflow

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

##### Validation Checklist

- ✓ PowerShell 7+ is being used
- ✓ All scripts have valid syntax (Validate-Scripts.ps1)
- ✓ All tests pass (./tests/Run-Tests.ps1)
- ⚠️ Code quality passes (PSScriptAnalyzer - optional)
- ⚠️ All scripts include `#Requires -Version 7.0` (checked by script)

## PowerShell 7+ Features for Code Generation

When generating new code or refactoring, **leverage modern PowerShell 7+ features**:

### Recommended PS7+ Features

1. **String Interpolation** (instead of concatenation)

   ```powershell
   # PS7+: Clean, readable
   Write-Host "Processing file: $filePath with encoding $encodingCodePage"

   # Avoid: Verbose concatenation
   Write-Host "Processing file: " + $filePath + " with encoding " + $encodingCodePage
   ```

2. **Ternary Operator** (if expressions)

   ```powershell
   # PS7+: Concise
   $result = $success ? "Passed" : "Failed"

   # Avoid: Verbose if-else for simple assignments
   if ($success) { $result = "Passed" } else { $result = "Failed" }
   ```

3. **Null Coalescing Operator** (for defaults)

   ```powershell
   # PS7+: Clean default handling
   $value = $input ?? "default"

   # Avoid: Verbose null checks
   if ($null -eq $input) { $value = "default" } else { $value = $input }
   ```

4. **Constructor Syntax** (::new instead of New-Object)

   ```powershell
   # PS7+: Modern syntax (already updated in this project)
   [System.Security.Principal.WindowsPrincipal]::new($identity)

   # Avoid: Legacy syntax
   New-Object System.Security.Principal.WindowsPrincipal($identity)
   ```

5. **Array Slicing & Methods**

   ```powershell
   # PS7+: Rich array operations
   $lines = Get-Content $file | Where-Object { $_ -match "pattern" }

   # PS7+: ForEach method
   $lines.ForEach({ $_ -replace "old", "new" })
   ```

### When NOT to Use Advanced Features

- **Clarity over cleverness**: If code is less readable, use traditional syntax
- **Compatibility concerns**: `#Requires -Version 7.0` already enforces PS7+
- **Performance**: Use traditional loops for very large datasets when faster

## Timestamp Parsing: Different Regex for Different Log Files

**CRITICAL:** M.E.Doc uses two log files with **different timestamp formats**. Using the wrong regex pattern will cause timestamp parsing to fail.

### Why Different Formats?

- **Planner.log**: Planning/scheduler log (4-digit year: DD.MM.YYYY)
- **update_*.log**: Execution/process log (2-digit year: DD.MM.YY)

Different purposes = Different formats. This is not a bug; it's architectural.

### Correct Regex Patterns

**Planner.log (lib/MedocUpdateCheck.psm1, Line 227):**

```powershell
# MUST match 4-digit year format
if ($line -match '^(\d{2}\.\d{2}\.\d{4})\s+(\d{1,2}:\d{2}:\d{2})\s+(.+)$') {
    # Parse with format: 'dd.MM.yyyy H:mm:ss'
}
```

**update_*.log (lib/MedocUpdateCheck.psm1, Line 322):**

```powershell
# MUST match 2-digit year format (milliseconds are ignored in parsing)
if ($line -match '^(\d{2}\.\d{2}\.\d{2})\s+(\d{1,2}:\d{2}:\d{2})') {
    # Parse with format: 'dd.MM.yy H:mm:ss'
}
```

### Example Data

**Planner.log:** `23.10.2025 5:00:00 Завантаження оновлення ezvit.11.02.185-11.02.186.upd`

- Regex: `\d{4}` ✅ matches 2025
- Format: `dd.MM.yyyy` ✅ correct

**update_*.log:** `23.10.25 10:30:15.100 00000001 INFO    IsProcessCheckPassed DI: True, AI: True`

- Regex: `\d{2}` ✅ matches 25 (= 2025)
- Format: `dd.MM.yy` ✅ correct
- Milliseconds (.100) ignored in parsing

### ❌ Common Mistakes

```powershell
# WRONG: Using 4-digit regex on update_*.log (will not match!)
if ($line -match '^\d{2}\.\d{2}\.\d{4}') { ... }  # ❌ Fails: "25.10.25" doesn't match \d{4}

# WRONG: Using wrong DateTime format
[DateTime]::ParseExact($str, 'dd.MM.yyyy H:mm:ss', $null)  # ❌ Fails on "25.10.25"

# WRONG: Not handling milliseconds in regex
if ($line -match '^\d{2}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}') { ... }  # ⚠️ Brittle
```

### ✅ Correct Approach

```powershell
# 1. Use correct regex for each log type
# Planner.log: \d{4} for 4-digit year
# update_*.log: \d{2} for 2-digit year

# 2. Use correct DateTime format
# Planner.log: 'dd.MM.yyyy H:mm:ss'
# update_*.log: 'dd.MM.yy H:mm:ss' (milliseconds ignored)

# 3. Test both formats
# Run tests: ./tests/Run-Tests.ps1
```

### Testing

**9 tests validate both timestamp formats:**

- 3 tests for regex pattern validation (4-digit vs 2-digit)
- 3 tests for format handling (milliseconds, log ID/level, line iteration)
- 3 tests for edge cases (single-line files, consistency, checkpoint filtering)

See [tests/MedocUpdateCheck.Tests.ps1](tests/MedocUpdateCheck.Tests.ps1) - "Timestamp regex pattern validation" context.

## Universal Code: System Variables Instead of Hardcoded Paths

**Critical for portability:** Windows installations may have custom drive layouts or security policies that change standard paths.

### Environment Variables to Use

Always use `$env:` variables for system paths instead of hardcoding:

- **`$env:ProgramData`** - Program data directory (credentials, checkpoints)
  - Default: `C:\ProgramData`
  - Standard location for system-wide application data
  - Readable by SYSTEM user in Task Scheduler

- **`$env:COMPUTERNAME`** - Server/computer hostname (config filenames, auto-detection)
  - Example: `MAINOFFICE-01`, `WAREHOUSE-DB`
  - Used for auto-generated config filenames
  - Replaces manual hostname typing

- **`$env:SystemRoot`** - Windows installation directory
  - Default: `C:\Windows`
  - Use when accessing Windows system files

- **`$env:TEMP`, `$env:TMP`** - Temporary directory
  - Safe location for temporary file creation

### Examples

**❌ NEVER DO THIS (hardcoded paths):**

```powershell
$credDir = "C:\ProgramData\MedocUpdateCheck\credentials"
$checkpointDir = "C:\ProgramData\MedocUpdateCheck\checkpoints"
$configFile = "C:\Windows\Config\app.ini"
```

**✅ ALWAYS DO THIS (system variables):**

```powershell
$credDir = "$env:ProgramData\MedocUpdateCheck\credentials"
$checkpointDir = "$env:ProgramData\MedocUpdateCheck\checkpoints"
$configFile = "$env:SystemRoot\Config\app.ini"
$configFileName = "Config-$env:COMPUTERNAME.ps1"
```

### Benefits of System Variables

1. **Portability**: Works on systems with custom drive layouts
2. **Security**: Respects Windows security policies and SYSTEM user permissions
3. **Maintainability**: No need to update code if Windows paths change
4. **Best Practices**: Follows Windows application development standards

---

## PowerShell 7+ Removed Features: NEVER Use These

**CRITICAL:** PowerShell 7 removed many legacy cmdlets and modules. When generating code, ALWAYS avoid these deprecated features.

### Removed Event Log Cmdlets

```powershell
# ❌ REMOVED IN PS7+ - DO NOT USE:
Get-EventLog -LogName Application           # REMOVED
Write-EventLog -LogName Application         # REMOVED
New-EventLog -LogName Application           # REMOVED
Clear-EventLog -LogName Application         # REMOVED

# ✅ CORRECT APPROACH - Use these instead:
[System.Diagnostics.EventLog]::SourceExists()           # Check if source exists
[System.Diagnostics.EventLog]::CreateEventSource()      # Create event source
$eventLog = [System.Diagnostics.EventLog]::new()        # Create instance
$eventLog.WriteEntry($message, $entryType, $eventId)   # Write entry
Get-WinEvent -FilterHashtable @{ ... }                  # Query events
```

**Project Implementation:** ✅ Uses .NET EventLog class in `Write-EventLogEntry` function (lib/MedocUpdateCheck.psm1)

### Removed WMI Cmdlets

```powershell
# ❌ REMOVED IN PS7+ - DO NOT USE:
Get-WmiObject -Class Win32_Process         # REMOVED
Invoke-WmiMethod -Class Win32_Process      # REMOVED
Remove-WmiObject -Path "..."               # REMOVED
Register-WmiEvent -Query "..."             # REMOVED

# ✅ CORRECT APPROACH - Use these instead:
Get-CimInstance -ClassName Win32_Process   # Use CIM cmdlets
Invoke-CimMethod -ClassName Win32_Process  # Use CIM cmdlets
Remove-CimInstance -InputObject ...        # Use CIM cmdlets
Register-CimIndicationEvent -Query "..."   # Use CIM cmdlets
```

**Project Status:** ✅ Project doesn't use WMI, so no impact

### Removed Modules

```powershell
# ❌ REMOVED IN PS7+ - DO NOT USE:
Import-Module PSScheduledJob               # REMOVED ENTIRELY
Get-ScheduledJob                           # REMOVED
Register-ScheduledJob                      # REMOVED
Unregister-ScheduledJob                    # REMOVED

# ✅ CORRECT APPROACH - Use these instead:
Get-ScheduledTask                          # Native Windows cmdlet
Register-ScheduledTask                     # Native Windows cmdlet
Unregister-ScheduledTask                   # Native Windows cmdlet
Start-ScheduledTask                        # Native Windows cmdlet
```

**Project Implementation:** ✅ Uses native Task Scheduler cmdlets (utils/Setup-ScheduledTask.ps1)

### Legacy Syntax to Avoid

```powershell
# ❌ OLD (Works but outdated):
$obj = New-Object System.Diagnostics.EventLog

# ✅ NEW (Modern PS7+ syntax):
$obj = [System.Diagnostics.EventLog]::new()
```

### Pre-Commit Validation for Agents

Before returning code to user, search for removed features:

```powershell
# Search for removed cmdlets in generated code
$removed = @('Get-EventLog', 'Write-EventLog', 'New-EventLog', 'Get-WmiObject',
             'Invoke-WmiMethod', 'Remove-WmiObject', 'PSScheduledJob')

foreach ($cmd in $removed) {
    if (Select-String -Path *.ps1 -Pattern $cmd -Quiet) {
        WARN: "Generated code contains removed cmdlet: $cmd"
    }
}
```

## Code Style & Conventions

### PowerShell Naming Standards

Follow **Verb-Noun** format for all functions:

```powershell
# Correct
function Test-UpdateOperationSuccess { }
function Get-UpdateStatusFromLog { }
function Invoke-MedocUpdateCheck { }
function Write-EventLogEntry { }
```

**Approved Verbs:** Get, Test, Invoke, Write, New, Set, Remove, Find, Select, Out, Format, Group, Measure, Compare, Copy, Join, Split, Export, Import, ConvertTo, ConvertFrom, Update, Add, Disable, Enable, Save, Show, Stop, Start, Suspend, Restart, Resume.

### Module Structure

**Universal Module:** `lib/MedocUpdateCheck.psm1`

- Contains ALL reusable functions
- Exports public functions via `Export-ModuleMember`
- No per-server customization in this file
- Functions should be idempotent where possible

**Per-Server Configuration:** `configs/Config-$env:COMPUTERNAME.ps1`

- Server-specific variables only (names, credentials, Telegram tokens)
- Filename automatically uses server's hostname (no manual typing needed)
- Use template: `configs/Config.template.ps1`
- Never commit real credentials; use placeholders

**Entry Point:** `Run.ps1`

- **DO NOT EDIT** for per-server use
- Load appropriate config file dynamically
- Call functions from imported module
- Universal across all servers

**Shared Validation Library:** `lib/ConfigValidation.psm1`

- Centralized configuration validation functions
- Imported by `lib/MedocUpdateCheck.psm1` and `utils/Validate-Config.ps1`
- Eliminates code duplication across validation logic
- Provides consistent validation across both code paths
- Functions: `Test-ServerName`, `Test-MedocLogsPath`, `Test-BotToken`, `Test-ChatId`, `Test-EncodingCodePage`, `Test-CheckpointPath`
- Each function returns standardized result object with `Valid`, `ErrorMessage`, optional `IsWarning` and `DefaultValue` properties

### Parameter Handling

**DO:**

```powershell
# Untyped parameter for null handling
function Test-UpdateOperationSuccess($MedocLogsPath) {
    if (-not $MedocLogsPath) { ... }
}

# Use -ErrorAction Stop in tests
Invoke-Pester -Path tests/ -ErrorAction Stop
```

**DON'T:**

```powershell
# Never use [datetime] with = $null
function Get-Updates([datetime]$SinceTime = $null) { }

# This causes PowerShell type conversion errors
# Fix: Remove type constraint entirely
function Get-Updates($SinceTime) { }
```

**Why:** PowerShell attempts type conversion before parameter binding. A `[datetime]` constraint on `$null` raises error.

### Variable Scoping in Tests

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

### Encoding & Internationalization

**CRITICAL:** All test data files use **Windows-1251** encoding, not UTF-8.

```powershell
# Test files include Cyrillic Ukrainian text
# Example: "Завантаження оновлення" (Update download)

# When reading in PowerShell (default encoding handles this):
$content = Get-Content -Path $path -Encoding Default

# Do NOT assume UTF-8 for M.E.Doc logs
$content = Get-Content -Path $path -Encoding UTF8  # WRONG
```

**Why:** M.E.Doc is a Ukrainian accounting software. Its Event Logs use Windows-1251 (CP1251) encoding for Cyrillic characters. Tests must match this encoding.

### Comment Style

```powershell
# Use comments to explain "why", not "what"
# We retry because M.E.Doc occasionally has transient network issues
$retryCount = 3
```

### Comments - International Standard

**MANDATORY:** All code comments must be in English. This project is developed for international audiences and requires universal code clarity.

#### Why English Only?

- **International Collaboration:** Contributors from different countries work on this codebase
- **Industry Standards:** Enterprise PowerShell code uses English-only comments
- **Tool Compatibility:** Automated analysis tools, AI agents, and code search assume English
- **Maintainability:** Future contributors (human and AI) must understand code intent

#### Comment Requirements

**DO:**

```powershell
# Skip entries before checkpoint time to avoid duplicate notifications
if ($SinceTime -and $timestamp -le $SinceTime) {
    continue
}

# Parse timestamp using strict format matching
# Format: dd.MM.yyyy H:mm:ss (e.g., 25.09.2025 4:01:28)
if ($line -match '^(\d{2}\.\d{2}\.\d{4}\s+\d{1,2}:\d{2}:\d{2})\s+(.+)$') {
    # Process line
}
```

**DON'T:**

```powershell
# ❌ Ukrainian comments (not allowed)
# Пропускаємо записи до часу контрольної точки
if ($SinceTime -and $timestamp -le $SinceTime) {
    continue
}

# ❌ Mixed languages (not allowed)
# Skip записи перед контрольной точкой
if ($SinceTime -and $timestamp -le $SinceTime) {
    continue
}

# ❌ No comments (not allowed for complex logic)
if ($SinceTime -and $timestamp -le $SinceTime) {
    continue
}
```

#### Comment Format Standards

1. **Start with capital letter after `#` and space**

   ```powershell
   # Correct: Capital letter
   # Correct with hyphen - explanation continues

   # incorrect: no capital letter at start
   #incorrect: no space after hash
   ```

2. **Explain intent, not implementation**

   ```powershell
   # ✅ Good: Explains WHY
   # Retry up to 3 times because Telegram API occasionally times out
   $maxRetries = 3

   # ❌ Bad: Just repeats code
   # Set maxRetries to 3
   $maxRetries = 3
   ```

3. **One space after `#`, before comment text**

   ```powershell
   # Correct format
   #IncorrectFormat
   #  ExtraSpaces
   ```

#### Comment Types

**Block Comments** (explain complex sections):

```powershell
# Phase 1: Search from end to find latest update operation
# We search backwards for efficiency since we only need the most recent
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    # Process line
}
```

**Inline Comments** (explain non-obvious code):

```powershell
$timestamp = [DateTime]::ParseExact($matches[1], 'dd.MM.yyyy H:mm:ss', $null)  # Parse Ukrainian date format
```

**Section Comments** (divide logical sections):

```powershell
# Verify M.E.Doc logs directory exists
if (-not (Test-Path $Config.MedocLogsPath)) {
    # Handle error
}

# Get last run time from checkpoint file
if (Test-Path $Config.LastRunFile) {
    # Load checkpoint
}
```

#### AI Agent Comment Validation

Before committing generated code, agents should verify:

```powershell
# Checklist for AI agents generating code:
# ✓ All comments are in English
# ✓ Each comment starts with capital letter
# ✓ One space after # and before text
# ✓ Comments explain WHY, not WHAT
# ✓ No Ukrainian, Russian, or other non-English characters
# ✓ Complex logic has explanatory comments
# ✓ No redundant comments that just repeat code
```

#### Pre-commit Comment Audit

Before submitting code, search for non-English comments:

```powershell
# Check for Cyrillic characters in comments (Ukrainian/Russian)
Get-ChildItem -Path lib, tests, utils -Filter *.ps1 -Recurse | ForEach-Object {
    $content = Get-Content $_ -Raw
    if ($content -match '#.*[А-Яа-яіїєґЁ]') {
        Write-Host "⚠️ Found non-English comment in: $_"
    }
}

# Check for comments without capital letter
Get-ChildItem -Path lib, tests, utils -Filter *.ps1 -Recurse | ForEach-Object {
    $lines = Get-Content $_
    $lines | ForEach-Object -Begin { $lineNum = 0 } -Process {
        $lineNum++
        if ($_ -match '^\s*#\s+[a-z]') {
            Write-Host "⚠️ Lowercase comment at $($_.FullPath):$lineNum"
        }
    }
}
```

## Testing Instructions

### Running Tests

**All Tests:**

```powershell
./tests/Run-Tests.ps1
```

**Specific Test File:**

```powershell
Invoke-Pester -Path tests/MedocUpdateCheck.Tests.ps1 -PassThru
```

**Single Test by Pattern:**

```powershell
Invoke-Pester -Path tests/MedocUpdateCheck.Tests.ps1 `
  -FullyQualifiedName "*should detect successful update*"
```

### Test Coverage

**Current Status:** Run `./tests/Run-Tests.ps1` to verify test coverage (output shows "Tests Passed: X")

Breakdown by category:

- **Unit Tests:** Message formatting, checkpoint operations, log parsing, encoding, error handling
- **Integration Tests:** Dual-log validation, configuration validation, module exports, Invoke-MedocUpdateCheck workflows

### Test Data & Encoding

All test data files in `tests/test-data/` are **Windows-1251 encoded** (required for M.E.Doc Cyrillic log support).

**Dual-Log Test Structure:**

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

**If modifying test data:**

1. Create files with proper Windows-1251 encoding using PowerShell:

   ```powershell
   $encoding = [System.Text.Encoding]::GetEncoding(1251)
   $text = "Your content here"
   [System.IO.File]::WriteAllBytes($Path, $encoding.GetBytes($text))
   ```

2. Include both Planner.log and update_*.log for functional tests
3. Ensure Cyrillic characters are properly encoded
4. Re-run tests to verify: `./tests/Run-Tests.ps1`

### Test Assertions

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

### Test Artifact Cleanup (AfterAll)

Test suites automatically clean up temporary checkpoint files after all tests complete, regardless of pass/fail/skip outcome.

**Why cleanup matters:**

- ✅ Prevents accumulation of temporary files in test-data directory
- ✅ Working directory stays clean after test runs
- ✅ Allows repeated test runs without artifact pollution
- ✅ Best practice for professional test suites

**Implementation:**

The `AfterAll` block in `tests/MedocUpdateCheck.Tests.ps1` automatically removes:

- All `checkpoint-*.txt` files generated during test execution
- Recursively from all test-data subdirectories
- Preserves actual test fixtures (`Planner.log`, `update_*.log` files)

**When adding new tests:**

If your test creates temporary files:

1. Use unique filenames with `[guid]::NewGuid()` to avoid conflicts
2. Rely on `AfterAll` for cleanup, OR
3. Use try/finally for immediate cleanup if the file is critical

**Example (relying on AfterAll):**

```powershell
It "Should handle custom checkpoint path" {
    $tempCheckpoint = Join-Path $testDataDir ("checkpoint-test-{0}.txt" -f ([guid]::NewGuid()))

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

### Using Enums in Tests

The MedocEventId enum is defined in the module for centralized event ID management. To use enum values in tests, follow this pattern:

#### Step 1: Import Module at Compile Time

At the very top of the test file (before any other code), add the `using module` directive:

```powershell
# Import module at compile time to make enum types available
using module "..\lib\MedocUpdateCheck.psm1"
```

This makes the `MedocEventId` enum available throughout the test file.

#### Step 2: Reference Enum Values Directly in Tests

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

#### Step 3: Available Enum Values

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

**Why Use Enums Instead of Hardcoding Numbers?**

- **Type Safety**: PowerShell validates enum member names at compile time
- **Maintainability**: If event ID values change, all tests automatically use the new values
- **Documentation**: Enum names self-document what each ID represents
- **Prevents Errors**: No risk of typos with hardcoded numbers (e.g., 1002 instead of 1001)

## Markdown Linting Guidelines

This project uses GitHub Actions markdown linting. Common issues and fixes:

### MD022: Heading Spacing

**Issue:** Missing blank line before heading

**Auto-fix:** Add blank line before every `##`, `###`, etc.

### MD031: Code Fence Language

**Issue:** Fenced code block missing language identifier

**Auto-fix:** Always include language after backticks:

- `powershell` for PowerShell
- `bash` for shell scripts
- `markdown` for markdown examples
- `json` for JSON files
- `yaml` for YAML files
- `text` if truly language-agnostic

### MD032: List Spacing

**Issue:** Missing blank line before list

**Auto-fix:** Add blank line before any ordered or unordered list.

### MD040: Fenced Code Language

**Issue:** Code fence missing language (stricter version of MD031)

**Auto-fix:** Same as MD031 above.

## Project Structure

```text
medoc-update/
├── Run.ps1                          # Universal entry point (DO NOT EDIT per-server)
├── lib/
│   └── MedocUpdateCheck.psm1        # Core module with all business logic
├── configs/
│   └── Config.template.ps1          # Template with all configuration options documented
├── utils/
│   ├── Setup-Credentials.ps1        # Credential encryption helper
│   ├── Setup-ScheduledTask.ps1      # Task Scheduler automation helper
│   └── Validate-Scripts.ps1         # PowerShell syntax validator
├── tests/
│   ├── Run-Tests.ps1                # Test runner
│   ├── MedocUpdateCheck.Tests.ps1   # Pester test cases
│   ├── test-data/                   # Dual-log test data (Windows-1251 encoded)
│   │   ├── dual-log-success/        # All 3 success flags present
│   │   ├── dual-log-no-update/      # No update entries
│   │   ├── dual-log-missing-updatelog/  # Update triggered, log missing
│   │   ├── dual-log-missing-flag1/  # Missing infrastructure flag
│   │   ├── dual-log-missing-flag2/  # Missing service restart flag
│   │   ├── dual-log-missing-flag3/  # Missing version confirmation flag
│   │   ├── dual-log-wrong-version/  # Version mismatch
│   │   └── update_2025-10-23.cleaned.log  # Sanitized production log
├── .github/
│   └── workflows/
│       └── tests.yml                # GitHub Actions CI/CD (9.5/10 rating)
├── AGENTS.md                        # This file - for AI agents
├── CLAUDE.md                        # Symlink to AGENTS.md (for Claude Code)
├── README.md                        # Human-focused project overview
├── CONTRIBUTING.md                  # Human contribution guidelines
├── SECURITY.md                      # Security best practices
├── TESTING.md                       # Human-focused testing guide
├── CODE_OF_CONDUCT.md               # Community guidelines
├── LICENSE                          # Apache 2.0 license
├── NOTICE                           # Attribution
└── .markdownlint.json               # Markdown linting config (uses defaults)
```

### Directory-Specific Notes

**`lib/`** - Core business logic

- All reusable functions go here
- Imported by `Run.ps1` and tests
- Functions must be idempotent
- No direct server-specific logic

**`configs/`** - Per-server customization

- One config file per monitored server
- Start with `Config.template.ps1` as base
- Store server names, credentials, Telegram tokens
- Never commit real credentials

**`utils/`** - Development and deployment utilities

- Setup-Credentials.ps1: Encrypt and manage credentials securely with CMS (self-signed certificate)
- Setup-ScheduledTask.ps1: Automate Task Scheduler setup with PowerShell 7+
- Validate-Scripts.ps1: Validate all PowerShell scripts for syntax errors

**`tests/`** - Automated testing

- Comprehensive tests covering core functions (unit and integration tests)
- Test data in Windows-1251 encoding
- Mock functions for Event Log and Telegram
- Run via GitHub Actions and locally
- Verify test count with: `./tests/Run-Tests.ps1`

**`.github/workflows/`** - CI/CD Pipeline

- Runs on Windows (multi-version PowerShell)
- Tests + code quality checks
- Markdown linting
- Test artifact uploads

## Exit Code Semantics for Operators

The `Invoke-MedocUpdateCheck` function returns a structured object with an `Outcome` property, which maps to exit codes via `Get-ExitCodeForOutcome`:

**Exit Code Mapping:**

- **0** — Normal completion (Success or NoUpdate)
- **1** — Error (configuration, I/O, Telegram issues)
- **2** — UpdateFailed (validation failure)

### For Agents: When Modifying Return Values

When changing `Invoke-MedocUpdateCheck` behavior or adding new outcome types:

1. **Update the Outcome values** in the outcome switch statement inside `Invoke-MedocUpdateCheck`
2. **Update Get-ExitCodeForOutcome** switch statement if adding new outcomes
3. **Update return object** to ensure EventId is correctly mapped from Outcome
4. **Update documentation** in DEPLOYMENT.md and README.md
5. **Add unit tests** for new exit code mappings in tests/MedocUpdateCheck.Tests.ps1
6. **Verify the mapping is stable** — external tooling may depend on it

### Example: Outcome → Exit Code → Operator Alert

```powershell
# In your code:
$result = Invoke-MedocUpdateCheck -Config $config
$exitCode = Get-ExitCodeForOutcome -Outcome $result.Outcome
exit $exitCode

# In Task Scheduler:
# Alert on exit code 1 (errors needing attention)
# Alert on exit code 2 (update validation failures - critical)
# Exit code 0 is expected for routine operations
```

## Common Pitfalls & Solutions

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

# To fix test file encoding:
iconv -f UTF-8 -t WINDOWS-1251 sample-log.txt
```

### Pitfall 4: Event Log Access on macOS/Linux

**Problem:**

```powershell
# This warns on non-Windows systems
Write-EventLogEntry -Message "Test"
# WARNING: Could not write to Event Log
```

**Expected Behavior:** Warnings are normal and expected on non-Windows. Tests continue normally. This is not an error.

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

## Git Workflow for Agents

### Branch Strategy

**main** - Production-ready code

- All tests passing
- Code reviewed
- Ready to deploy to servers

All changes go through **feature** or **fix** branches with PR-based workflow. No develop branch.

### Making Changes

1. **Create feature or fix branch** from `main`:

```powershell
git checkout main
git pull origin main
git checkout -b feature/your-feature-name
# OR
git checkout -b fix/your-bug-description
```

1. **Make changes** and test locally:

```powershell
./tests/Run-Tests.ps1
```

1. **Commit with meaningful message:**

```text
Add feature description

- What was changed
- Why it was changed
- Any breaking changes or warnings
```

1. **Push and open PR:**

```powershell
git push origin feature/your-feature-name
```

1. **GitHub Actions runs automatically:**

- Tests run on Windows (PowerShell 7+ - latest)
- Code quality checks
- Markdown linting
- Results appear in PR checks tab

1. **All tests must pass before merge:**

- All tests passing (verify with: `./tests/Run-Tests.ps1`)
- No PSScriptAnalyzer issues
- Markdown validation passing
- No merge conflicts

### Commit Message Format

Recommended format:

```text
[Type] Brief description

Longer explanation of changes if needed.

- Specific change 1
- Specific change 2
```

**Types:**

- `feat:` New feature or enhancement
- `fix:` Bug fix
- `test:` Test additions or fixes
- `docs:` Documentation changes
- `refactor:` Code restructuring without behavior change
- `chore:` Build, dependencies, tooling

## Security Considerations

### ⚠️ PII & Sensitive Data Warning - CRITICAL FOR CODE GENERATION

**Before committing ANY code, examples, or documentation:**

**Never include:**

- Real server names or hostnames
- Infrastructure provider names or abbreviations
- Real IP addresses, domain names, or network paths
- Email addresses (except generic examples like `user@example.com`)
- Real API keys, tokens, or credentials
- Real chat IDs or user identifiers
- Organizational structure details (office locations, departments, names)

**Always use instead:**

- Generic server names: `MEDOC-SRV01`, `MY-MEDOC-SERVER`, `TARGET-SERVER`
- Placeholder format: `YOUR_SERVER_NAME`, `EXAMPLE-SERVER`, `HOSTNAME_HERE`
- Generic examples: `192.168.0.x`, `user@example.com`, `123456:ABC...` (obviously fake)

**Pre-Commit Checklist:**

- [ ] No real server names in code or examples
- [ ] No IP addresses or domain names
- [ ] No email patterns beyond generic examples
- [ ] All server examples use generic names (MEDOC-SRV*, MY-*, etc.)
- [ ] Config templates use `YOUR_VALUE_HERE` placeholders
- [ ] No real tokens, keys, or credentials in examples

---

### Credentials & Secrets (SYSTEM User Compatible)

**IMPORTANT:** This project uses CMS (Cryptographic Message Syntax) encryption with self-signed LocalMachine certificate for credentials compatible with Task Scheduler running as SYSTEM user.

**Never commit:**

- Telegram bot tokens (plain text)
- Chat IDs (plain text)
- Server names (credentials, but ServerName can be auto-detected)
- API keys
- Domain credentials
- Usernames or email addresses

**Instead:**

- Use `utils/Setup-Credentials.ps1` to encrypt credentials securely
- Credentials stored as encrypted CMS message: `$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms`
- Encrypted with self-signed certificate in LocalMachine\My store (readable by SYSTEM user)
- Certificate: 5-year validity, NonExportable RSA-2048 key
- Config files load credentials using `utils/Get-TelegramCredentials.ps1`
- Document in `Config.template.ps1` as placeholders only
- Use GitHub Secrets for CI/CD

**Certificate Validation for Upgrades:**

When `Setup-Credentials.ps1` runs, it validates existing certificates meet CMS requirements:

- **Check 1: Certificate Expiration**
  - If expired or expiring < 30 days: regenerate new certificate
  - 5-year validity ensures manageable rotation cycle

- **Check 2: Private Key Accessibility**
  - If private key not accessible: regenerate
  - Required for decryption with `Unprotect-CmsMessage`

- **Check 3: Document Encryption EKU (1.3.6.1.4.1.311.80.1)**
  - CMS requires Extended Key Usage: Document Encryption
  - Old certificates from earlier releases may lack this
  - If missing: regenerate with `-Type DocumentEncryptionCert`

- **Check 4: KeyEncipherment Key Usage**
  - CMS requires both DataEncipherment AND KeyEncipherment
  - Old certificates may only have DataEncipherment
  - If missing: regenerate with both usages

**Why Validation Matters:**

Old certificates generated without proper CMS requirements will cause `Protect-CmsMessage` to fail at runtime with: "The certificate is not valid for encryption." The validation detects this silently before encryption and automatically regenerates the certificate.

**Hybrid ServerName Handling:**

- Auto-detect from `$env:MEDOC_SERVER_NAME` if set, else fall back to `$env:COMPUTERNAME`
- Allow explicit override in config: `$serverName = "MY_SERVER_NAME"`
- Never hardcode server names in code

### Code Security

- **No eval or dynamic code execution** without validation
- **Always use strict mode:** `Set-StrictMode -Version Latest`
- **Validate inputs:** Check file paths, server names, message content
- **Error messages:** Don't expose full paths or sensitive info in error logs
- **Dependencies:** Only use built-in PowerShell modules (no external NuGet packages)

### Testing Security

- Test Event Log writing but mock credentials
- Test Telegram sending but use mock bot tokens
- Test file operations with test data, not real logs
- GitHub Actions runs in isolated Windows environment

See [SECURITY.md](SECURITY.md) for full security guidelines.

## Agent Interaction Guidelines

### What Agents Should Ask Before Acting

**ALWAYS ask user permission before:**

- Installing modules locally (`Install-Module` on user's system)
- Modifying configuration files with real server names
- Creating credentials or secrets
- Running destructive operations (delete, reset)
- Making changes to `Run.ps1` (should stay universal)

### What Agents Can Do Automatically

**No need to ask for:**

- Adding functions to `lib/MedocUpdateCheck.psm1`
- Creating new test files in `tests/`
- Adding documentation files
- Creating feature branches
- Running `./tests/Run-Tests.ps1` to validate work
- Fixing markdown linting issues in docs
- Refactoring code (if tests still pass)

### What Agents Should Report

**Always inform user about:**

- Test results (passing/failing count)
- Markdown linting issues found
- Breaking changes to existing functions
- Security concerns in proposed changes
- Dependencies that need installation (ask permission)
- Changes that affect deployment or configuration

## Documentation Maintenance Guidelines

**CRITICAL:** Avoid creating "stale" documentation that requires manual updates for each file. This project follows a single-source-of-truth approach.

### Never Hardcode (Always Reference Instead)

**❌ DON'T:**

```markdown
**Version:** 1.0
**Last Updated:** October 2025
**Author:** John Doe
**License:** Apache 2.0
**Timestamp:** 2025-10-27
```

**✅ DO:**

```markdown
**Authors:** See [README.md](README.md#authors) for list of authors
**License:** See [LICENSE](LICENSE) file for details
**Note:** For release versions, check git tags: `git tag -l`
```

### Why This Matters

1. **Single Source of Truth**
   - Authors listed only in README.md
   - License terms only in LICENSE file
   - Versions only in git tags
   - No duplication = no sync issues

2. **Zero Maintenance Burden**
   - No manual updates needed when authors change
   - No stale dates or versions
   - License updates happen in one place
   - Git history handles timestamps

3. **Always Accurate**
   - Git commit shows actual update time
   - Git tags show actual releases
   - README.md is source of author info
   - LICENSE file is source of legal terms

### Best Practices for Documentation

**✅ Reference External Sources:**

```markdown
# Correct approach - reference, don't copy
**License:** See [LICENSE](LICENSE) file for details
**Authors:** See [README.md](README.md#authors) for contributors
**Version:** Check git tags with `git describe --tags`
**Last Modified:** See `git log <filename>` for history
```

**❌ Avoid Copying Information:**

```markdown
# Wrong approach - creates maintenance burden
**License:** Apache License 2.0, granted under terms...
**Authors:** John Doe, Jane Smith, Bob Jones
**Version:** 2.1.4 (updated 2025-10-27)
**Last Modified:** Yesterday at 3:45 PM
```

### Markdown Link Format

Always use markdown links to point to actual sources:

```markdown
- [README.md](README.md#authors) - for author information
- [LICENSE](LICENSE) - for license details
- [SECURITY.md](SECURITY.md) - for security procedures
- [CONTRIBUTING.md](CONTRIBUTING.md) - for contribution guidelines
```

### Table of Responsibility

| Information | Location | Update Method |
|---|---|---|
| Authors/Contributors | README.md | Edit file directly |
| License Terms | LICENSE file | Edit file directly |
| Release Versions | Git tags | `git tag -a vX.Y.Z` |
| Last Updated | Git history | Automatic via commits |
| Code Examples | Documentation files | Edit markdown directly |
| Markdown Style | .markdownlint.json | Config file |

### Avoiding Hardcoded Values in Documentation

When documenting numeric or dynamic values (test counts, file sizes, line counts, version numbers), **provide commands to obtain them** instead of hardcoding the values. This prevents documentation from becoming stale.

**❌ DON'T (Hardcoded Values - Will Become Stale):**

```markdown
- **Test Count:** 74 tests passing
- **Module Size:** 265+ lines
- **Pester Version:** 5.7.1
- **Total Files:** 42 files
- **Checkpoint Size:** ~2KB per checkpoint
```

**✅ DO (Provide Commands to Obtain Values):**

```markdown
- **Test Count:** Run `./tests/Run-Tests.ps1` to verify test coverage (output shows "Tests Passed: X")
- **Module Size:** Check with `(Get-Content ./lib/MedocUpdateCheck.psm1 | Measure-Object -Line).Lines`
- **Pester Version:** Check with `Import-Module Pester -PassThru | Select-Object Version`
- **Total Files:** List with `Get-ChildItem -Recurse -File | Measure-Object | Select-Object Count`
- **Checkpoint Size:** Check with `Get-Item $checkpointPath | Select-Object -ExpandProperty Length`
```

**Why This Matters:**

1. **No Stale Documentation**
   - Values update automatically as code changes
   - No manual edits needed when metrics change
   - Users always see accurate information

2. **Educational Value**
   - Developers and AI agents learn how to measure metrics
   - Commands are reusable for troubleshooting
   - Demonstrates diagnostic techniques

3. **Transparency**
   - Shows exactly how values are calculated
   - Builds confidence in documentation accuracy
   - Enables independent verification

**When to Hardcode:**

Only hardcode values in these cases:

- **Historical examples:** "In version 1.0, we had 45 tests" (marked as historical)
- **Fixed constants:** "Event ID 1000 is reserved for success" (unchanging by design)
- **Design requirements:** "Requires PowerShell 7.0 or later" (architectural constraint)
- **Configuration templates:** `$BotToken = "YOUR_BOT_TOKEN_HERE"` (placeholder for user input)

### Example: Proper Documentation with Dynamic Values

```markdown
## Test Coverage

The test suite includes unit and integration tests:

```powershell
# Check current test count
./tests/Run-Tests.ps1
```

**Current Status:**

- Run the test command above to see total tests passing
- Breakdown: Unit tests (file parsing, encoding, error handling), Integration tests (dual-log validation, configuration validation)
- All tests passing indicates the module is ready for deployment

This approach keeps documentation accurate without manual updates.

---

## Documentation Work Guidelines for AI Agents

### Before Writing/Modifying Documentation

#### Critical Workflow

Always follow this workflow to maintain quality and avoid duplication

#### 1. Search Existing Documentation First

Before proposing or writing ANY documentation:

```powershell
# Search for existing content
grep -r "YourTopicHere" *.md

# Examples:
grep -r "Event Log" *.md
grep -r "ServerName" *.md
grep -r "Windows-1251" *.md
grep -r "encoding" *.md
```

If content exists, reference it instead of duplicating it.

#### 2. Identify Authoritative Source

When content exists in multiple places, identify which file is authoritative:

| Topic | Authoritative Source | Policy |
|-------|----------------------|--------|
| Event Log Queries | TESTING.md | Other files link only |
| ServerName Configuration | SECURITY.md | Other files link only |
| Windows-1251 Encoding | SECURITY.md | Other files link only |
| Glossary Terms | README.md | Use consistently everywhere |
| Code Examples | TESTING.md | Link from other docs |
| Deployment Steps | DEPLOYMENT.md | Reference from others |

#### 3. Prefer References Over Duplication

**DON'T:**

```markdown
# In README.md
Get-WinEvent ...filter...
# Then again in TESTING.md
Get-WinEvent ...filter...  # Same code!
```

**DO:**

```markdown
# In README.md
For detailed queries, see [TESTING.md - Event Log Query Examples](TESTING.md#event-log-query-examples)

# In TESTING.md (authoritative location)
## Event Log Query Examples
(single comprehensive location)
```

### Proposing Documentation Improvements

If you identify documentation issues during work:

#### 1. Diagnose the Problem

- Is there duplication? (20+ identical lines)
- Is information scattered? (Same topic in 3+ files)
- Is content inconsistent? (Different versions of same info)
- Are links broken? (References to non-existent files)
- Is clarity poor? (Terms undefined, examples missing)

#### 2. Propose Solutions

Format for proposing improvements:

```markdown
## Proposed Improvement: [Topic Name]

**Problem:** [What's wrong]
**Locations:** [Which files affected]
**Current Impact:** [Why this matters]

**Proposed Solution:**
- Create single authoritative section in [FILE.md]
- Update references in [other files]
- Estimated effort: [X hours]

**Example:**
[Show before/after]
```

#### 3. Implement With User Approval

- Present analysis to user
- Get approval before implementing
- Execute systematically
- Verify all tests pass after changes
- Check markdown linting passes

### Quality Standards for Documentation Work

#### Pre-Commit Documentation Checklist

Before submitting ANY documentation changes (additions, modifications, or fixes):

**Search & Duplication Check (CRITICAL):**

- [ ] `grep -r "YourTopic" *.md` — Search for existing content
- [ ] Identify if topic is already documented elsewhere
- [ ] If found, reference it instead of duplicating
- [ ] Search for duplicates of THIS new content after writing
- [ ] Consolidate similar content if found scattered across files

**Consistency & Accuracy Check:**

- [ ] Verify content matches the actual codebase (check code examples, versions)
- [ ] **CRITICAL: Use function/section names, NOT line numbers** (see examples below)
- [ ] Verify content matches actual test behavior (run tests to confirm)
- [ ] Check all references to other files/sections are correct
- [ ] Ensure terminology matches project glossary/standards
- [ ] Verify no hardcoded values that will become stale (use commands instead)
- [ ] Check all links are valid and point to correct sections
- [ ] Ensure glossary terms used consistently throughout

**Technical Quality Check:**

- [ ] Verify markdown linting passes (`npx markdownlint-cli2 *.md`)
- [ ] Check for duplicate headings (MD024)
- [ ] Verify proper heading hierarchy (MD025/MD026)
- [ ] Ensure blank lines before lists (MD032)
- [ ] Confirm fenced code blocks have language identifiers (MD031/MD040)
- [ ] No orphaned references (links to non-existent sections)
- [ ] Update Table of Contents if section structure changed

**Strategic Distribution Check:**

- [ ] Identify the audience (users vs developers vs AI agents)
- [ ] Place content in the right document for that audience
- [ ] Add cross-references in related docs (don't duplicate, reference)
- [ ] Verify related documentation links back (if needed)

**Examples from This Project:**

✅ Exit codes documented in:

- TESTING.md (what cleanup does - user perspective)
- AGENTS.md (how cleanup works - developer perspective)
- DEPLOYMENT.md (operator alerting strategy)
- Code comments (self-documents implementation)

✅ No duplication: each file has unique perspective, links to others

❌ Wrong approach: copying the same explanation to all files

### Line Number References - AVOID (Fragile)

Documentation must NOT reference code by line number. Line numbers change whenever code is edited, making references stale and misleading.

**DON'T** (Fragile - will break on edits):

```markdown
See lib/MedocUpdateCheck.psm1 (lines 21-52) for the enum definition.
Uses .NET EventLog class (lib/MedocUpdateCheck.psm1:195-212).
Update the outcome mapping (line ~804 in module).
TESTING.md lines 217-226 show the quick reference.
```

**DO** (Stable - survives code edits):

```markdown
See the `MedocEventId` enum definition in lib/MedocUpdateCheck.psm1.
Uses .NET EventLog class in the `Write-EventLogEntry` function.
Update the outcome switch statement in `Invoke-MedocUpdateCheck`.
See the "Event ID Quick Reference" section in TESTING.md.
```

**Why:**

- Line numbers change frequently with code edits
- Future maintainers see stale, incorrect references
- Developers might make changes in wrong locations
- Function/section names remain stable

**Exception:** Line numbers in code *examples* within backticks (e.g., showing error output) are acceptable.

#### Consistency Checks

- [ ] Search for duplicates of this content
- [ ] Identify authoritative location
- [ ] Remove duplication, add references instead
- [ ] Check all links are valid
- [ ] Verify markdown linting passes
- [ ] Ensure glossary terms used consistently
- [ ] Update Table of Contents if changed
- [ ] Test all cross-references work

#### Single Source of Truth Maintenance

When updating documentation:

1. Update authoritative source first
2. Check which files reference it
3. Verify all references still work
4. Search for any duplicate content to remove
5. Ensure consistency across files

#### Examples of Consolidation

##### Pattern A: Scattered Examples

- Before: Same code in 4 files
- After: Code in TESTING.md, links in others
- Files Modified: README.md, SECURITY.md, DEPLOYMENT.md

##### Pattern B: Multiple Explanations

- Before: ServerName explained 3 different ways
- After: Single explanation in SECURITY.md, references elsewhere
- Files Modified: README.md, CONTRIBUTING.md

##### Pattern C: Information Scattered

- Before: Encoding tips across multiple files
- After: Complete guide in SECURITY.md with links
- Files Modified: AGENTS.md, TESTING.md, CONTRIBUTING.md

### Documentation Maintenance Tasks

Common documentation improvements to suggest:

1. **Consolidate Similar Content**
   - Effort: 2-4 hours
   - Value: Reduce maintenance burden
   - Example: Event Log queries (done)

2. **Clarify Conflicting Information**
   - Effort: 1-2 hours
   - Value: Improve user understanding
   - Example: ServerName config (done)

3. **Add Missing Context**
   - Effort: 1-2 hours
   - Value: Prevent user confusion
   - Example: Windows-1251 encoding (done)

4. **Create Reference Guides**
   - Effort: 1-2 hours
   - Value: Professional, easy lookup
   - Example: Glossary (done)

### Examples of Good Proposals

**Good:** "I notice Event Log examples appear in 4 files with different -MaxEvents values (10, 20, 50, 1). Should I consolidate to TESTING.md with clear use cases for each scenario?"

**Good:** "ServerName config is explained 3 different ways in README, SECURITY, and CONTRIBUTING. Users don't know which approach to use. Should I create comprehensive guide in SECURITY.md with clear scenarios?"

**Good:** "Windows-1251 encoding is mentioned 7 times across docs but never fully explained. Should I create a section in SECURITY.md covering why, when, how, troubleshooting, and configuration?"

**Bad:** "Let me add Event Log examples to every file that mentions them."

**Bad:** "I'll copy-paste ServerName explanation into all three documents for redundancy."

**Bad:** "I found a typo, I'll fix it locally without checking if it appears elsewhere."

---

## Recommendations for Ongoing Maintenance

### Documentation Maintenance

#### When adding new Event IDs

1. Update documentation files (SECURITY.md is authoritative):
   - SECURITY.md - Add to "Event ID Reference" table + "Monitoring Strategy" section
   - TESTING.md - Add to "Event ID Quick Reference", link to SECURITY.md for full details
   - README.md - Update "Event ID Ranges" section, link to SECURITY.md for complete list
   - DEPLOYMENT.md - Update if deployment-specific Event IDs are relevant

2. For each Event ID provide:
   - Level classification (Info/Error based on severity)
   - Description of what triggered it
   - Troubleshooting steps
   - Root cause analysis

3. Verify Event ID consistency across all files by running:

    ```powershell
    # Search for Event IDs across all documentation
    grep -r "1010\|1011\|1012\|1013" *.md
    ```

4. Update code and tests if new Event ID requires new logic

#### When updating test coverage

1. Do NOT hardcode test counts in documentation
2. Instead, provide command to obtain current count (example):

    ```markdown
    Run `./tests/Run-Tests.ps1` to verify test coverage
    ```

3. Update TESTING.md with new test categories/breakdown if applicable
4. Update test data in `tests/test-data/` with Windows-1251 encoding

---

#### When adding dynamic value documentation

1. **NEVER hardcode:** Test counts, line counts, version numbers, file sizes, metric values
2. **ALWAYS provide:** Command to obtain the value
3. **Document:** Why the metric matters and how it's calculated
4. Examples:
   - ❌ "Module has 265 lines" → ✅ "Check with: `(Get-Content ./lib/MedocUpdateCheck.psm1 | Measure-Object -Line).Lines`"
   - ❌ "74 tests passing" → ✅ "Run `./tests/Run-Tests.ps1` to verify coverage"
   - ❌ "Latest: v11.02.186" → ✅ "Check with: `git describe --tags`"

#### When modifying documentation structure

1. Maintain markdown link consistency:
   - Use `[text](path#anchor)` format
   - Verify links point to correct sections
   - Update cross-references in multiple files if section moves

2. Update table of contents if adding new sections:
   - Keep hierarchy consistent
   - Ensure proper markdown spacing (blank lines before/after headings)
   - Run through markdown linter before submitting

3. When consolidating examples:
   - Designate one file as authoritative (e.g., TESTING.md for Event Log queries)
   - Update other files to reference authoritative source
   - Document why consolidation improves maintenance

### Code Maintenance

#### Validation before committing

```powershell
# Step 1: Syntax validation (REQUIRED)
pwsh ./utils/Validate-Scripts.ps1

# Step 2: Run tests
./tests/Run-Tests.ps1

# Step 3: Code quality check (optional)
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    pwsh -NoProfile -Command {
        Import-Module PSScriptAnalyzer -Force
        Invoke-ScriptAnalyzer -Path './lib' -Recurse
    }
}
```

#### When adding new functions

1. Place in `lib/MedocUpdateCheck.psm1`
2. Use `Verb-Noun` naming convention
3. Add to module exports: `Export-ModuleMember -Function`
4. Include comment-based help: `<#.SYNOPSIS...#>`
5. Add unit tests in `tests/MedocUpdateCheck.Tests.ps1`
6. Document in appropriate markdown file

#### Event ID Management (Centralized Enum)

**Important:** All Event IDs are defined in a centralized `enum MedocEventId` in `lib/MedocUpdateCheck.psm1`. This enum serves as the single source of truth for all Event IDs across the project.

**Enum structure by range:**

```powershell
enum MedocEventId {
    # 1000-1099: Normal flow (operational, not errors)
    Success = 1000                   # ✅ All flags confirmed
    NoUpdate = 1001                  # ℹ️ No update detected

    # 1100-1199: Configuration errors
    ConfigMissingKey = 1100          # ❌ Missing required config key
    ConfigInvalidValue = 1101        # ❌ Invalid config value

    # 1200-1299: Environment/filesystem errors
    PlannerLogMissing = 1200         # ❌ Planner.log not found
    UpdateLogMissing = 1201          # ❌ update_*.log not found
    LogsDirectoryMissing = 1202      # ❌ M.E.Doc logs directory not found
    CheckpointDirCreationFailed = 1203  # ❌ Checkpoint directory creation failed
    EncodingError = 1204             # ❌ Encoding error reading logs

    # 1300-1399: Update/flag validation failures
    Flag1Failed = 1300               # ❌ Infrastructure validation failed
    Flag2Failed = 1301               # ❌ Service restart failed
    Flag3Failed = 1302               # ❌ Version confirmation failed
    MultipleFlagsFailed = 1303       # ❌ Multiple flags missing

    # 1400-1499: Notification/communication errors
    TelegramAPIError = 1400          # ❌ Telegram API error
    TelegramSendError = 1401         # ❌ Telegram send failed

    # 1500-1599: Checkpoint/state persistence errors
    CheckpointWriteError = 1500      # ❌ Checkpoint write failed

    # 1900+: Unexpected/general errors
    GeneralError = 1900              # ❌ Unexpected error
}
```

**When modifying Event ID logic:**

1. **Add new Event IDs to enum first** in `lib/MedocUpdateCheck.psm1` (in the `MedocEventId` enum definition)
   - Choose correct range based on error category
   - Add descriptive comment
   - Use PascalCase naming (e.g., `CredentialsEncryptionFailed`)

2. **Use enum value in code** instead of hardcoded numbers:

   ```powershell
   # ✅ CORRECT: Use enum
   Write-EventLogEntry -Message $msg -EventType Error -EventId ([MedocEventId]::PlannerLogMissing)

   # ❌ WRONG: Hardcoded numbers
   Write-EventLogEntry -Message $msg -EventType Error -EventId 1200
   ```

3. **Update Test-UpdateOperationSuccess** if function returns new Status/ErrorId combinations
   - Add Status and ErrorId to return object
   - Example: `@{ Status = "Failed"; ErrorId = [MedocEventId]::PlannerLogMissing }`

4. **Document in SECURITY.md** - Update Event ID reference tables:
   - Add row to appropriate range section (1100-1199, 1200-1299, etc.)
   - Include ID, Level, Scenario, Meaning, Action
   - Example: `| **1200** | Error | ❌ Planner.log Missing | Planner.log not found... | Verify MedocLogsPath... |`

5. **Update README.md** - Ensure Event ID range list is complete:
   - Add range to bullet list if new range introduced
   - Link to SECURITY.md for full reference

6. **Add test case in `tests/MedocUpdateCheck.Tests.ps1`**
   - Test that function returns correct Status/ErrorId
   - Test that Write-EventLogEntry is called with correct EventId
   - Example:

     ```powershell
     It "Should log with EventId 1200 when Planner.log missing" {
         # Mock setup, invoke, verify EventId
     }
     ```

7. **Run validation:**

   ```powershell
   pwsh ./utils/Validate-Scripts.ps1    # Syntax check
   ./tests/Run-Tests.ps1                 # All tests must pass (105+ tests)
   ```

8. **Verify consistency** across all files:
   - Search for any hardcoded Event ID numbers and replace with enum references
   - Verify no duplicate Event IDs
   - Check documentation reflects all implemented IDs

### Preventing Documentation Drift

#### Single Source of Truth Rules

1. **Authors**: Reference README.md#authors, never copy to other files
2. **License**: Reference LICENSE file, never copy legal text
3. **Versions**: Use `git tag` commands, never hardcode version numbers
4. **Event IDs**: Use TESTING.md as authoritative table, other files reference or extract
5. **Event Log Queries**: Keep comprehensive examples in TESTING.md only
6. **Test Information**: Use command-based references, not hardcoded counts

#### Cross-File Consistency Checks

Before committing documentation changes, verify:

```powershell
# 1. Event ID consistency check
Write-Host "Checking Event ID consistency..."
$eventIds = @(1000, 1001, 1100, 1101, 1200, 1201, 1202, 1203, 1204, 1300, 1301, 1302, 1303, 1400, 1401, 1500, 1900)
foreach ($id in $eventIds) {
    $readmeMatches = (Get-Content README.md | Select-String $id | Measure-Object).Count
    $testingMatches = (Get-Content TESTING.md | Select-String $id | Measure-Object).Count
    $securityMatches = (Get-Content SECURITY.md | Select-String $id | Measure-Object).Count
    Write-Host "Event ID $id - README: $readmeMatches, TESTING: $testingMatches, SECURITY: $securityMatches"
}

# 2. Markdown link validation
Write-Host "Checking markdown links..."
$links = Get-Content *.md | Select-String '\[.*\]\(.*\)' -AllMatches | ForEach-Object { $_.Matches }
foreach ($link in $links) {
    Write-Host "Link found: $($link.Value)"
}

# 3. Hardcoded value check
Write-Host "Checking for hardcoded metrics..."
Get-Content *.md | Select-String '(74 tests|265 lines|test count|total tests)' -IgnoreCase
```

### Quality Gates Before Merge

**All of the following must pass before committing:**

- ✅ All tests passing (`./tests/Run-Tests.ps1` - run to verify current count)
- ✅ Syntax validation passing (`pwsh ./utils/Validate-Scripts.ps1`)
- ✅ Markdown linting passing (GitHub Actions check)
- ✅ No hardcoded dynamic values in documentation
- ✅ Event ID consistency across all files
- ✅ Cross-references verified and working
- ✅ Code comments explain "why", not "what"
- ✅ Windows-1251 encoding used for test data files

---

## Quick Reference for AI Agents

### Do's

- Keep functions in `lib/MedocUpdateCheck.psm1`
- Use `Verb-Noun` naming convention
- Test data files are Windows-1251 encoded
- Use `$script:` scope in Pester BeforeAll blocks
- Document why, not what
- Run `./tests/Run-Tests.ps1` to validate work
- Check markdown before submitting changes
- Follow branch strategy (feature/fix branches from main)
- Ask user before installing modules locally
- Use `utils/Setup-Credentials.ps1` for credential encryption
- Implement hybrid ServerName detection (env var or fallback)
- Ensure all credential handling works with SYSTEM user
- **Add `using module "..\lib\MedocUpdateCheck.psm1"` at top of test files to access enum types**
- **Use enum values directly in tests: `[MedocEventId]::Success`** (not hardcoded numbers)

### Don'ts

- Don't use `[datetime]$parameter = $null` (type conversion error)
- Don't commit real credentials or secrets (use Setup-Credentials.ps1)
- Don't edit `Run.ps1` for per-server customization
- Don't assume UTF-8 for M.E.Doc logs
- Don't use deprecated Pester syntax (`-HaveKey`)
- Don't skip markdown linting before submitting
- Don't commit test data in UTF-8 format
- Don't forget blank lines before headings/lists in markdown
- Don't auto-install modules without user permission
- Don't store plain text credentials in config files
- Don't hardcode ServerName in code or configs
- Don't use user-key encryption for credentials (won't work with SYSTEM user)

## Links & Resources

- **CONTRIBUTING.md** - Human contribution guidelines
- **TESTING.md** - Comprehensive testing guide with coverage analysis
- **SECURITY.md** - Security best practices and considerations
- **LICENSE** - See file for full license terms (Apache 2.0)
- **README.md** - Project overview and quick start

---

**For Agents:** All 20+ major AI coding platforms compatible

**Maintained by:** See [README.md](README.md#authors) for list of authors and contributors

**License:** See [LICENSE](LICENSE) file for details

**Note:** For the latest version, check the git commit history
