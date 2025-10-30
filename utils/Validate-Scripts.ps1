#!/usr/bin/env pwsh

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Validation utility requires colored console output for validation results. Write-Host is appropriate for interactive validation reporting.'
)]

<#
.SYNOPSIS
    Validates all PowerShell scripts in the project for syntax errors and code quality.

.DESCRIPTION
    Uses PSParser to tokenize all .ps1 and .psm1 files and report any syntax errors
    without executing the scripts. If PSScriptAnalyzer is installed, also performs
    code quality and best practice validation.

    Useful for pre-commit validation and CI/CD pipelines.

.PARAMETER Verbose
    Shows detailed validation output including AST type for each script.

.PARAMETER SkipAnalyzer
    Skips PSScriptAnalyzer validation even if module is installed.
    Useful for faster validation when only syntax check is needed.

.PARAMETER ExcludePattern
    Additional exclude patterns (comma-separated) for files to skip.
    Default: .git, node_modules

.EXAMPLE
    ./Validate-Scripts.ps1
    # Validates all scripts for syntax errors
    # Runs PSScriptAnalyzer if available

.EXAMPLE
    ./Validate-Scripts.ps1 -SkipAnalyzer
    # Syntax validation only (faster)

.EXAMPLE
    ./Validate-Scripts.ps1 -ExcludePattern "*.backup", "archive/*"
    # Validates excluding backup files and archive directory

.EXAMPLE
    ./Validate-Scripts.ps1 -Verbose
    # Shows detailed output including AST types and analyzer details
#>

#Requires -Version 7.0

param(
    [switch]$Verbose,
    [switch]$SkipAnalyzer,
    [string[]]$ExcludePattern = @()
)

$ErrorActionPreference = "Continue"
$startTime = Get-Date

# Script root is project root (parent of utils directory where this script lives)
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptFiles = @()
$validationResults = @{
    SyntaxPassed = @()
    SyntaxFailed = @()
    AnalyzerIssues = @()
    AnalyzerInstalled = $false
}

# Build exclusion patterns
$defaultExclusions = @(".git", "node_modules")
$allExclusions = $defaultExclusions + $ExcludePattern

Write-Host "PowerShell Script Validator" -ForegroundColor Cyan
Write-Host ([string]::new('=', 50)) -ForegroundColor Gray
Write-Host ""

# Check if PSScriptAnalyzer is available
$analyzerAvailable = $false
if (-not $SkipAnalyzer) {
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        $analyzerAvailable = $true
        $validationResults.AnalyzerInstalled = $true
        Write-Host "PSScriptAnalyzer detected - running quality validation" -ForegroundColor Cyan
    }
}
Write-Host ""

# Find all PowerShell scripts
Write-Host "Scanning for PowerShell scripts..." -ForegroundColor Cyan
$scriptFiles = @(
    Get-ChildItem -Path $scriptRoot -Include "*.ps1", "*.psm1" -Recurse |
    Where-Object {
        $fullPath = $_.FullName
        # Check exclusion patterns
        $excluded = $false
        foreach ($pattern in $allExclusions) {
            if ($fullPath -match [regex]::Escape($pattern) -or $fullPath -match $pattern) {
                $excluded = $true
                break
            }
        }
        -not $excluded
    }
)

Write-Host "Found $($scriptFiles.Count) script(s)"
if ($ExcludePattern.Count -gt 0) {
    Write-Host "  (Excluding: $($allExclusions -join ', '))" -ForegroundColor DarkGray
}
Write-Host ""

if ($scriptFiles.Count -eq 0) {
    Write-Host "No PowerShell scripts found" -ForegroundColor Yellow
    exit 0
}

# Validate each script - Syntax check
Write-Host "Validating syntax..." -ForegroundColor Cyan
foreach ($script in $scriptFiles) {
    $relativePath = $script.FullName.Replace("$scriptRoot/", "").Replace("$scriptRoot\", "")
    $displayPath = $relativePath -replace "\\", "/"

    try {
        $content = Get-Content -Path $script.FullName -Raw -ErrorAction Stop

        # Attempt to parse the script (validates syntax without execution)
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $content,
            [ref]$null,
            [ref]$parseErrors
        )

        if ($parseErrors.Count -gt 0) {
            Write-Host "✗ $displayPath" -ForegroundColor Red
            $validationResults.SyntaxFailed += $displayPath

            foreach ($parseError in $parseErrors) {
                Write-Host "  Line $($parseError.Extent.StartLineNumber): $($parseError.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✓ $displayPath" -ForegroundColor Green
            $validationResults.SyntaxPassed += $displayPath

            if ($Verbose) {
                Write-Host "  AST Type: $($ast.GetType().Name)" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host "✗ $displayPath" -ForegroundColor Red
        $validationResults.SyntaxFailed += $displayPath
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Run PSScriptAnalyzer if available
if ($analyzerAvailable) {
    Write-Host ""
    Write-Host "Running PSScriptAnalyzer..." -ForegroundColor Cyan

    try {
        Import-Module PSScriptAnalyzer -Force
        $analyzerResults = Invoke-ScriptAnalyzer -Path $scriptRoot -Recurse -ErrorAction Continue

        if ($analyzerResults) {
            $validationResults.AnalyzerIssues = $analyzerResults

            if ($Verbose) {
                $analyzerResults | ForEach-Object {
                    $severity = $_.Severity
                    $severityColor = switch ($severity) {
                        "Error" { "Red" }
                        "Warning" { "Yellow" }
                        "Information" { "Gray" }
                        default { "White" }
                    }

                    Write-Host "  [$severity] $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor $severityColor
                    if ($_.SuggestedCorrections) {
                        Write-Host "    → $($_.SuggestedCorrections[0].Text)" -ForegroundColor DarkGreen
                    }
                }
            } else {
                $errorCount = ($analyzerResults | Where-Object { $_.Severity -eq "Error" }).Count
                $warningCount = ($analyzerResults | Where-Object { $_.Severity -eq "Warning" }).Count
                Write-Host "  Found $errorCount errors, $warningCount warnings" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No code quality issues found ✓" -ForegroundColor Green
        }
    } catch {
        Write-Host "  Error running PSScriptAnalyzer: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Calculate validation time
$elapsedTime = ((Get-Date) - $startTime).TotalMilliseconds

# Summary
Write-Host ""
Write-Host ([string]::new('=', 50)) -ForegroundColor Gray
Write-Host "Validation Summary:" -ForegroundColor Cyan
Write-Host "  ✓ Syntax Passed:  $($validationResults.SyntaxPassed.Count)"
Write-Host "  ✗ Syntax Failed:  $($validationResults.SyntaxFailed.Count)"

if ($analyzerAvailable) {
    $errorCount = ($validationResults.AnalyzerIssues | Where-Object { $_.Severity -eq "Error" }).Count
    $warningCount = ($validationResults.AnalyzerIssues | Where-Object { $_.Severity -eq "Warning" }).Count
    $infoCount = ($validationResults.AnalyzerIssues | Where-Object { $_.Severity -eq "Information" }).Count

    Write-Host "  ⚠️  Analyzer Issues:"
    Write-Host "      • Errors:      $errorCount"
    Write-Host "      • Warnings:    $warningCount"
    Write-Host "      • Information: $infoCount"
}

Write-Host "  ⏱️  Time: $([math]::Round($elapsedTime, 2))ms"
Write-Host ""

# Determine exit code
$hasErrors = $false
if ($validationResults.SyntaxFailed.Count -gt 0) {
    Write-Host "Failed scripts:" -ForegroundColor Red
    $validationResults.SyntaxFailed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    $hasErrors = $true
}

if ($analyzerAvailable -and $validationResults.AnalyzerIssues) {
    $analyzerErrors = $validationResults.AnalyzerIssues | Where-Object { $_.Severity -eq "Error" }
    if ($analyzerErrors) {
        Write-Host ""
        Write-Host "PSScriptAnalyzer errors:" -ForegroundColor Red
        $analyzerErrors | ForEach-Object {
            Write-Host "  - $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor Red
        }
        $hasErrors = $true
    }
}

if (-not $hasErrors) {
    Write-Host "All validations passed! ✅" -ForegroundColor Green
    exit 0
} else {
    exit 1
}
