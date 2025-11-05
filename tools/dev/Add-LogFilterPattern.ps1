#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Add regex patterns interactively to cleanup-patterns.txt and apply them iteratively.

.DESCRIPTION
This utility provides an interactive workflow for developers to:
1. Define and test a regex pattern
2. Apply it to source logs for immediate preview
3. Review lines that would be removed
4. Save the pattern to cleanup-patterns.txt for future use
5. Repeat for next pattern

Useful for:
- Developing and testing new cleanup patterns
- Iteratively reducing log file size
- Documenting which patterns remove which log entries
- Building a curated pattern library

WORKFLOW:
1. Provide a regex pattern to match lines to exclude
2. Pattern is applied to all source logs
3. Display how many lines would be removed
4. Append pattern to cleanup-patterns.txt
5. Overwrite output with filtered version
6. Append removed lines to excluded archive

.PARAMETER Pattern
Regex pattern to apply for filtering (required).
Lines matching this pattern will be marked for removal.

.PARAMETER SourceDir
Directory containing original M.E.Doc update logs (update_*.log format).
Default: "logs/source" (relative to script directory)

.PARAMETER CleanedDir
Directory where cleaned log files are maintained.
Default: "logs/cleaned" (relative to script directory)

.PARAMETER ExcludedDir
Directory where excluded lines are archived.
Default: "logs/excluded" (relative to script directory)

.PARAMETER PatternsFile
File where patterns are accumulated (one per line).
Default: "patterns/cleanup-patterns.txt" (relative to script directory)

.EXAMPLE
.\Add-LogFilterPattern.ps1 -Pattern "INFO\s+Створення копії файлу:"
# Add pattern to remove "INFO Creating copy file:" messages

.EXAMPLE
.\Add-LogFilterPattern.ps1 -Pattern "MEDOCSRV\\TEMP\\[0-9a-f]{8}"
# Add pattern to remove temporary file paths

.EXAMPLE
.\Add-LogFilterPattern.ps1 -Pattern "[^\s]+\\[^\s]+\.[a-zA-Z0-9]+$"
# Add pattern to remove file path lines

.NOTES
PATTERN DEVELOPMENT WORKFLOW:
1. Start with a simple literal string: "text to remove"
2. Test with this script to see matches
3. Refine regex if needed
4. Once satisfied, pattern is saved automatically

ENCODING CRITICAL:
- Input logs must be Windows-1251 encoded (M.E.Doc standard)
- Patterns file UTF-8 (for cross-platform editing)
- Output logs use Windows-1251 to maintain compatibility

REGEX BASICS FOR M.E.Doc LOGS:
  \s        - Any whitespace (space, tab, newline)
  \d        - Any digit [0-9]
  [a-z]     - Character class (a through z)
  [0-9a-f]  - Hex digits
  +         - One or more of previous
  *         - Zero or more of previous
  ?         - Optional (0 or 1 of previous)
  .         - Any character (escape with \. for literal dot)
  |         - OR operator
  ^         - Start of line
  $         - End of line
  (...)     - Grouping
  {n,m}     - Repeat n to m times

CYRILLIC PATTERNS:
PowerShell regex supports Unicode, so you can use Cyrillic directly:
  Розпаковано файл:
  Створення копії файлу:
  Оновлення файлу:
  INFO\s+.+
  ERROR\s+.+

TESTING PATTERNS:
Before using this script, test your pattern:
  "Sample log line" -match "your regex pattern"
  # Returns $true if pattern matches, $false otherwise

For complex patterns, use conditional operators:
  $line -match "^ERROR|^FAIL" # Match lines starting with ERROR or FAIL

DIRECTORY STRUCTURE:
  tools/dev/
  ├── Invoke-LogFiltering.ps1 (batch apply all patterns)
  ├── Add-LogFilterPattern.ps1 (this script - add patterns iteratively)
  ├── patterns/
  │   └── cleanup-patterns.txt (accumulated patterns)
  └── logs/
      ├── source/ (input logs from production)
      ├── cleaned/ (progressively filtered logs)
      └── excluded/ (archive of removed lines)

WORKFLOW WITH BOTH SCRIPTS:
A. Exploratory pattern development:
   1. Use Add-LogFilterPattern.ps1 multiple times
   2. Test and refine patterns interactively
   3. Review results after each pattern
   4. Save working patterns to cleanup-patterns.txt

B. Batch application on new logs:
   1. Place new raw logs in logs/source/
   2. Run Invoke-LogFiltering.ps1
   3. Applies all patterns from cleanup-patterns.txt at once
   4. Outputs cleaned logs and excluded archive

C. Starting from scratch:
   1. Place raw logs in logs/source/
   2. Use Add-LogFilterPattern.ps1 to develop patterns
   3. Once satisfied, use Invoke-LogFiltering.ps1 next time

EXPECTED OUTPUT:
  Pattern saved to: patterns/cleanup-patterns.txt
  Processed 5 files
  Total lines kept: 45230
  Total lines excluded: 12540

TROUBLESHOOTING:
- If no logs found: Ensure logs/source/ contains update_*.log files
- If pattern syntax error: Test regex in PowerShell first
- If too many lines removed: Pattern too broad - refine it
- If too few lines removed: Pattern too narrow - make it more general

SEE ALSO:
- Invoke-LogFiltering.ps1 - Batch apply all patterns at once
- tools/dev/README.md - Complete documentation and examples
- patterns/cleanup-patterns.txt - Pattern library with explanations

#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern,

    [string]$SourceDir = (Join-Path $PSScriptRoot "logs/source"),
    [string]$CleanedDir = (Join-Path $PSScriptRoot "logs/cleaned"),
    [string]$ExcludedDir = (Join-Path $PSScriptRoot "logs/excluded"),
    [string]$PatternsFile = (Join-Path $PSScriptRoot "patterns/cleanup-patterns.txt")
)

# Register Windows code pages for cross-platform PowerShell 7 support
# On non-Windows systems, explicitly load the encoding provider
if (-not ([System.Text.Encoding]::Encodings.Any({ $_.Name -eq "windows-1251" }))) {
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
}

# Windows-1251 encoding for M.E.Doc compatibility
$encoding = [System.Text.Encoding]::GetEncoding(1251)

# Validate regex pattern syntax
try {
    [regex]::new($Pattern) | Out-Null
}
catch {
    Write-Error "The provided regex pattern '$Pattern' is invalid. Please check the syntax. Error: $($_.Exception.Message)" -ErrorAction Stop
}

# Validate inputs
if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory not found: $SourceDir" -ErrorAction Stop
}

# Create directories if they don't exist
New-Item -ItemType Directory -Path $CleanedDir -Force | Out-Null
New-Item -ItemType Directory -Path $ExcludedDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $PatternsFile) -Force | Out-Null

# Initialize cleaned directory from source if first run
$cleanedFiles = @(Get-ChildItem $CleanedDir -Filter "update_*.log" -ErrorAction SilentlyContinue)
$sourceFiles = @(Get-ChildItem $SourceDir -Filter "update_*.log")

if ($cleanedFiles.Count -eq 0 -and $sourceFiles.Count -gt 0) {
    Write-Host "First run detected: Copying source files to cleaned directory..." -ForegroundColor Yellow
    $sourceFiles | ForEach-Object {
        Copy-Item $_.FullName -Destination (Join-Path $CleanedDir $_.Name) -Force
    }
}

# Process files with the pattern
Write-Host "Processing with pattern: $Pattern" -ForegroundColor Cyan
Write-Host ""

$files = Get-ChildItem $CleanedDir -Filter "update_*.log"
$totalKept = 0
$totalExcluded = 0

foreach ($file in $files) {
    # Use temporary file for filtered content
    $tempFile = New-TemporaryFile
    $excludedPath = Join-Path $ExcludedDir $file.Name
    $linesKeptInFile = 0
    $linesExcludedInFile = 0

    try {
        # Use StreamWriter for efficient buffered I/O instead of Add-Content (one open/close per line)
        $writerKept = [System.IO.StreamWriter]::new($tempFile.FullName, $false, $encoding)
        $writerExcluded = [System.IO.StreamWriter]::new($excludedPath, $true, $encoding)

        try {
            # Stream-process file line-by-line without loading entire file into memory
            foreach ($line in [System.IO.File]::ReadLines($file.FullName, $encoding)) {
                if ($line -match $Pattern) {
                    $writerExcluded.WriteLine($line)
                    $linesExcludedInFile++
                } else {
                    $writerKept.WriteLine($line)
                    $linesKeptInFile++
                }
            }
        }
        finally {
            $writerKept.Dispose()
            $writerExcluded.Dispose()
        }

        # Replace original file with filtered version
        Move-Item -Path $tempFile.FullName -Destination $file.FullName -Force
    }
    finally {
        # Ensure temporary file is cleaned up
        if (Test-Path $tempFile.FullName) {
            Remove-Item $tempFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    $totalKept += $linesKeptInFile
    $totalExcluded += $linesExcludedInFile
}

# Append pattern to file
$Pattern | Out-File $PatternsFile -Encoding utf8 -Append

Write-Host "Processed $($files.Count) files" -ForegroundColor Green
Write-Host "Total lines kept: $totalKept" -ForegroundColor Green
Write-Host "Total lines excluded: $totalExcluded" -ForegroundColor Green
Write-Host "Pattern saved to: $PatternsFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Pattern added successfully!" -ForegroundColor Green
