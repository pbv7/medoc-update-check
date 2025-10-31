# Code Standards & Conventions for Agents

Comprehensive guide for PowerShell code style, conventions, and language features to use when
working on the M.E.Doc Update Check project.

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

## PowerShell 7+ Removed Features: NEVER Use These

**CRITICAL:** PowerShell 7 removed many legacy cmdlets and modules. When generating code,
ALWAYS avoid these deprecated features.

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

**Project Implementation:** ✅ Uses .NET EventLog class in `Write-EventLogEntry` function

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

**Project Implementation:** ✅ Uses native Task Scheduler cmdlets

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

**Approved Verbs:** Get, Test, Invoke, Write, New, Set, Remove, Find, Select, Out, Format,
Group, Measure, Compare, Copy, Join, Split, Export, Import, ConvertTo, ConvertFrom, Update,
Add, Disable, Enable, Save, Show, Stop, Start, Suspend, Restart, Resume.

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
- Functions: `Test-ServerName`, `Test-MedocLogsPath`, `Test-BotToken`, `Test-ChatId`,
  `Test-EncodingCodePage`, `Test-CheckpointPath`
- Each function returns standardized result object with `Valid`, `ErrorMessage`, optional
  `IsWarning` and `DefaultValue` properties

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

**Why:** PowerShell attempts type conversion before parameter binding. A `[datetime]` constraint
on `$null` raises error.

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

**Why:** M.E.Doc is a Ukrainian accounting software. Its Event Logs use Windows-1251 (CP1251)
encoding for Cyrillic characters. Tests must match this encoding.

## Comment Standards

### English-Only Requirement

**MANDATORY:** All code comments must be in English. This project is developed for
international audiences and requires universal code clarity.

#### Why English Only?

- **International Collaboration:** Contributors from different countries work on this codebase
- **Industry Standards:** Enterprise PowerShell code uses English-only comments
- **Tool Compatibility:** Automated analysis tools, AI agents, and code search assume English
- **Maintainability:** Future contributors (human and AI) must understand code intent

### Comment Format Standards

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

### Comment Types

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

### AI Agent Comment Validation

Before committing generated code, verify:

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

### Pre-commit Comment Audit

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

## Universal Code: System Variables Instead of Hardcoded Paths

**Critical for portability:** Windows installations may have custom drive layouts or security
policies that change standard paths.

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

## Timestamp Parsing: Different Regex for Different Log Files

**CRITICAL:** M.E.Doc uses two log files with **different timestamp formats**. Using the
wrong regex pattern will cause timestamp parsing to fail.

### Why Different Formats?

- **Planner.log**: Planning/scheduler log (4-digit year: DD.MM.YYYY)
- **update_*.log**: Execution/process log (2-digit year: DD.MM.YY)

Different purposes = Different formats. This is not a bug; it's architectural.

### Correct Regex Patterns

**Planner.log:**

```powershell
# MUST match 4-digit year format
if ($line -match '^(\d{2}\.\d{2}\.\d{4})\s+(\d{1,2}:\d{2}:\d{2})\s+(.+)$') {
    # Parse with format: 'dd.MM.yyyy H:mm:ss'
}
```

**update_*.log:**

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

**update_*.log:**
`23.10.25 10:30:15.100 00000001 INFO    IsProcessCheckPassed DI: True, AI: True`

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

## Validation Checklist for Agents

Before committing code changes, verify:

- ✓ PowerShell 7+ is being used
- ✓ All scripts have valid syntax (run `pwsh ./utils/Validate-Scripts.ps1`)
- ✓ All tests pass (run `./tests/Run-Tests.ps1`)
- ✓ Code quality passes (PSScriptAnalyzer - optional)
- ✓ All scripts include `#Requires -Version 7.0`
- ✓ No hardcoded paths (use `$env:` variables)
- ✓ No removed PS7+ cmdlets (EventLog, WMI, PSScheduledJob)
- ✓ All comments in English
- ✓ Comments explain WHY, not WHAT
- ✓ Function names follow Verb-Noun convention
- ✓ No untyped datetime parameters with null defaults
- ✓ Windows-1251 encoding for test data

---

**For more information:**

- See [AGENTS-TESTING.md](AGENTS-TESTING.md) for testing standards and enum usage
- See [AGENTS-SECURITY.md](AGENTS-SECURITY.md) for security guidelines and PII concerns
- See [AGENTS-TOOLS-AND-WORKFLOW.md](AGENTS-TOOLS-AND-WORKFLOW.md) for tool selection
