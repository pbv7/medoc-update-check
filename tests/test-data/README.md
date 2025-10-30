# M.E.Doc Update Check - Test Data Directory

This directory contains test log files for validating the M.E.Doc Update Check functionality. All files use **Windows-1251 encoding** (CP1251) to support Cyrillic characters in M.E.Doc logs.

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

Verify encoding of existing files:

```powershell
# Check encoding (should output "Windows-1251" or "CP1251")
file -i test-file.log

# Or in PowerShell:
[System.Text.Encoding]::GetEncoding(1251).EncodingName
```

---

## Test Scenarios

### Dual-Log Validation Tests

M.E.Doc update detection uses a two-log strategy. Each test scenario contains both logs:

#### 1. `dual-log-success/`

**Status:** ✅ Update completed successfully

**Files:**

- `Planner.log` - Contains update trigger entry
- `update_YYYY-MM-DD.log` - Contains all 3 success flags

**Success Criteria (all required):**

1. **Infrastructure Validation**
   - Pattern: `IsProcessCheckPassed DI: True, AI: True`
   - Confirms .NET infrastructure validation passed

2. **Service Restart Success**
   - Pattern: `сервіс ZvitGrp запущен у нормальному` (service started normally)
   - Confirms ZvitGrp service restarted successfully

3. **Version Confirmation**
   - Pattern: `новая версія - {TARGET_VERSION}` (new version - number)
   - Confirms system reports expected version

**Use case:** Validate successful update detection and message formatting

---

#### 2. `dual-log-no-update/`

**Status:** ❌ No update activity detected

**Files:**

- `Planner.log` - No update trigger entries
- `update_*.log` - Not present or empty

**Trigger Detection:**

- Searches for pattern: `Завантаження оновлення ezvit.X.X.X-X.X.X.upd`
- If pattern not found → No update detected

**Use case:** Validate that the function correctly identifies when no updates occurred

---

#### 3. `dual-log-missing-updatelog/`

**Status:** ⚠️ Update triggered but detailed log missing

**Files:**

- `Planner.log` - Contains update trigger entry
- `update_*.log` - Missing or not found

**Failure Reason:**

- Phase 1 detected update initiation
- Phase 2 failed: Log file not found at expected location
- Update marked as FAILED (suspicious: update started but no detailed log)

**Use case:** Validate that missing log files are detected as update failures

---

#### 4. `dual-log-missing-flag1/`

**Status:** ⚠️ Update completed but missing infrastructure validation flag

**Files:**

- `Planner.log` - Contains update trigger
- `update_*.log` - Contains flags 2 & 3, but missing flag 1

**Missing Flag:**

- Pattern not found: `IsProcessCheckPassed DI: True, AI: True`
- Indicates .NET infrastructure validation failed or not logged

**Use case:** Validate detection of infrastructure validation failures

---

#### 5. `dual-log-missing-flag2/`

**Status:** ⚠️ Update completed but missing service restart flag

**Files:**

- `Planner.log` - Contains update trigger
- `update_*.log` - Contains flags 1 & 3, but missing flag 2

**Missing Flag:**

- Pattern not found: `сервіс ZvitGrp запущен у нормальному`
- Indicates ZvitGrp service failed to restart or not logged

**Use case:** Validate detection of service restart failures

---

#### 6. `dual-log-missing-flag3/`

**Status:** ⚠️ Update completed but missing version confirmation flag

**Files:**

- `Planner.log` - Contains update trigger
- `update_*.log` - Contains flags 1 & 2, but missing flag 3

**Missing Flag:**

- Pattern not found: `новая версія - {TARGET_VERSION}`
- Indicates system failed to confirm version or update failed

**Use case:** Validate detection of version confirmation failures

---

#### 7. `dual-log-wrong-version/`

**Status:** ⚠️ Update completed but with unexpected version number

**Files:**

- `Planner.log` - Trigger shows expected version: `ezvit.11.02.186-11.02.187.upd`
- `update_*.log` - Contains all 3 flags but version doesn't match
  - Pattern: `новая версія - 185` (should be 187)

**Failure Reason:**

- All flags present (update completed)
- Version mismatch detected (security concern: unexpected version installed)
- Update marked as FAILED

**Use case:** Validate version mismatch detection and security alerts

---

#### 8. `dual-log-multiple-flags-failed/`

**Status:** ⚠️ Update completed but multiple success flags missing

**Files:**

- `Planner.log` - Contains update trigger entry
- `update_*.log` - Contains only flag 3, but missing flags 1 & 2

**Missing Flags:**

- Pattern not found: `IsProcessCheckPassed DI: True, AI: True` (Flag 1)
- Pattern not found: `сервіс ZvitGrp запущен у нормальному` (Flag 2)
- Pattern found: `новая версія - {TARGET_VERSION}` (Flag 3 present)

**Failure Reason:**

- Two or more critical success flags are missing
- Indicates multiple components failed (infrastructure AND service restart)
- Update marked as FAILED with ErrorId: `MultipleFlagsFailed` (Event ID 1303)

**Event ID:** `[MedocEventId]::MultipleFlagsFailed` (1303)

**Use case:** Validate that multiple simultaneous flag failures are correctly
identified and reported with the dedicated `MultipleFlagsFailed` error code
(as opposed to reporting individual `Flag1Failed` or `Flag2Failed`)

---

### Test Coverage Summary

**8 scenarios tested:**

1. ✅ Success - All 3 flags present
2. ✅ No update - No update entries in logs
3. ✅ Missing update log - Update triggered but log file missing
4. ✅ Missing Flag 1 - Infrastructure validation failed
5. ✅ Missing Flag 2 - Service restart failed
6. ✅ Missing Flag 3 - Version confirmation failed
7. ✅ Wrong version - All flags present but version mismatch
8. ✅ Multiple flags failed - Flags 1 & 2 missing simultaneously

**EncodingError (EventId 1204):** Tested via direct function calls in unit tests rather than scenario files. The `Test-UpdateOperationSuccess` function includes try/catch error handling for encoding issues during log file reading. This is exercised in the validation workflow but not via dedicated test data file scenario due to PowerShell's transparent encoding handling.

---

### Timestamp Formats

Test data demonstrates correct timestamp parsing for both log types:

#### Planner.log Format

- **Format:** `DD.MM.YYYY H:MM:SS`
- **Example:** `25.10.2025 4:01:28`
- **Regex:** `\d{2}\.\d{2}\.\d{4}` (4-digit year)

#### update_*.log Format

- **Format:** `DD.MM.YY H:MM:SS.MMM`
- **Example:** `25.10.25 10:30:15.100`
- **Regex:** `\d{2}\.\d{2}\.\d{2}` (2-digit year)
- **Note:** Milliseconds are included in logs but ignored during parsing

---

## File Structure Example

Each scenario directory follows this pattern:

```text
dual-log-success/
├── Planner.log              # Planning/scheduler log (Windows-1251 encoded)
├── update_2025-10-25.log    # Execution log (Windows-1251 encoded)
```

### Planner.log Content Example

```text
25.10.2025 4:01:28 Завантаження оновлення ezvit.11.02.185-11.02.186.upd
25.10.2025 4:05:12 Оновлення завершено
```

### update_YYYY-MM-DD.log Content Example

```text
25.10.25 10:30:15.100 00000001 INFO    IsProcessCheckPassed DI: True, AI: True
25.10.25 10:45:32.250 00000002 INFO    сервіс ZvitGrp запущен у нормальному режимі
25.10.25 11:00:00.000 00000003 INFO    новая версія - 186
```

---

## Using Test Data in Tests

### Pester Test Example

```powershell
Describe "Dual-log validation" {
    BeforeEach {
        $script:logsDir = Join-Path $PSScriptRoot "test-data" "dual-log-success"
    }

    It "Should detect successful update" {
        $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
        $result.Status | Should -Be "Success"
    }
}
```

---

## Test Data Maintenance

### Creating New Scenarios

When adding new test scenarios:

1. **Create scenario directory** with descriptive name (e.g., `dual-log-missing-flag2`)

2. **Create Planner.log** with Windows-1251 encoding:
   - Include update trigger line if applicable
   - Use format: `DD.MM.YYYY H:MM:SS {message}`

3. **Create update_YYYY-MM-DD.log** with Windows-1251 encoding:
   - Use date from Planner.log entry
   - Include appropriate flags for scenario
   - Use format: `DD.MM.YY H:MM:SS.MMM {id} {level} {message}`

4. **Document in this README** explaining:
   - What the scenario tests
   - Success/failure criteria
   - Use case

5. **Add corresponding Pester test** in `tests/MedocUpdateCheck.Tests.ps1`

### Updating Existing Scenarios

When modifying test data:

1. Verify Windows-1251 encoding is maintained
2. Update README.md documentation if scenario behavior changes
3. Re-run tests to ensure all affected tests pass: `./tests/Run-Tests.ps1`
4. Document the change in git commit message

---

## Troubleshooting

### "Pattern not found" Errors

If tests fail with pattern matching errors:

1. **Check encoding:** Verify files are Windows-1251 encoded, not UTF-8
2. **Check Cyrillic characters:** Ensure special characters (і, ї, є, ґ) are correct
3. **Check line endings:** Use LF or CRLF consistently
4. **Verify patterns:** Compare against actual M.E.Doc logs

### Creating Test Files on macOS/Linux

```powershell
# PowerShell 7+ (cross-platform)
$encoding = [System.Text.Encoding]::GetEncoding(1251)
$content = "Test content"
[System.IO.File]::WriteAllBytes("/path/to/file.log", $encoding.GetBytes($content))
```

---

## Related Documentation

- [TESTING.md](../../TESTING.md) - Comprehensive testing guide
- [AGENTS.md](../../AGENTS.md) - Timestamp format details and validation strategy
- [tests/MedocUpdateCheck.Tests.ps1](../MedocUpdateCheck.Tests.ps1) - Test cases using this data
