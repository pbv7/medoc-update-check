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
    Supports code coverage measurement and test filtering.

.PARAMETER Verbose
    Show detailed test output

.PARAMETER Filter
    Filter tests by name pattern (supports wildcards: * for any characters, ? for single character)

.PARAMETER PassThru
    Return test results object for further processing

.PARAMETER Coverage
    Enable code coverage measurement (requires Pester 5.0+)
    Shows coverage stats for lib/ files (production code only)

.EXAMPLE
    .\tests\Run-Tests.ps1
    Run all tests with summary output

    .\tests\Run-Tests.ps1 -Verbose
    Run all tests with detailed output

    .\tests\Run-Tests.ps1 -Filter "*success*"
    Run only tests matching "success" pattern

    .\tests\Run-Tests.ps1 -Coverage
    Run tests with code coverage measurement and report

.NOTES
    Requires: Pester module (Install-Module Pester -Force)
    Coverage parameter requires Pester 5.0+
#>

param(
    [switch]$Verbose,
    [string]$Filter,
    [switch]$PassThru,
    [switch]$Coverage
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

# Coverage configuration (output to tests folder)
$coverageFile = Join-Path $PSScriptRoot "coverage-local.xml"

# Use Pester 5 configuration for coverage support
if ($Coverage) {
    $config = New-PesterConfiguration
    $config.Run.Path = $testFiles
    $config.Run.PassThru = $true
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @('lib', 'Run.ps1')  # Production code only
    $config.CodeCoverage.OutputPath = $coverageFile
    $config.CodeCoverage.OutputFormat = "JaCoCo"

    if ($Verbose) {
        $config.Output.Verbosity = "Detailed"
    }
    if ($Filter) {
        $config.Filter.FullName = $Filter
    }

    Write-Host "Code coverage: ENABLED" -ForegroundColor Cyan
    Write-Host ""

    # Run tests with coverage
    try {
        $results = Invoke-Pester -Configuration $config
    } catch {
        Write-Host "ERROR: Failed to run tests with coverage" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        if (Test-Path $coverageFile) {
            Remove-Item $coverageFile -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }
} else {
    # Traditional parameter-based Pester invocation (no coverage)
    Write-Host "Code coverage: disabled (use -Coverage flag to enable)" -ForegroundColor Gray
    Write-Host ""

    $pesterParams = @{
        Path = $testFiles
        PassThru = $true
    }

    if ($Verbose) {
        $pesterParams["Verbose"] = $true
    }

    if ($Filter) {
        $pesterParams["FullNameFilter"] = $Filter
    }

    # Run tests without coverage
    try {
        $results = Invoke-Pester @pesterParams
    } catch {
        Write-Host "ERROR: Failed to run tests" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

# Display test results and coverage (common for both coverage and non-coverage runs)
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

# Display coverage stats if enabled
if ($Coverage -and (Test-Path $coverageFile)) {
    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Code Coverage Report" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan

    # Parse JaCoCo XML for coverage stats
    [xml]$coverageXml = Get-Content $coverageFile
    $covNodes = $coverageXml.SelectNodes("//counter[@type='LINE']")

    if ($covNodes.Count -gt 0) {
        # Get the last (summary) counter
        $summary = $covNodes[-1]
        $covered = [int]$summary.covered
        $missed = [int]$summary.missed
        $total = $covered + $missed

        if ($total -gt 0) {
            $percent = [math]::Round(($covered / $total) * 100, 2)
            Write-Host "Lines Covered:   $covered / $total" -ForegroundColor White
            Write-Host "Coverage:        $percent%" -ForegroundColor $(if ($percent -ge 80) { "Green" } elseif ($percent -ge 60) { "Yellow" } else { "Red" })
        }
    }
    Write-Host ""
}

if ($PassThru) {
    return $results
}

# Cleanup coverage file (temporary local file)
if (Test-Path $coverageFile) {
    Remove-Item $coverageFile -Force -ErrorAction SilentlyContinue
}

# Exit with appropriate code
exit $results.FailedCount
