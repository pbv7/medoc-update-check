#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Shared helper function for log file filtering operations.

.DESCRIPTION
This module provides a reusable function for filtering log files by regex patterns.
Used by both Add-LogFilterPattern.ps1 and Invoke-LogFiltering.ps1 to avoid code duplication.

.NOTES
This is an internal helper module for the log filtering tools. It is dot-sourced by
the main scripts and should not be invoked directly by users.

ENCODING CRITICAL:
- Input logs must be Windows-1251 encoded (M.E.Doc standard)
- Output logs use Windows-1251 to maintain compatibility
#>

# Register Windows code pages for cross-platform PowerShell 7 support
# On non-Windows systems, explicitly load the encoding provider
$encodingExists = [System.Text.Encoding]::GetEncodings() | Where-Object { $_.Name -eq "windows-1251" }
if (-not $encodingExists) {
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
}

<#
.SYNOPSIS
Invoke filtering on a log file by regex pattern and return statistics.

.DESCRIPTION
Processes a single log file, filtering out lines matching the provided pattern.
Uses efficient StreamWriter for buffered I/O to handle large files with minimal memory impact.

.PARAMETER File
The log file to process (System.IO.FileInfo object).

.PARAMETER Pattern
Regex pattern string to match lines for exclusion.

.PARAMETER ExcludedDir
Directory where excluded lines are archived.

.PARAMETER Encoding
System.Text.Encoding object for file I/O (should be Windows-1251 for M.E.Doc logs).

.PARAMETER CapturePreview
Switch to capture first 5 excluded lines for preview display (useful for interactive mode).

.OUTPUTS
Hashtable with KeptCount, ExcludedCount, and ExcludedLines properties.

.EXAMPLE
$result = Invoke-PatternFilter -File $file -Pattern "INFO\s+Створення" -ExcludedDir "logs/excluded" -Encoding $encoding
Write-Host "Kept: $($result.KeptCount), Excluded: $($result.ExcludedCount)"

.EXAMPLE
# Capture preview of excluded lines for interactive review
$result = Invoke-PatternFilter -File $file -Pattern "INFO\s+Створення" -ExcludedDir "logs/excluded" -Encoding $encoding -CapturePreview
$result.ExcludedLines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }

#>
function Invoke-PatternFilter {
    param(
        [System.IO.FileInfo]$File,
        [string]$Pattern,
        [string]$ExcludedDir,
        [System.Text.Encoding]$Encoding,
        [switch]$CapturePreview
    )

    $tempFile = New-TemporaryFile
    $excludedPath = Join-Path $ExcludedDir $File.Name
    $linesKeptInFile = 0
    $linesExcludedInFile = 0
    $excludedLines = @()

    try {
        # Use StreamWriter for efficient buffered I/O
        $writerKept = [System.IO.StreamWriter]::new($tempFile.FullName, $false, $Encoding)
        $writerExcluded = [System.IO.StreamWriter]::new($excludedPath, $true, $Encoding)

        try {
            # Stream-process file line-by-line without loading entire file into memory
            foreach ($line in [System.IO.File]::ReadLines($File.FullName, $Encoding)) {
                if ($line -match $Pattern) {
                    $writerExcluded.WriteLine($line)
                    $linesExcludedInFile++
                    # Capture first 5 lines for preview if requested
                    if ($CapturePreview -and $excludedLines.Count -lt 5) {
                        $excludedLines += $line
                    }
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
        Move-Item -Path $tempFile.FullName -Destination $File.FullName -Force
    }
    finally {
        # Ensure temporary file is cleaned up
        if (Test-Path $tempFile.FullName) {
            Remove-Item $tempFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    return @{
        KeptCount = $linesKeptInFile
        ExcludedCount = $linesExcludedInFile
        ExcludedLines = $excludedLines
    }
}

function Get-LogFilterPatterns {
    <#
    .SYNOPSIS
    Load and filter regex patterns from the patterns file.
    .DESCRIPTION
    Reads the patterns file, filtering out empty lines and comment lines.
    Centralizes the pattern loading logic used by multiple scripts.
    .PARAMETER PatternsFile
    Path to the patterns file to read.
    .OUTPUTS
    Array of pattern strings (empty/comment lines removed).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PatternsFile
    )

    return @(Get-Content $PatternsFile -Encoding utf8 -ErrorAction SilentlyContinue |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}
