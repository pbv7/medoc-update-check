# Developer Tools: M.E.Doc Log Filtering Utilities

Development utilities for reducing production M.E.Doc log file sizes by removing verbose,
repetitive, or non-update-relevant entries.

## Overview

These tools help developers analyze M.E.Doc server update logs more efficiently by:

- **Reducing file sizes** - Remove verbose framework/infrastructure logging
- **Focusing analysis** - Keep only lines relevant to update validation
- **Archiving exclusions** - Preserve removed lines for recovery if needed
- **Building patterns** - Iteratively develop and test cleanup patterns

## Quick Start

### 1. Interactive Pattern Development

Develop and test patterns one at a time:

```powershell
./Add-LogFilterPattern.ps1 -Pattern "INFO\s+Створення копії файлу:"
```

This:

- Tests the pattern against all source logs
- Shows how many lines would be removed
- Saves the pattern to `patterns/cleanup-patterns.txt`
- Updates cleaned logs and excluded archive

### 2. Batch Apply All Patterns

Apply all patterns from the library at once (optimized single-pass processing):

```powershell
./Invoke-LogFiltering.ps1
```

This:

- Copies source logs to cleaned directory
- Combines all patterns into single regex for efficient processing
- Processes each file once with all patterns applied
- Reports total lines kept/excluded
- Produces final cleaned logs

## Directory Structure

```text
tools/dev/
├── README.md (this file)
├── Invoke-LogFiltering.ps1 (batch apply all patterns)
├── Add-LogFilterPattern.ps1 (interactive pattern development)
├── patterns/
│   └── cleanup-patterns.txt (library of regex patterns)
└── logs/
    ├── source/ (input: raw logs from production)
    ├── cleaned/ (output: filtered logs)
    └── excluded/ (archive: lines that were removed)
```

## Workflow

### Scenario A: Analyzing a New Production Log

1. Place raw `update_*.log` files in `logs/source/`
2. Run batch processing:

   ```powershell
   ./Invoke-LogFiltering.ps1
   ```

3. Review cleaned logs in `logs/cleaned/`
4. If needed, recover removed lines from `logs/excluded/`

### Scenario B: Developing New Cleanup Patterns

1. Start with raw logs in `logs/source/`
2. Test patterns interactively:

   ```powershell
   ./Add-LogFilterPattern.ps1 -Pattern "pattern to test"
   ./Add-LogFilterPattern.ps1 -Pattern "another pattern"
   # Review results after each run
   ```

3. Once satisfied with patterns, use batch mode for next analysis:

   ```powershell
   ./Invoke-LogFiltering.ps1
   ```

### Scenario C: Refining Patterns on Existing Cleaned Logs

If you've already cleaned logs and want to add more patterns:

```powershell
# logs/cleaned/ directory retains previous filters
./Add-LogFilterPattern.ps1 -Pattern "new pattern"
./Add-LogFilterPattern.ps1 -Pattern "another pattern"
```

## Script Details

### Invoke-LogFiltering.ps1

Batch apply all patterns from the patterns library.

**Usage:**

```powershell
./Invoke-LogFiltering.ps1 [options]
```

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| SourceDir | logs/source | Directory with update_*.log files |
| OutputDir | logs/cleaned | Where to write cleaned logs |
| ExcludedDir | logs/excluded | Archive of removed lines |
| PatternsFile | patterns/cleanup-patterns.txt | Pattern library file |

**Example:**

```powershell
./Invoke-LogFiltering.ps1
# Uses all defaults (relative to script)

./Invoke-LogFiltering.ps1 -SourceDir "C:\prod-logs" -OutputDir "C:\analysis"
# Custom absolute paths
```

**Output:**

```text
Found 20 patterns to apply

Copying source files to output directory...
Copied 5 file(s)

[1/20] Applying: INFO\s+Створення копії файлу:
  Lines kept: 45230, excluded: 2100
[2/20] Applying: MEDOCSRV\\TEMP\\[0-9a-f]{8}
  Lines kept: 44890, excluded: 340
...
[20/20] Applying: \d+,[^,]+,\d+$
  Lines kept: 28450, excluded: 16440

✅ Done! All patterns applied.
  Cleaned logs: logs/cleaned
  Excluded lines: logs/excluded
```

### Add-LogFilterPattern.ps1

Add a single pattern interactively and apply it to logs. Displays a preview of excluded lines
to help review what will be removed. Automatically prevents duplicate patterns from being added
to the library.

**Usage:**

```powershell
./Add-LogFilterPattern.ps1 -Pattern "regex pattern"
```

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| Pattern | (required) | Regex pattern to apply |
| SourceDir | logs/source | Original logs |
| CleanedDir | logs/cleaned | Directory for in-place filtering. Populated from `SourceDir` on first run. |
| ExcludedDir | logs/excluded | Excluded lines archive |
| PatternsFile | patterns/cleanup-patterns.txt | Pattern library |
| SkipStats | $false | Skip per-pattern statistics and use single-pass processing for speed |

**Duplicate Prevention:**

The script automatically checks if a pattern already exists in the pattern library before
adding it. If you attempt to add a duplicate pattern, the script will:

- Display a warning that the pattern already exists
- Skip adding the duplicate
- Suggest editing the patterns file manually if needed

This prevents accumulation of duplicate entries in `patterns/cleanup-patterns.txt`.

**Example:**

```powershell
./Add-LogFilterPattern.ps1 -Pattern "Розпаковано файл:"
# Remove unpacking messages (shows detailed statistics)

./Add-LogFilterPattern.ps1 -Pattern "INFO\s+[A-Za-z0-9]"
# Remove info lines with alphanumeric

./Add-LogFilterPattern.ps1 -Pattern "new pattern" -SkipStats
# Add pattern and use fast single-pass processing

./Add-LogFilterPattern.ps1 -Pattern "[0-9a-f]{8}-[0-9a-f]{4}"
# Remove UUID patterns
```

**Output:**

In default mode (with detailed statistics):

```text
Processing with pattern: INFO\s+Створення копії файлу:

Processed 5 files
Applied 1 pattern with detailed statistics
Total lines kept: 45230
Total lines excluded: 2100

Preview of excluded lines (first 5 shown):
────────────────────────────────────────────────────────────────────────────────
INFO     Створення копії файлу: C:\path\to\file1.txt
INFO     Створення копії файлу: C:\path\to\file2.exe
INFO     Створення копії файлу: C:\MEDOCSRV\DATA\update.xml
INFO     Створення копії файлу: D:\backup\archive.zip
INFO     Створення копії файлу: C:\logs\system.log
... and 2095 more lines
────────────────────────────────────────────────────────────────────────────────

Pattern saved to: patterns/cleanup-patterns.txt

✅ Pattern added successfully!
```

With `-SkipStats` flag (single-pass, no preview):

```text
Processing with pattern: INFO\s+Створення копії файлу:

Processed 5 files
Applied 3 patterns in single pass
Total lines kept: 42100
Total lines excluded: 5230
Pattern saved to: patterns/cleanup-patterns.txt

✅ Pattern added successfully!
```

## Pattern Library

Located in `patterns/cleanup-patterns.txt`. Each line is a regex pattern applied
sequentially to remove verbose log entries.

### Example Patterns

```regex
# Unpack messages
Розпаковано файл:

# Copy file operations
INFO\s+Створення копії файлу:
INFO\s+Копія файлу .+ не створюється

# Update operations (verbose)
INFO\s+Оновлення файлу:
INFO\s+файл:

# File checks and validation
INFO\s+Файл [A-Z0-9]
INFO\s+Файл не перевіряється - виключено з переліку

# Directory/File operations
INFO\s+.+DirectoryOrFile : '[A-Z]:\\
INFO\s+.+File NOT found: '[A-Z]:\\

# Checksums and temp data
INFO\s+Вдало, контрольні суми співпадають

# UUID patterns
MEDOCSRV\\TEMP\\[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}

# File paths
INFO\s+([^\s]+\\)*[^\s]+\.[a-zA-Z0-9]+$

# Replacement directives
INFO\s+REPLACE:
```

### Pattern Syntax

Use standard PowerShell regex:

| Syntax | Meaning | Example |
|--------|---------|---------|
| `.` | Any character | `ERROR.+` |
| `\s` | Whitespace | `INFO\s+` |
| `\d` | Digit | `\d{4}` |
| `[a-z]` | Character class | `[a-z]+` |
| `[0-9a-f]` | Hex digit | `[0-9a-f]{8}` |
| `+` | One or more | `ERROR+` |
| `*` | Zero or more | `ERROR*` |
| `?` | Optional | `ERROR?` |
| `\|` | OR operator | `ERROR\|FAIL` or `(ERROR\|FAIL)` |
| `^` | Line start | `^ERROR` |
| `$` | Line end | `ERROR$` |
| `()` | Group | `(ERROR\|FAIL)` |
| `{n,m}` | Repeat | `\d{1,3}` |

### Testing Patterns

Before adding patterns, test them:

```powershell
# Simple test
"Sample log line" -match "pattern to test"
# Returns $true or $false

# With complex patterns
$line = "INFO     Creating copy file: C:\path\file.txt"
$line -match "INFO\s+Створення"
# Returns $true if pattern matches
```

## Encoding

**CRITICAL:** These tools handle M.E.Doc logs with specific encoding requirements:

- **Input logs:** Windows-1251 (M.E.Doc standard)
- **Pattern file:** UTF-8 (must be saved as UTF-8 for correct Cyrillic handling)
- **Output logs:** Windows-1251 (maintains compatibility with M.E.Doc)

The `patterns/cleanup-patterns.txt` file **must** be saved with UTF-8 encoding to
correctly handle Cyrillic characters. If you edit it manually with a text editor,
ensure your editor is configured to save the file as UTF-8. Use the
`Add-LogFilterPattern.ps1` script to add patterns if unsure about encoding.

## Performance Notes

### Invoke-LogFiltering.ps1 (Batch Tool)

Uses optimized **single-pass processing** by combining all patterns into a single regex:

- Each file is read and written only once, regardless of pattern count
- Significantly faster than sequential pattern application
- No per-pattern statistics (not needed for batch processing)

### Add-LogFilterPattern.ps1 (Interactive Tool)

**Default:** Shows detailed per-pattern statistics (developer-friendly)

- Useful for understanding pattern impact during development

**With `-SkipStats` flag:** Uses single-pass processing for faster testing

- Combines all patterns into single regex
- Useful when working with many accumulated patterns
- Useful for very large log files

### Performance factors

- Number of log files
- Size of each log file (in MB)
- Number of patterns
- Complexity of regex patterns

### Optimization tips

1. **Use Invoke-LogFiltering.ps1 for batch processing** - Optimized single-pass design
2. **Use -SkipStats in Add-LogFilterPattern.ps1 with many patterns** - For faster development cycles
3. **Reduce file size** - Move older logs to separate directory
4. **Simplify patterns** - Use more specific regex (fewer false matches)
5. **Reduce patterns** - Comment out unused patterns with `#`

## Troubleshooting

### No logs found

**Error:** "No update_*.log files found in logs/source/"

**Solution:** Place `update_*.log` files in the `logs/source/` directory

### Pattern syntax error

**Error:** "The regex pattern is not valid"

**Solution:** Test your pattern first:

```powershell
"test" -match "your pattern"
# Fix pattern syntax before using script
```

### Too many/few lines removed

**Error:** Pattern matched more/fewer lines than expected

**Solution:**

- **Too many:** Pattern too broad, refine it:

  ```powershell
  # Bad: Too broad
  "INFO"

  # Better: More specific
  "INFO\s+Створення копії"
  ```

- **Too few:** Pattern too narrow, generalize it:

  ```powershell
  # Bad: Too specific
  "INFO     File: C:\path\file123.txt"

  # Better: More general
  "INFO\s+File: [A-Za-z]:"
  ```

### Excluded lines are empty

**Cause:** Pattern didn't match any lines

**Solution:**

- Verify pattern is correct (test with PowerShell)
- Check encoding of source logs
- Verify log file contains expected content

## Workflow Recommendations

### Best Practices

1. **Start simple** - Begin with literal text matches before regex
2. **Test first** - Use PowerShell to test pattern before applying
3. **Save patterns** - Keep patterns in library for future use
4. **Archive exclusions** - Don't delete excluded lines immediately
5. **Review results** - Check cleaned logs to verify quality

### Pattern Development Checklist

- [ ] Pattern matches lines you want to remove
- [ ] Pattern doesn't accidentally remove important lines
- [ ] Pattern tested with `-match` operator first
- [ ] Regex syntax is valid PowerShell
- [ ] Pattern handles Cyrillic text correctly
- [ ] Pattern works across all log files

## Support

For script details and full documentation:

```powershell
Get-Help .\Invoke-LogFiltering.ps1 -Full
Get-Help .\Add-LogFilterPattern.ps1 -Full
```

For PowerShell regex help:

```powershell
Get-Help about_Regular_Expressions
```

## Notes

- These tools are **developer utilities** - not used in production scripts
- Logs are assumed to be from M.E.Doc update processes
- Windows-1251 encoding is non-negotiable for M.E.Doc compatibility
- Pattern development is iterative - don't worry about perfection on first run
