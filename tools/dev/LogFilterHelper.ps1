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
Apply a regex pattern to a single file and return filtering statistics.

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

.OUTPUTS
Hashtable with KeptCount and ExcludedCount properties.

.EXAMPLE
$result = Apply-PatternToFile -File $file -Pattern "INFO\s+Створення" -ExcludedDir "logs/excluded" -Encoding $encoding
Write-Host "Kept: $($result.KeptCount), Excluded: $($result.ExcludedCount)"

#>
function Apply-PatternToFile {
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

# Export function for use by dot-sourcing scripts
Export-ModuleFunction -Function Apply-PatternToFile -ErrorAction SilentlyContinue
