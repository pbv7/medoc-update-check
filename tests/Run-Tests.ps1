#Requires -Version 7.0

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Test runner is a CLI utility that requires colored console output for readability. Write-Host is appropriate for interactive test result reporting.'
)]

<#
.SYNOPSIS
    Quick test runner for M.E.Doc Update Check project

.DESCRIPTION
    Runs all automated tests and provides a summary report.
    Supports different output formats and test filtering.

.PARAMETER Verbose
    Show detailed test output

.PARAMETER OutputFormat
    Output format: None, Detailed, Summary (default: Summary)

.PARAMETER Filter
    Filter tests by name pattern

.PARAMETER PassThru
    Return test results object for further processing

.EXAMPLE
    .\tests\Run-Tests.ps1
    Run all tests with summary output

    .\tests\Run-Tests.ps1 -Verbose
    Run all tests with detailed output

    .\tests\Run-Tests.ps1 -Filter "*success*"
    Run only tests matching "success" pattern

.NOTES
    Requires: Pester module (Install-Module Pester -Force)
#>

param(
    [switch]$Verbose,
    [ValidateSet("None", "Detailed", "Summary")]
    [string]$OutputFormat = "Summary",
    [string]$Filter,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

# Verify Pester is installed
Write-Host "Checking for Pester module..." -ForegroundColor Cyan
$pesterModule = Get-Module Pester -ListAvailable
if (-not $pesterModule) {
    Write-Host "ERROR: Pester module not found. Install with:" -ForegroundColor Red
    Write-Host "  Install-Module Pester -Force" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Pester version $($pesterModule.Version) found" -ForegroundColor Green

# Get test file paths
$testFiles = @(
    (Join-Path $PSScriptRoot "MedocUpdateCheck.Tests.ps1"),
    (Join-Path $PSScriptRoot "Utilities.Tests.ps1")
)

# Verify test files exist
foreach ($testFile in $testFiles) {
    if (-not (Test-Path $testFile)) {
        Write-Host "WARNING: Test file not found: $testFile" -ForegroundColor Yellow
    }
}

# Filter to only existing test files
$testFiles = $testFiles | Where-Object { Test-Path $_ }

if ($testFiles.Count -eq 0) {
    Write-Host "ERROR: No test files found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running $($testFiles.Count) test suite(s):" -ForegroundColor Cyan
$testFiles | ForEach-Object { Write-Host "  - $(Split-Path -Leaf $_)" -ForegroundColor Cyan }
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Prepare Invoke-Pester parameters
$pesterParams = @{
    Path = $testFiles
}

if ($Verbose) {
    $pesterParams["Verbose"] = $true
}

if ($Filter) {
    $pesterParams["Filter"] = @{ Name = $Filter }
}

if ($PassThru -or $OutputFormat -ne "None") {
    $pesterParams["PassThru"] = $true
}

# Run tests
try {
    $results = Invoke-Pester @pesterParams

    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Test Summary" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    $totalTests = $results.PassedCount + $results.FailedCount + $results.SkippedCount
    Write-Host "Total Tests: $totalTests" -ForegroundColor White
    Write-Host "Passed:      $($results.PassedCount)" -ForegroundColor Green
    Write-Host "Failed:      $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { "Red" } else { "Green" })
    Write-Host "Skipped:     $($results.SkippedCount)" -ForegroundColor Yellow
    Write-Host ""

    if ($results.FailedCount -gt 0) {
        Write-Host "Failed Tests:" -ForegroundColor Red
        $testItems = @()
        if ($results.PSObject.Properties.Name -contains 'TestResult' -and $results.TestResult) {
            $testItems = $results.TestResult
        }
        elseif ($results.PSObject.Properties.Name -contains 'Tests' -and $results.Tests) {
            $testItems = $results.Tests
        }
        if ($testItems.Count -gt 0) {
            $testItems |
                Where-Object { $_.Outcome -eq "Failed" -or $_.Result -eq "Failed" } |
                ForEach-Object {
                    Write-Host "  ✗ $($_.Name)" -ForegroundColor Red
                    if ($_.FailureMessage) {
                        Write-Host "    Error: $($_.FailureMessage)" -ForegroundColor Red
                    }
                }
        } else {
            Write-Host "  (Failed test details unavailable from PassThru; see verbose output)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($results.FailedCount -eq 0 -and $results.PassedCount -gt 0) {
        Write-Host "✓ All tests passed!" -ForegroundColor Green
    }

    if ($PassThru) {
        return $results
    }

    # Exit with appropriate code
    exit $results.FailedCount
} catch {
    Write-Host "ERROR: Failed to run tests" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
