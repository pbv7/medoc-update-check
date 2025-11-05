#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Apply all patterns from cleanup-patterns.txt to M.E.Doc log files sequentially.

.DESCRIPTION
This utility applies a series of regex patterns stored in cleanup-patterns.txt
to M.E.Doc update log files, removing verbose/repetitive entries to reduce log
file size while preserving lines relevant for update analysis.

The tool processes all update_*.log files and produces:
- Cleaned logs (reduced size, pattern lines removed)
- Excluded lines archive (for recovery if needed)
- Progress output showing lines kept/excluded per pattern

This is especially useful for:
- Reducing production log sizes before analysis
- Removing verbose framework/infrastructure logging
- Extracting only update-relevant entries
- Archiving excluded lines for future reference

WORKFLOW:
1. Copy source logs to output directory
2. For each pattern in cleanup-patterns.txt:
   a. Read all lines from cleaned log files
   b. Lines matching pattern → moved to excluded archive
   c. Lines not matching pattern → kept in cleaned log
3. Display summary of lines kept/excluded per pattern

.PARAMETER SourceDir
Directory containing original M.E.Doc update logs (update_*.log format).
Default: "logs/source" (relative to script directory)

.PARAMETER OutputDir
Directory where cleaned log files will be written.
Default: "logs/cleaned" (relative to script directory)

.PARAMETER ExcludedDir
Directory where excluded lines are archived (for recovery/audit).
Default: "logs/excluded" (relative to script directory)

.PARAMETER PatternsFile
File containing regex patterns (one per line) to match and remove.
Default: "patterns/cleanup-patterns.txt" (relative to script directory)

.EXAMPLE
.\Invoke-LogFiltering.ps1
# Uses default directories relative to script location

.EXAMPLE
.\Invoke-LogFiltering.ps1 -SourceDir "C:\logs" -OutputDir "C:\cleaned"
# Specify custom absolute paths

.EXAMPLE
.\Invoke-LogFiltering.ps1 -PatternsFile "patterns/custom-patterns.txt"
# Use custom patterns file

.NOTES
ENCODING CRITICAL:
- Input logs must be Windows-1251 encoded (M.E.Doc standard)
- Patterns file must be UTF-8 (for cross-platform editing)
- Output logs use Windows-1251 to maintain compatibility

PATTERNS FILE FORMAT:
- One regex pattern per line
- Lines starting with '#' are treated as comments (optional)
- Empty lines are ignored
- Use standard PowerShell regex syntax
- Patterns are applied sequentially (order matters)

REGEX EXAMPLES:
  # Match literal text
  Розпаковано файл:

  # Match with whitespace
  INFO\s+Створення копії файлу:

  # Match with character classes
  MEDOCSRV\\TEMP\\[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}

  # Match hex UUID pattern
  [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}

  # Match file paths
  '[A-Z]:\\([^']*\\)*[^']+\.[a-zA-Z0-9]+'

DIRECTORY STRUCTURE:
  tools/dev/
  ├── Invoke-LogFiltering.ps1 (this script)
  ├── Add-LogFilterPattern.ps1 (interactive pattern editor)
  ├── patterns/
  │   └── cleanup-patterns.txt (patterns library)
  └── logs/
      ├── source/ (input logs from production)
      ├── cleaned/ (output after filtering)
      └── excluded/ (archive of removed lines)

WORKFLOW STEPS:
1. Place unprocessed logs in logs/source/
2. Run this script (uses default params)
3. Review cleaned logs in logs/cleaned/
4. If needed, recover excluded lines from logs/excluded/

ERROR HANDLING:
- Script stops if source directory not found
- Script stops if patterns file not found
- Invalid regex patterns will cause PowerShell errors
- Check regex syntax before running on large logs

PERFORMANCE NOTES:
- Processing speed depends on:
  a) Number of log files
  b) Size of each log file
  c) Number of patterns
  d) Complexity of regex patterns
- Typical: 100MB logs with 20 patterns = 30-60 seconds
- Progress shown for each pattern applied

SEE ALSO:
- Add-LogFilterPattern.ps1 - Interactive tool to add patterns
- tools/dev/README.md - Complete documentation and examples
- patterns/cleanup-patterns.txt - Pattern library with explanations

#>
param(
    [string]$SourceDir = (Join-Path $PSScriptRoot "logs/source"),
    [string]$OutputDir = (Join-Path $PSScriptRoot "logs/cleaned"),
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

# Validate inputs
if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory not found: $SourceDir" -ErrorAction Stop
}

if (-not (Test-Path $PatternsFile)) {
    Write-Error "Patterns file not found: $PatternsFile" -ErrorAction Stop
}

# Read all patterns (skip empty lines and comments)
$patterns = @(Get-Content $PatternsFile -Encoding utf8 | Where-Object {
    $_ -and -not $_.StartsWith('#')
})

if ($patterns.Count -eq 0) {
    Write-Warning "No patterns found in $PatternsFile (empty file or all comments)"
    exit 0
}

Write-Host "Found $($patterns.Count) patterns to apply" -ForegroundColor Cyan
Write-Host ""

# Create output directories
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path $ExcludedDir -Force | Out-Null

# Copy source to output first
Write-Host "Copying source files to output directory..." -ForegroundColor Yellow
$sourceFiles = @(Get-ChildItem $SourceDir -Filter "update_*.log")

if ($sourceFiles.Count -eq 0) {
    Write-Warning "No update_*.log files found in $SourceDir"
    exit 0
}

$sourceFiles | ForEach-Object {
    Copy-Item $_.FullName -Destination (Join-Path $OutputDir $_.Name) -Force
}
Write-Host "Copied $($sourceFiles.Count) file(s)" -ForegroundColor Green

Write-Host ""

# Apply each pattern sequentially using streaming for memory efficiency
$patternNum = 1
foreach ($pattern in $patterns) {
    Write-Host "[$patternNum/$($patterns.Count)] Applying: $pattern" -ForegroundColor Green

    $files = Get-ChildItem $OutputDir -Filter "update_*.log"
    $totalKept = 0
    $totalExcluded = 0

    foreach ($file in $files) {
        # Use temporary file for filtered content
        $tempFile = New-TemporaryFile
        $excludedPath = Join-Path $ExcludedDir $file.Name
        $linesKeptInFile = 0
        $linesExcludedInFile = 0

        try {
            # Stream-process file line-by-line without loading entire file into memory
            # Use Get-Content with Encoding parameter for cross-platform support
            Get-Content $file.FullName -Encoding $encoding -ReadCount 0 | ForEach-Object {
                if ($_ -match $pattern) {
                    $_ | Add-Content -Path $excludedPath -Encoding $encoding
                    $linesExcludedInFile++
                } else {
                    $_ | Add-Content -Path $tempFile.FullName -Encoding $encoding
                    $linesKeptInFile++
                }
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

    Write-Host "  Lines kept: $totalKept, excluded: $totalExcluded" -ForegroundColor DarkGray
    $patternNum++
}

Write-Host ""
Write-Host "✅ Done! All patterns applied." -ForegroundColor Green
Write-Host "  Cleaned logs: $OutputDir" -ForegroundColor Cyan
Write-Host "  Excluded lines: $ExcludedDir" -ForegroundColor Cyan
