# M.E.Doc Update Check - Test Data Directory

This directory contains test log files for validating the M.E.Doc Update Check functionality.
All files use **Windows-1251 encoding** (CP1251) to support Cyrillic characters in M.E.Doc logs.

## Encoding Information

**Critical:** All test data files in this directory must be encoded in Windows-1251, not UTF-8.

### Why Windows-1251?

- M.E.Doc is a Ukrainian accounting software
- Event logs use Cyrillic characters (Ukrainian and Russian)
- Windows-1251 is the standard encoding for Windows Event Logs in Eastern Europe
- Tests must match production log encoding to ensure pattern matching works correctly

### Creating Test Data with Proper Encoding

When creating new test files, use PowerShell with Windows-1251 encoding:

```powershell
$encoding = [System.Text.Encoding]::GetEncoding(1251)
$content = "Your content with Cyrillic characters here"
[System.IO.File]::WriteAllBytes($path, $encoding.GetBytes($content))
```

### Checking File Encoding

Verify encoding of existing files.

On **Linux/macOS:**

```bash
# Option 1: Using file command (may report iso-8859-1 for Windows-1251 without BOM)
file --mime-encoding test-file.log

# Option 2: Using uchardet (more reliable for Windows-1251 detection)
uchardet test-file.log

# Option 3: Using enca (better support for legacy encodings)
enca test-file.log
```

**Note:** `file` uses heuristics and may not reliably detect Windows-1251 without BOM markers.
For accurate encoding detection, install `uchardet` or `enca`:

- **macOS:** `brew install uchardet` or `brew install enca`
- **Linux:** `sudo apt-get install uchardet` or `sudo apt-get install enca`

On **Windows or with PowerShell 7+** (cross-platform, verify content):

```powershell
# Read first 5 lines with Windows-1251 encoding
# Cyrillic characters should display correctly
Get-Content -Path test-file.log -Encoding ([System.Text.Encoding]::GetEncoding(1251)) -TotalCount 5
```

---

## Test Scenarios - 2-Marker System (Phase 1 v2.0)

M.E.Doc update detection uses a **2-marker validation system**:

### Core Concept

The system validates update success by checking for **2 critical markers** in the update log:

- **Marker V (Version):** Pattern `Версія програми - {TARGET_VERSION}` confirms version matches
- **Marker C (Completion):** Pattern `Завершення роботи, операція "Оновлення"` confirms operation finished

**Classification:**

- ✅ **SUCCESS:** Both markers V AND C present
- ❌ **FAILED:** Either marker V OR C missing (operation detected but incomplete)
- ℹ️ **NO UPDATE:** Planner.log contains no update trigger (no operation to evaluate)

---

### Test Scenarios

#### 1. `success-both-markers/`

**Status:** ✅ Update completed successfully

**Files:**

- `Planner.log` - Contains update trigger entry
- `update_2025-10-23.log` - Contains both V and C markers

**Markers Present:**

- **Marker V (Version):** `Версія програми - 186` ✓
- **Marker C (Completion):** `Завершення роботи, операція "Оновлення"` ✓

**Outcome:** SUCCESS (ErrorId=1000)

**Use case:** Validate successful update detection, marker extraction, version parsing, and Telegram message formatting for success cases

**Test Coverage:**

- Detects both markers present
- Extracts version information correctly
- Formats success message with version details and timestamps
- Verifies UpdateStartTime and UpdateEndTime extraction

---

#### 2. `failure-missing-version-marker/`

**Status:** ❌ Update failed - version marker missing

**Files:**

- `Planner.log` - Contains update trigger entry (`ezvit.11.02.185-11.02.186.upd`)
- `update_2025-10-23.log` - Contains completion marker but NOT version marker

**Markers Present:**

- **Marker V (Version):** MISSING ✗
- **Marker C (Completion):** `Завершення роботи, операція "Оновлення"` ✓

**Outcome:** FAILED (ErrorId=1302)

- OperationFound: true (because completion marker present)
- Success: false

**Use case:** Validate detection of incomplete updates where operation completed but version was not confirmed (indicates version mismatch or failed validation)

**Test Coverage:**

- Detects missing version marker
- Still recognizes operation block (completion marker present)
- Formats failure message with reason text
- Extracts version from Planner.log (independent of marker presence)

---

#### 3. `failure-missing-completion-marker/`

**Status:** ❌ Update failed - operation block incomplete

**Files:**

- `Planner.log` - Contains update trigger entry
- `update_2025-10-23.log` - Contains partial update log but NOT completion marker

**Markers Present:**

- **Marker V (Version):** May or may not be present
- **Marker C (Completion):** MISSING ✗

**Outcome:** FAILED (ErrorId=1302)

- OperationFound: false (because completion marker missing - cannot identify operation block)
- Success: false

**Use case:** Validate detection of interrupted/incomplete updates where the update
process started but did not finish (suspicious: update triggered but logs incomplete)

**Test Coverage:**

- Detects missing completion marker
- Correctly identifies operation as NOT found
- Distinguishes from "no update" case (operation WAS detected, just incomplete)
- Provides appropriate failure message

---

#### 4. `failure-no-update-detected/`

**Status:** ℹ️ No update detected in logs

**Files:**

- `Planner.log` - Contains NO update trigger entries (no `Завантаження оновлення ezvit.X.X.X-X.X.X.upd` pattern)
- No `update_*.log` file (not created because no update was triggered)

**Markers:** Neither marker found (no operation to evaluate)

**Outcome:** NO UPDATE (ErrorId=1001)

- Status: "NoUpdate"
- Success: false (not a failure, just no activity)

**Use case:** Validate distinction between "no update activity" and "update failed".
This is informational (not an error) and formats differently in Telegram messages
(ℹ️ emoji instead of ❌)

**Test Coverage:**

- Correctly distinguishes NO UPDATE from FAILED
- Formats informational message (not error message)
- Uses correct ErrorId (1001, not 1302)
- Checkpoint filtering returns NoUpdate when no updates found

---

#### 5. `failure-no-update-log/`

**Status:** ❌ Update log missing (update detected in Planner.log but update_*.log absent)

**Files:**

- `Planner.log` - Contains update trigger entry
- No `update_*.log` file (update log was not created or is missing)

**Outcome:** FAILED (ErrorId=1201 - UpdateLogMissing) when Planner.log shows an update
trigger. If Planner.log had no trigger, it would be treated as NO UPDATE (1001) instead.

**Use case:** Validate handling of missing update logs. If no update trigger in
Planner.log → NO UPDATE. If update trigger exists but log missing → suspicious scenario

**Test Coverage:**

- Handles gracefully when update log is missing
- Returns appropriate outcome based on Planner.log content (this fixture exercises the missing-log failure path)

---

### Test Coverage Summary

**5 scenarios tested:**

1. ✅ **Success** - Both markers present (V✓ C✓)
2. ❌ **Failed - Missing Version** - Completion without version confirmation (V✗ C✓)
3. ❌ **Failed - Missing Completion** - Incomplete operation (V✓/✗ C✗)
4. ℹ️ **No Update** - No update entries in logs (no Planner update trigger)
5. ❌ **No Update Log** - Update log file missing after Planner shows update trigger

**Comprehensive outcomes validated:**

- SUCCESS: 1000
- FAILED: 1302 (marker failure), 1201 (missing update log)
- NO UPDATE: 1001
- ENCODING ERROR: 1204 (tested via direct unit tests, not file-based scenarios)

---

## Search Strategy: Finding the Last Operation

The system uses a **backward search** strategy to find the most recent update operation:

1. **Start at end of update_*.log**
2. **Search backward** for completion marker: `Завершення роботи, операція "Оновлення"`
3. **If found:** Record end position
4. **Search backward** from that position for start marker: `Початок роботи, операція "Оновлення"`
5. **If found:** Extract operation block between start and end
6. **If NOT found:** Return FAILED (operation incomplete/aborted)

This strategy ensures:

- Only the **LAST operation** matters (logs may contain multiple updates)
- Faster search for large logs
- Handles multiple operations correctly

---

### Timestamp Formats

Test data demonstrates correct timestamp parsing for both log types:

#### Planner.log Format

- **Format:** `DD.MM.YYYY H:MM:SS`
- **Example:** `25.10.2025 4:01:28`
- **Regex:** `\d{2}\.\d{2}\.\d{4}` (4-digit year)
- **Content:** `Завантаження оновлення ezvit.11.02.185-11.02.186.upd`

#### update_YYYY-MM-DD.log Format

- **Format:** `DD.MM.YY H:MM:SS.MMM {id} {level} {message}`
- **Example:** `25.10.25 10:30:15.100 00000001 INFO Версія програми - 186`
- **Regex:** `\d{2}\.\d{2}\.\d{2}` (2-digit year)
- **Note:** Milliseconds are included in logs but ignored during parsing

---

## File Structure Examples

### success-both-markers/

```text
success-both-markers/
├── Planner.log              # Planning/scheduler log (Windows-1251 encoded)
├── update_2025-10-23.log    # Execution log with both markers (Windows-1251 encoded)
```

#### Planner.log Content Example

```text
15.10.2025 14:00:00 Сервис полный старт
23.10.2025 10:30:15 Завантаження оновлення ezvit.11.02.185-11.02.186.upd
25.10.2025 16:45:22 Сервис полный старт
```

#### update_2025-10-23.log Content Example

```text
23.10.25 10:30:15.257 00000001 INFO    Початок роботи, операція "Оновлення"
23.10.25 10:35:00.100 00000002 INFO    ... operation steps ...
23.10.25 10:48:37.585 00000003 INFO    Версія програми - 186
23.10.25 10:48:38.100 00000004 INFO    Завершення роботи, операція "Оновлення"
```

---

## Using Test Data in Tests

### Pester Test Example

```powershell
Describe "2-marker validation" {
    It "Should detect successful update with both markers" {
        $logsDir = Join-Path $PSScriptRoot "test-data" "success-both-markers"
        $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

        $result.Status | Should -Be "Success"
        $result.Success | Should -Be $true
        $result.MarkerVersionConfirm | Should -Be $true
        $result.MarkerCompletionMarker | Should -Be $true
    }

    It "Should detect failure when version marker missing" {
        $logsDir = Join-Path $PSScriptRoot "test-data" "failure-missing-version-marker"
        $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

        $result.Status | Should -Be "Failed"
        $result.MarkerVersionConfirm | Should -Be $false
        $result.MarkerCompletionMarker | Should -Be $true
    }
}
```

---

## Test Data Maintenance

### Creating New Scenarios

When adding new test scenarios:

1. **Create scenario directory** with descriptive name (e.g., `failure-no-update-log`)

2. **Create Planner.log** with Windows-1251 encoding:
   - Include update trigger line if applicable
   - Use format: `DD.MM.YYYY H:MM:SS {message}`
   - Use actual M.E.Doc event text (e.g., `Завантаження оновлення ezvit.X.X.X-X.X.X.upd`)

3. **Create update_YYYY-MM-DD.log** (if scenario requires):
   - Use date from Planner.log entry
   - Include appropriate markers for scenario (V, C, both, or neither)
   - Use format: `DD.MM.YY H:MM:SS.MMM {id} {level} {message}`
   - Use actual M.E.Doc event text

4. **Document in this README:**
   - What scenario tests
   - Markers present/missing
   - Expected outcome and ErrorId
   - Use case

5. **Add corresponding Pester test** in `tests/MedocUpdateCheck.Tests.ps1`:
   - Test marker detection
   - Test outcome (Success/Failed/NoUpdate)
   - Test message formatting
   - Test checkpoint filtering if applicable

### Updating Existing Scenarios

When modifying test data:

1. Verify Windows-1251 encoding is maintained
2. Update README.md documentation if scenario behavior changes
3. Re-run tests to ensure all affected tests pass
4. Document the change in git commit message

---

## Troubleshooting

### "Pattern not found" Errors

If tests fail with pattern matching errors:

1. **Check encoding:** Verify files are Windows-1251 encoded, not UTF-8

   ```powershell
   uchardet tests/test-data/*/Planner.log
   ```

2. **Check Cyrillic characters:** Ensure special characters (і, ї, є, ґ, о, у) are correct

3. **Check marker patterns:** Verify exact pattern matches:
   - Version marker: `Версія програми - {number}` (exact spacing/hyphen)
   - Completion marker: `Завершення роботи, операція "Оновлення"` (exact quotes)

4. **Check line endings:** Verify LF or CRLF consistency across files

5. **Compare against real M.E.Doc logs:** Validate patterns against actual production logs

### Creating Test Files on macOS/Linux

```powershell
# PowerShell 7+ (cross-platform)
$encoding = [System.Text.Encoding]::GetEncoding(1251)
$content = @"
23.10.2025 10:30:15 Завантаження оновлення ezvit.11.02.185-11.02.186.upd
"@
[System.IO.File]::WriteAllBytes("/path/to/Planner.log", $encoding.GetBytes($content))
```

---

## Related Documentation

- [TESTING.md](../../TESTING.md) - Comprehensive testing guide including 2-marker system
- [AGENTS.md](../../AGENTS.md) - 2-marker system explanation for AI agents
- [docs/analysis/implementation-plan-phase1.md](../../docs/analysis/implementation-plan-phase1.md) - Phase 1 refactoring details
- [tests/MedocUpdateCheck.Tests.ps1](../MedocUpdateCheck.Tests.ps1) - Test cases using this data (164 tests, including marker validation)
