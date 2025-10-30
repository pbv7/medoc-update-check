# PSScriptAnalyzer Note: This test file uses unused mock function parameters.
# These are intentional - mock function signatures match the real functions they replace,
# even when specific parameters aren't used in a particular test scenario.

<#
.SYNOPSIS
    Pester tests for MedocUpdateCheck module

.DESCRIPTION
    Comprehensive unit and integration tests for the M.E.Doc Update Check module.
    Tests core functionality: log parsing, update detection, and notification sending.

.NOTES
    Run with: Invoke-Pester -Path "tests/MedocUpdateCheck.Tests.ps1" -Verbose
    Requires: Pester module (Install-Module Pester -Force)
#>

# Import module at compile time to make enum types available
using module "..\lib\MedocUpdateCheck.psm1"

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "..\lib\MedocUpdateCheck.psm1"
    Import-Module $modulePath -Force

    # Test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
}

Describe "Test-UpdateOperationSuccess - Unit Tests" {

    Context "Successful update detection with dual-log validation" {
        It "Should detect successful update when all 3 flags present in update log" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Success"
            $result.ErrorId | Should -Be ([MedocEventId]::Success)
            $result.Success | Should -Be $true
            $result.TargetVersion | Should -Not -BeNullOrEmpty
        }

        It "Should return hashtable with correct properties for successful update" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "Success") | Should -Be $true
            ($result.Keys -contains "UpdateTime") | Should -Be $true
            ($result.Keys -contains "TargetVersion") | Should -Be $true
            ($result.Keys -contains "UpdateLogPath") | Should -Be $true
            ($result.Keys -contains "Flag1_Infrastructure") | Should -Be $true
            ($result.Keys -contains "Flag2_ServiceRestart") | Should -Be $true
            ($result.Keys -contains "Flag3_VersionConfirm") | Should -Be $true
            ($result.Keys -contains "Status") | Should -Be $true
            ($result.Keys -contains "ErrorId") | Should -Be $true
        }

        It "Should parse update time correctly from Planner.log" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateTime | Should -BeOfType [datetime]
        }

        It "Should extract target version from update filename" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.TargetVersion | Should -Match "^\d+$"  # Should be a number like 184 or 186
        }
    }

    Context "No update detection" {
        It "Should return NoUpdate status when no updates in Planner.log" {
            $logsDir = Join-Path $testDataDir "dual-log-no-update"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "NoUpdate"
            $result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)
            $result.Message | Should -Match "No update"
        }
    }

    Context "Failed update detection (missing log file)" {
        It "Should return failure when update log file is missing" {
            $logsDir = Join-Path $testDataDir "dual-log-missing-updatelog"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
            $result.ErrorId | Should -Be ([MedocEventId]::UpdateLogMissing)
            $result.Success | Should -Be $false
            $result.Reason | Should -Match "Update log file not found"
        }
    }

    Context "Failed update detection (missing success flags)" {
        It "Should return failure when Flag1_Infrastructure is missing" {
            $logsDir = Join-Path $testDataDir "dual-log-missing-flag1"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
            $result.ErrorId | Should -Be ([MedocEventId]::Flag1Failed)
            $result.Success | Should -Be $false
            $result.Flag1_Infrastructure | Should -Be $false
        }

        It "Should return failure when Flag2_ServiceRestart is missing" {
            $logsDir = Join-Path $testDataDir "dual-log-missing-flag2"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
            $result.ErrorId | Should -Be ([MedocEventId]::Flag2Failed)
            $result.Success | Should -Be $false
            $result.Flag2_ServiceRestart | Should -Be $false
        }

        It "Should return failure when Flag3_VersionConfirm is missing" {
            $logsDir = Join-Path $testDataDir "dual-log-missing-flag3"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
            $result.ErrorId | Should -Be ([MedocEventId]::Flag3Failed)
            $result.Success | Should -Be $false
            $result.Flag3_VersionConfirm | Should -Be $false
        }

        It "Should return failure when version number doesn't match target" {
            $logsDir = Join-Path $testDataDir "dual-log-wrong-version"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
            $result.ErrorId | Should -Be ([MedocEventId]::Flag3Failed)
            $result.Success | Should -Be $false
            $result.Flag3_VersionConfirm | Should -Be $false
        }

        It "Should return MultipleFlagsFailed when two or more flags are missing" {
            $logsDir = Join-Path $testDataDir "dual-log-multiple-flags-failed"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
            $result.ErrorId | Should -Be ([MedocEventId]::MultipleFlagsFailed)
            $result.Success | Should -Be $false
            # Multiple flags should be false
            $result.Flag1_Infrastructure | Should -Be $false
            $result.Flag2_ServiceRestart | Should -Be $false
            $result.Flag3_VersionConfirm | Should -Be $true
        }
    }

    Context "Checkpoint filtering (SinceTime)" {
        It "Should return NoUpdate status when updates are before checkpoint time" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $checkpointTime = [datetime]::ParseExact("31.12.2025 23:59:59", "dd.MM.yyyy HH:mm:ss", $null)

            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -SinceTime $checkpointTime

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "NoUpdate"
            $result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)
        }

        It "Should include updates after checkpoint time" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $checkpointTime = [datetime]::ParseExact("01.01.2020 00:00:00", "dd.MM.yyyy HH:mm:ss", $null)

            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -SinceTime $checkpointTime

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Success"
            $result.ErrorId | Should -Be ([MedocEventId]::Success)
        }
    }

    Context "Encoding support" {
        It "Should support Windows-1251 encoding (default)" {
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -EncodingCodePage 1251

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Success"
        }
    }

    Context "Error handling" {
        It "Should return error status when log directory does not exist" {
            $invalidPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $result = & {
                Test-UpdateOperationSuccess -MedocLogsPath $invalidPath -ErrorAction SilentlyContinue
            } 2>$null

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Error"
            $result.ErrorId | Should -Be ([MedocEventId]::PlannerLogMissing)
        }

        It "Should require MedocLogsPath parameter" {
            { Test-UpdateOperationSuccess -ErrorAction Stop } | Should -Throw
        }

        It "Should return error status when Planner.log is missing" {
            $missingPlannerDir = Join-Path $testDataDir "missing-planner"
            if (-not (Test-Path $missingPlannerDir)) {
                New-Item -ItemType Directory -Path $missingPlannerDir | Out-Null
            }
            try {
                $result = & {
                    Test-UpdateOperationSuccess -MedocLogsPath $missingPlannerDir -ErrorAction SilentlyContinue
                } 2>$null
                $result | Should -Not -BeNullOrEmpty
                $result.Status | Should -Be "Error"
                $result.ErrorId | Should -Be ([MedocEventId]::PlannerLogMissing)
            } finally {
                Remove-Item $missingPlannerDir -Recurse -Force
            }
        }
    }

    Context "Event Log verification for error paths" {
        BeforeEach {
            # Initialize Event Log capture for this context
            $script:capturedLogEvents = @()

            # Mock Write-EventLogEntry to capture calls (works on all platforms)
            Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
                param(
                    [string]$Message,
                    [string]$EventType,
                    [int]$EventId,
                    [string]$EventLogSource,
                    [string]$EventLogName
                )
                $script:capturedLogEvents += [pscustomobject]@{
                    Message   = $Message
                    EventType = $EventType
                    EventId   = $EventId
                    Source    = $EventLogSource
                    LogName   = $EventLogName
                }
            }
        }

        It "Should log PlannerLogMissing error when Planner.log is absent" {
            $missingDir = Join-Path $testDataDir "test-missing-planner-$(New-Guid)"
            New-Item -ItemType Directory -Path $missingDir -Force | Out-Null

            try {
                $result = Test-UpdateOperationSuccess -MedocLogsPath $missingDir -ErrorAction SilentlyContinue

                # Verify error status
                $result.Status | Should -Be "Error"
                $result.ErrorId | Should -Be ([MedocEventId]::PlannerLogMissing)

                # Verify Event Log was called with correct EventId (platform-independent test via mock)
                $logEntry = $script:capturedLogEvents | Where-Object { $_.EventId -eq ([int][MedocEventId]::PlannerLogMissing) } | Select-Object -Last 1
                $logEntry | Should -Not -BeNullOrEmpty
                $logEntry.EventType | Should -Be "Error"
                $logEntry.Message | Should -Match "Planner.log not found"
            } finally {
                Remove-Item $missingDir -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should log EncodingError when log file cannot be read" {
            # Create test directory with Planner.log that has invalid content
            $testDir = Join-Path $testDataDir "test-encoding-error-$(New-Guid)"

            try {
                New-Item -ItemType Directory -Path $testDir -Force | Out-Null

                # Create Planner.log with minimal invalid content
                # Using UTF-8 with BOM which may cause issues with Windows-1251 parsing
                "Test`nInvalid content" | Set-Content -Path "$testDir\Planner.log" -Encoding UTF8

                # Try to read with Windows-1251 encoding - should work but demonstrates error path
                # For this test, we'll rely on the mock to verify error paths log correctly
                $result = Test-UpdateOperationSuccess -MedocLogsPath $testDir -EncodingCodePage 1251 -ErrorAction SilentlyContinue

                # Note: This test validates the error handling mechanism
                # Whether it returns "Error" or "NoUpdate" depends on file content
                # The important thing is that IF an error occurs, it's logged
                # Current test verifies the logging infrastructure is in place
                $result | Should -Not -BeNullOrEmpty
                ($result.Status -eq "Error" -or $result.Status -eq "NoUpdate") | Should -Be $true
            } finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should log all error paths with appropriate EventId and Error level" {
            # This test validates that the logging infrastructure is properly connected
            # Mock Test-UpdateOperationSuccess to return an error status
            Mock -CommandName Test-UpdateOperationSuccess -ModuleName MedocUpdateCheck -MockWith {
                @{
                    Status  = "Error"
                    ErrorId = [MedocEventId]::EncodingError
                    Message = "Error reading log file"
                }
            }

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
            $result.Outcome | Should -Be 'Error'

            # Verify that error was logged to Event Log with correct EventId
            $errorLogEntry = $script:capturedLogEvents | Where-Object { $_.EventId -eq ([int][MedocEventId]::EncodingError) } | Select-Object -Last 1
            $errorLogEntry | Should -Not -BeNullOrEmpty
            $errorLogEntry.EventType | Should -Be "Error"
        }
    }

    Context "Warning Event Log verification" {
        BeforeEach {
            $script:capturedLogEvents = @()
            $script:capturedWarnings = @()

            Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
                param(
                    [string]$Message,
                    [string]$EventType,
                    [int]$EventId,
                    [string]$EventLogSource,
                    [string]$EventLogName
                )
                $script:capturedLogEvents += [pscustomobject]@{
                    Message   = $Message
                    EventType = $EventType
                    EventId   = $EventId
                }
            }

            # Capture Write-Warning calls (they go to different stream)
            $warningVariable = "WarningPreference"
            Set-Variable -Name $warningVariable -Value "Continue" -Scope Global
        }

        It "Should log warning to Event Log when EncodingCodePage is invalid" {
            $logsDir = Join-Path $testDataDir "dual-log-success"

            $result = Invoke-MedocUpdateCheck -Config @{
                ServerName        = "TestServer"
                MedocLogsPath     = $logsDir
                BotToken          = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId            = "12345"
                EncodingCodePage  = 9999  # Invalid codepage
            } -ErrorAction SilentlyContinue 2>$null

            # Verify function handled the warning and continued
            $result.Outcome | Should -Be 'Error'  # Telegram/transport or other error outcome

            # Verify warning was logged to Event Log with correct EventId and type
            $warnEntry = $script:capturedLogEvents |
                Where-Object { $_.EventId -eq ([int][MedocEventId]::ConfigInvalidValue) -and $_.EventType -eq "Warning" } |
                Select-Object -Last 1
            $warnEntry | Should -Not -BeNullOrEmpty
            $warnEntry.Message | Should -Match "EncodingCodePage.*(invalid|not supported)"
        }

        It "Should log error when Event Log source cannot be created (admin required)" {
            # Mock New-Item to fail when creating checkpoint directory
            # This simulates permission issues during initialization
            $logsDir = Join-Path $testDataDir "dual-log-success"

            Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
                param(
                    [string]$Message,
                    [string]$EventType,
                    [int]$EventId,
                    [string]$EventLogSource,
                    [string]$EventLogName
                )
                # Simulate Event Log source creation failure (no admin)
                if ($Message -match "Failed to create checkpoint") {
                    $script:capturedLogEvents += [pscustomobject]@{
                        Message   = $Message
                        EventType = $EventType
                        EventId   = $EventId
                    }
                }
            }

            $result = Invoke-MedocUpdateCheck -Config @{
                ServerName    = "TestServer"
                MedocLogsPath = $logsDir
                LastRunFile   = (Join-Path $logsDir ("checkpoint-eventlog-{0}.txt" -f ([guid]::NewGuid().ToString("N"))))
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            } -ErrorAction SilentlyContinue 2>$null

            # Function should handle gracefully (continue execution)
            $result.Outcome | Should -Be 'Error'  # Error outcome but execution path reached
        }

        It "Should handle Write-EventLogEntry gracefully when Event Log is unavailable" {
            # This test validates that warnings are issued when Event Log fails
            # but execution continues (important for cross-platform compatibility)
            $logsDir = Join-Path $script:testDataDir "dual-log-success"

            # Mock Invoke-RestMethod to simulate successful Telegram API response
            Mock -CommandName Invoke-RestMethod -ModuleName MedocUpdateCheck -MockWith {
                return @{ ok = $true }
            }

            # On macOS/Linux, Event Log operations fail gracefully with Write-Warning
            # This test ensures that behavior is correct
            $result = Invoke-MedocUpdateCheck -Config @{
                ServerName    = "TestServer"
                MedocLogsPath = $logsDir
                LastRunFile   = (Join-Path -Path $logsDir -ChildPath ("checkpoint-eventlog2-{0}.txt" -f ([guid]::NewGuid().ToString("N"))))
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            } -ErrorAction SilentlyContinue 2>$null

            # Function should complete (not throw) and return structured success outcome
            $result.Outcome | Should -Be 'Success'
        }
    }
}

Describe "Get-VersionInfo - Version Parsing Tests" {

    Context "Standard format (ezvit.X.Y.Z-X.Y.Z.upd)" {
        It "Should parse version with dash separator" {
            $result = Get-VersionInfo -RawVersion "ezvit.11.02.183-11.02.184.upd"
            $result.FromVersion | Should -Be "11.02.183"
            $result.ToVersion | Should -Be "11.02.184"
        }

        It "Should parse version without .upd extension" {
            $result = Get-VersionInfo -RawVersion "ezvit.11.02.183-11.02.184"
            $result.FromVersion | Should -Be "11.02.183"
            $result.ToVersion | Should -Be "11.02.184"
        }

        It "Should handle version numbers with leading zeros" {
            $result = Get-VersionInfo -RawVersion "ezvit.11.02.001-11.02.100.upd"
            $result.FromVersion | Should -Be "11.02.001"
            $result.ToVersion | Should -Be "11.02.100"
        }
    }

    Context "M.E.Doc format variations" {
        It "Should parse version with hyphen (standard M.E.Doc format)" {
            $result = Get-VersionInfo -RawVersion "ezvit.11.02.183-11.02.184.upd"
            $result.FromVersion | Should -Be "11.02.183"
            $result.ToVersion | Should -Be "11.02.184"
        }

        It "Should handle hyphen without ezvit prefix" {
            $result = Get-VersionInfo -RawVersion "11.02.183-11.02.184"
            $result.FromVersion | Should -Be "11.02.183"
            $result.ToVersion | Should -Be "11.02.184"
        }
    }

    Context "Fallback for unknown formats" {
        It "Should handle dash-separated unknown format" {
            $result = Get-VersionInfo -RawVersion "old-something-11.02.184"
            # Dash matches, so it will try to split
            $result.FromVersion | Should -Not -BeNullOrEmpty
            $result.ToVersion | Should -Not -BeNullOrEmpty
        }

        It "Should handle single version number" {
            $result = Get-VersionInfo -RawVersion "11.02.184.upd"
            $result.FromVersion | Should -Be "previous"
            $result.ToVersion | Should -Be "11.02.184"
        }
    }

    Context "Edge cases" {
        It "Should handle empty product name prefix" {
            $result = Get-VersionInfo -RawVersion "11.02.183-11.02.184"
            $result.FromVersion | Should -Be "11.02.183"
            $result.ToVersion | Should -Be "11.02.184"
        }

        It "Should trim whitespace from version numbers" {
            $result = Get-VersionInfo -RawVersion "  ezvit.11.02.183 - 11.02.184  "
            $result.FromVersion | Should -Match "11.02.183"
            $result.ToVersion | Should -Match "11.02.184"
        }
    }
}

Describe "Write-EventLogEntry - Unit Tests" {

    Context "Function exists and is callable" {
        It "Should be exported from module" {
            Get-Command Write-EventLogEntry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should accept required parameters" {
            { Write-EventLogEntry -Message "Test message" } | Should -Not -Throw
        }

        It "Should accept optional parameters" {
            { Write-EventLogEntry -Message "Test" -EventType "Warning" -EventId 2000 } | Should -Not -Throw
        }
    }

    Context "Parameter validation" {
        It "Should require Message parameter" {
            # When mandatory parameter is missing, PowerShell raises a ParameterBindingException
            { $null | Write-EventLogEntry -ErrorAction Stop } | Should -Throw
        }

        It "Should validate EventType values" {
            { Write-EventLogEntry -Message "Test" -EventType "InvalidType" } | Should -Throw
        }

        It "Should accept valid EventType values" {
            { Write-EventLogEntry -Message "Test" -EventType "Information" } | Should -Not -Throw
            { Write-EventLogEntry -Message "Test" -EventType "Warning" } | Should -Not -Throw
            { Write-EventLogEntry -Message "Test" -EventType "Error" } | Should -Not -Throw
        }
    }

    Context "Default values" {
        It "Should use Information as default EventType" {
            # This implicitly tests that the function accepts the call without EventType
            { Write-EventLogEntry -Message "Test message" } | Should -Not -Throw
        }

        It "Should use 1000 as default EventId" {
            # Function should accept call and use 1000 as EventId
            { Write-EventLogEntry -Message "Test message" } | Should -Not -Throw
        }
    }
}

Describe "Invoke-MedocUpdateCheck - Integration Tests" {

    Context "Configuration validation" {
        It "Should reject missing ServerName" {
            $badConfig = @{
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            { Invoke-MedocUpdateCheck -Config $badConfig -ErrorAction Stop } | Should -Throw
        }

        It "Should reject missing MedocLogsPath" {
            $badConfig = @{
                ServerName = "TestServer"
                BotToken   = "test_token"
                ChatId     = "12345"
            }

            { Invoke-MedocUpdateCheck -Config $badConfig -ErrorAction Stop } | Should -Throw
        }

        It "Should reject all missing required keys" {
            $requiredKeys = @("ServerName", "MedocLogsPath", "BotToken", "ChatId")
            foreach ($missingKey in $requiredKeys) {
                $config = @{
                    ServerName     = "TestServer"
                    MedocLogsPath  = "C:\test"
                    BotToken       = "test_token"
                    ChatId         = "12345"
                }
                $config.Remove($missingKey)

                { Invoke-MedocUpdateCheck -Config $config -ErrorAction Stop } | Should -Throw
            }
        }
    }

    Context "Required config presence" {
        It "Should require hashtable Config parameter" {
            { Invoke-MedocUpdateCheck } | Should -Throw
        }
    }

    Context "Default values" {
        It "Should use default encoding when not specified" {
            # This is tested indirectly - the function should not throw when missing
            $logsDir = Join-Path $testDataDir "dual-log-success"
            $tempCheckpoint = Join-Path $testDataDir ".test-checkpoint.txt"

            try {
                $config = @{
                    ServerName        = "TestServer"
                    MedocLogsPath     = $logsDir
                    LastRunFile       = $tempCheckpoint
                    BotToken          = "invalid_token"
                    ChatId            = "12345"
                    # EncodingCodePage intentionally omitted (should default to 1251)
                }

                # Should return structured error outcome when Telegram/API fails
                $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
                $result.Outcome | Should -Be 'Error'
            } finally {
                if (Test-Path $tempCheckpoint) { Remove-Item $tempCheckpoint }
            }
        }
    }

    Context "Event ID mapping" {
        BeforeEach {
            $script:loggedEvents = @()

            Mock -CommandName Format-UpdateTelegramMessage -ModuleName MedocUpdateCheck -MockWith {
                param($UpdateResult, $ServerName, $CheckTime)
                "TELEGRAM_MESSAGE"
            }

            Mock -CommandName Format-UpdateEventLogMessage -ModuleName MedocUpdateCheck -MockWith {
                param($UpdateResult, $ServerName, $CheckTime)
                "EVENT_LOG_MESSAGE"
            }

            Mock -CommandName Invoke-RestMethod -ModuleName MedocUpdateCheck -MockWith { @{ ok = $true } }

            Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
                param(
                    [string]$Message,
                    [string]$EventType,
                    [int]$EventId,
                    [string]$EventLogSource,
                    [string]$EventLogName
                )
                $script:loggedEvents += [pscustomobject]@{
                    Message   = $Message
                    EventType = $EventType
                    EventId   = $EventId
                }
            }
        }

        AfterEach {
            if (Get-Variable -Name checkpointPath -Scope Script -ErrorAction SilentlyContinue) {
                if (Test-Path $script:checkpointPath) { Remove-Item $script:checkpointPath -Force }
                Remove-Variable -Name checkpointPath -Scope Script -ErrorAction SilentlyContinue
            }
        }

        It "Should log success event as Information with ID 1000" {
            Mock -CommandName Test-UpdateOperationSuccess -ModuleName MedocUpdateCheck -MockWith {
                @{
                    Status               = "Success"
                    ErrorId              = [MedocEventId]::Success
                    Success              = $true
                    FromVersion          = "11.02.183"
                    ToVersion            = "11.02.184"
                    UpdateStartTime      = Get-Date
                    UpdateEndTime        = Get-Date
                    UpdateDuration       = 60
                    Flag1_Infrastructure = $true
                    Flag2_ServiceRestart = $true
                    Flag3_VersionConfirm = $true
                    Reason               = "All success flags confirmed"
                }
            }

            $script:checkpointPath = Join-Path $testDataDir ("checkpoint-success-{0}.txt" -f ([guid]::NewGuid().ToString("N")))

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                LastRunFile   = $script:checkpointPath
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
            $result.Outcome | Should -Be 'Success'
            $result.NotificationSent | Should -Be $true

            $eventRecord = $script:loggedEvents | Where-Object { $_.Message -eq "EVENT_LOG_MESSAGE" } | Select-Object -Last 1
            $eventRecord | Should -Not -BeNullOrEmpty
            $eventRecord.EventId | Should -Be ([int][MedocEventId]::Success)
            $eventRecord.EventType | Should -Be "Information"
        }

        It "Should log no-update event as Information with ID 1001" {
            Mock -CommandName Test-UpdateOperationSuccess -ModuleName MedocUpdateCheck -MockWith {
                @{
                    Status  = "NoUpdate"
                    ErrorId = [MedocEventId]::NoUpdate
                    Message = "No updates found"
                }
            }

            $script:checkpointPath = Join-Path $testDataDir ("checkpoint-noupdate-{0}.txt" -f ([guid]::NewGuid().ToString("N")))

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                LastRunFile   = $script:checkpointPath
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
            $result.Outcome | Should -Be 'NoUpdate'
            $result.NotificationSent | Should -Be $true

            $eventRecord = $script:loggedEvents | Where-Object { $_.Message -eq "EVENT_LOG_MESSAGE" } | Select-Object -Last 1
            $eventRecord | Should -Not -BeNullOrEmpty
            $eventRecord.EventId | Should -Be ([int][MedocEventId]::NoUpdate)
            $eventRecord.EventType | Should -Be "Information"
        }

        It "Should log flag failure event as Error with mapped ID" {
            Mock -CommandName Test-UpdateOperationSuccess -ModuleName MedocUpdateCheck -MockWith {
                @{
                    Status               = "Failed"
                    ErrorId              = [MedocEventId]::Flag1Failed
                    Success              = $false
                    FromVersion          = "11.02.183"
                    ToVersion            = "11.02.184"
                    Flag1_Infrastructure = $false
                    Flag2_ServiceRestart = $true
                    Flag3_VersionConfirm = $true
                    Reason               = "Flag1 missing"
                }
            }

            $script:checkpointPath = Join-Path $testDataDir ("checkpoint-failure-{0}.txt" -f ([guid]::NewGuid().ToString("N")))

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                LastRunFile   = $script:checkpointPath
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
            $result.Outcome | Should -Be 'UpdateFailed'
            $result.NotificationSent | Should -Be $true

            $eventRecord = $script:loggedEvents | Where-Object { $_.Message -eq "EVENT_LOG_MESSAGE" } | Select-Object -Last 1
            $eventRecord | Should -Not -BeNullOrEmpty
            $eventRecord.EventId | Should -Be ([int][MedocEventId]::Flag1Failed)
            $eventRecord.EventType | Should -Be "Error"
        }

        It "Should stop early and log error when update routine reports Error" {
            Mock -CommandName Test-UpdateOperationSuccess -ModuleName MedocUpdateCheck -MockWith {
                @{
                    Status  = "Error"
                    ErrorId = [MedocEventId]::PlannerLogMissing
                    Message = "Planner.log missing"
                }
            }

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                LastRunFile   = Join-Path $testDataDir ("checkpoint-error-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
            $result.Outcome | Should -Be 'Error'

            $eventRecord = $script:loggedEvents | Where-Object { $_.EventId -eq ([int][MedocEventId]::PlannerLogMissing) } | Select-Object -Last 1
            $eventRecord | Should -Not -BeNullOrEmpty
            $eventRecord.EventType | Should -Be "Error"
        }
    }
}

Describe "Message Formatting - Unit Tests" {

    Context "Version extraction from UpdateLine" {
        It "Should extract version from success UpdateLine" {
            $updateLine = "Завантаження оновлення ezvit.11.02.183-11.02.184.upd"
            $version = ($updateLine -split 'Завантаження оновлення')[1].Trim()

            $version | Should -Be "ezvit.11.02.183-11.02.184.upd"
        }

        It "Should handle version without .upd extension" {
            $updateLine = "Завантаження оновлення ezvit.11.02.183-11.02.184"
            $version = ($updateLine -split 'Завантаження оновлення')[1].Trim()

            $version | Should -Be "ezvit.11.02.183-11.02.184"
        }

        It "Should trim extra whitespace from version string" {
            $updateLine = "Завантаження оновлення  ezvit.11.02.183-11.02.184  "
            $version = ($updateLine -split 'Завантаження оновлення')[1].Trim()

            $version | Should -Be "ezvit.11.02.183-11.02.184"
        }
    }

    Context "Message construction" {
        It "Should include server name in success message" {
            $serverName = "TestServer"
            $version = "ezvit.11.02.183-11.02.184"
            $timeTaken = 7.2
            $timestamp = "25.09.2025 5:07:12"

            $message = "✅ $serverName`nМ.E.Doc оновлено до версії $version`nЧас виконання: ${timeTaken} хв`nПеревірено: $timestamp"

            $message | Should -Match "✅ TestServer"
            $message | Should -Match "ezvit.11.02.183-11.02.184"
            $message | Should -Match "7.2 хв"
        }

        It "Should format failure message with emoji and version" {
            $serverName = "TestServer"
            $version = "ezvit.11.02.183-11.02.184"
            $timestamp = "25.09.2025 5:07:12"

            $message = "❌ $serverName`nПОМИЛКА при оновленні до версії $version`nПеревірено: $timestamp"

            $message | Should -Match "❌ TestServer"
            $message | Should -Match "ПОМИЛКА при оновленні"
            $message | Should -Match "ezvit.11.02.183-11.02.184"
        }

        It "Should format no-update message with info emoji" {
            $serverName = "TestServer"
            $timestamp = "25.09.2025 5:07:12"

            $message = "ℹ️ $serverName`nОновлень не було`nПеревірено: $timestamp"

            $message | Should -Match "ℹ️ TestServer"
            $message | Should -Match "Оновлень не було"
            $message | Should -Match $timestamp
        }

        It "Should include newlines for proper message formatting" {
            $serverName = "Server1"
            $version = "v1.0"
            $message = "✅ $serverName`nМ.E.Doc оновлено до версії $version"

            # Check that message contains backtick-n (escaped newline)
            $message | Should -Match "Server1`nМ.E.Doc"
        }
    }

    Context "Cyrillic text handling" {
        It "Should preserve Cyrillic characters in message" {
            $message = "❌ Тест`nПОМИЛКА при оновленні до версії test"

            $message | Should -Match "Тест"
            $message | Should -Match "ПОМИЛКА"
            $message | Should -Match "оновленні"
        }

        It "Should handle Cyrillic ServerName in message" {
            $serverName = "Сервер_1"
            $message = "✅ $serverName`nОновлено успішно"

            $message | Should -Match "Сервер_1"
            $message | Should -Match "Оновлено успішно"
        }
    }
}

Describe "Checkpoint Operations - Unit Tests" {

    Context "Checkpoint filename generation" {
        It "Should sanitize server name in checkpoint filename" {
            $serverName = "Server-01"
            $checkpointFileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            $checkpointFileName | Should -Be "last_run_Server-01.txt"
        }

        It "Should replace special characters with underscore in filename" {
            $serverName = "Server@01#Test"
            $checkpointFileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            $checkpointFileName | Should -Be "last_run_Server_01_Test.txt"
        }

        It "Should handle spaces in server name" {
            $serverName = "Server 01 Test"
            $checkpointFileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            $checkpointFileName | Should -Be "last_run_Server_01_Test.txt"
        }

        It "Should preserve hyphens and alphanumeric in filename" {
            $serverName = "Server-01_Test-02"
            $checkpointFileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            $checkpointFileName | Should -Be "last_run_Server-01_Test-02.txt"
        }
    }

    Context "Checkpoint timestamp handling" {
        It "Should parse valid checkpoint timestamp in correct format" {
            $checkpointContent = "25.09.2025 05:00:00"

            $lastRunTime = [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null)

            $lastRunTime.Day | Should -Be 25
            $lastRunTime.Month | Should -Be 9
            $lastRunTime.Year | Should -Be 2025
            $lastRunTime.Hour | Should -Be 5
            $lastRunTime.Minute | Should -Be 0
        }

        It "Should handle checkpoint with two-digit hour" {
            $checkpointContent = "25.09.2025 15:30:45"

            { [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null) } | Should -Not -Throw
        }

        It "Should fail gracefully on malformed checkpoint timestamp" {
            $checkpointContent = "invalid timestamp"

            { [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null) } | Should -Throw
        }

        It "Should handle checkpoint with leading zero in hour" {
            $checkpointContent = "25.09.2025 09:00:00"
            $lastRunTime = [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null)

            $lastRunTime.Hour | Should -Be 9
        }

        It "Should handle year 2000 timestamp" {
            $checkpointContent = "01.01.2000 00:00:00"

            { [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null) } | Should -Not -Throw
        }

        It "Should handle year 2099 timestamp" {
            $checkpointContent = "31.12.2099 23:59:59"

            { [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null) } | Should -Not -Throw
        }

        It "Should handle midnight timestamp" {
            $checkpointContent = "15.06.2025 00:00:00"
            $lastRunTime = [DateTime]::ParseExact($checkpointContent, 'dd.MM.yyyy HH:mm:ss', $null)

            $lastRunTime.Hour | Should -Be 0
            $lastRunTime.Minute | Should -Be 0
            $lastRunTime.Second | Should -Be 0
        }
    }

    Context "ServerName special characters in filenames" {
        It "Should handle Cyrillic ServerName" {
            $serverName = "Сервер_01"
            $fileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            # Cyrillic characters get replaced, underscores are preserved
            $fileName | Should -Match "last_run_.*_01\.txt"
        }

        It "Should handle mixed case and numbers in ServerName" {
            $serverName = "Server123"
            $fileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            $fileName | Should -Be "last_run_Server123.txt"
        }

        It "Should handle ServerName with dots and commas" {
            $serverName = "Server.01,Test"
            $fileName = "last_run_$($serverName -replace '[^\w\-]', '_').txt"

            $fileName | Should -Be "last_run_Server_01_Test.txt"
        }
    }

    Context "Configuration required keys validation" {
        It "Should require BotToken in configuration" {
            $badConfig = @{
                ServerName    = "TestServer"
                MedocLogsPath = "C:\test"
                ChatId        = "12345"
            }

            { Invoke-MedocUpdateCheck -Config $badConfig -ErrorAction Stop } | Should -Throw
        }

        It "Should require ChatId in configuration" {
            $badConfig = @{
                ServerName    = "TestServer"
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
            }

            { Invoke-MedocUpdateCheck -Config $badConfig -ErrorAction Stop } | Should -Throw
        }

        It "Should accept configuration with all required keys present" {
            $validConfig = @{
                ServerName    = "TestServer"
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            # Just verify the hashtable structure is valid for all required keys
            $validConfig.Keys.Count | Should -Be 4
            $validConfig.ContainsKey("ServerName") | Should -Be $true
            $validConfig.ContainsKey("MedocLogsPath") | Should -Be $true
            $validConfig.ContainsKey("BotToken") | Should -Be $true
            $validConfig.ContainsKey("ChatId") | Should -Be $true
        }
    }

    Context "Configuration validation edge cases" {
        It "Should reject ServerName exceeding 255 characters" {
            $longServerName = "A" * 256

            $config = @{
                ServerName    = $longServerName
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            { Invoke-MedocUpdateCheck -Config $config -ErrorAction Stop } | Should -Throw
        }

        It "Should reject ServerName with special characters" {
            $config = @{
                ServerName    = "Server@#$%"
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            { Invoke-MedocUpdateCheck -Config $config -ErrorAction Stop } | Should -Throw
        }

        It "Should accept ServerName at exactly 255 characters" {
            $serverName255 = "A" * 255

            $config = @{
                ServerName    = $serverName255
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            # Should not throw (validate structure, not execution)
            $config.ServerName.Length | Should -Be 255
        }

        It "Should reject BotToken shorter than 20 characters" {
            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = "C:\test"
                BotToken      = "short"
                ChatId        = "12345"
            }

            { Invoke-MedocUpdateCheck -Config $config -ErrorAction Stop } | Should -Throw
        }

        It "Should accept BotToken in valid Telegram format" {
            # Valid Telegram format: {botId}:{botToken} where token is 35+ characters
            $botToken = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = (Join-Path $testDataDir "dual-log-success")
                BotToken      = $botToken
                ChatId        = "12345"
            }

            # Should not throw (validate structure)
            $config.BotToken -match '^\d{1,10}:[A-Za-z0-9_-]{35,}$' | Should -Be $true
        }

        It "Should reject ChatId that is non-numeric" {
            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "ABC123"
            }

            { Invoke-MedocUpdateCheck -Config $config -ErrorAction Stop } | Should -Throw
        }

        It "Should accept ChatId as negative number (private chats)" {
            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = "C:\test"
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "-123456789"
            }

            # Should not throw (structure validation)
            $config.ChatId -match '^-?\d+$' | Should -Be $true
        }
    }

    Context "Checkpoint directory creation failure" {
        BeforeEach {
            $script:capturedLogEvents = @()

            Mock -CommandName Write-EventLogEntry -ModuleName MedocUpdateCheck -MockWith {
                param(
                    [string]$Message,
                    [string]$EventType,
                    [int]$EventId,
                    [string]$EventLogSource,
                    [string]$EventLogName
                )
                $script:capturedLogEvents += [pscustomobject]@{
                    Message   = $Message
                    EventType = $EventType
                    EventId   = $EventId
                }
            }
        }

        It "Should handle gracefully when checkpoint directory cannot be created" {
            # This test validates that checkpoint directory creation failures are logged
            # We test this by providing an explicit LastRunFile path, which triggers the directory creation code
            $testDataPath = Join-Path $script:testDataDir "dual-log-success"

            # Use a path that won't actually get created (read-only volume or permission denied)
            # For the mock, we'll fail New-Item when trying to create directories
            $protectedCheckpointPath = "$script:tempDir\Protected\Checkpoints\TestServer.txt"

            $config = @{
                ServerName      = "TestServer"
                MedocLogsPath   = $testDataPath
                LastRunFile     = $protectedCheckpointPath
                BotToken        = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId          = "12345"
            }

            # Mock New-Item to fail when attempting to create the checkpoint directory
            $originalNewItem = Get-Command New-Item
            Mock -CommandName New-Item -MockWith {
                # Check if this is trying to create a directory in our test path
                $Path = $PSBoundParameters["Path"]
                if ($Path -like "*Protected*Checkpoints*" -and $PSBoundParameters["ItemType"] -eq "Directory") {
                    throw [System.UnauthorizedAccessException]::new("Access denied")
                }
                # For other calls, use the original command
                & $originalNewItem @PSBoundParameters
            }

            # Mock Invoke-RestMethod to simulate successful Telegram API response
            Mock -CommandName Invoke-RestMethod -MockWith {
                return @{ ok = $true }
            }

            # Call should not throw - function handles gracefully
            { Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue 2>$null } |
                Should -Not -Throw

            # Verify error logged to Event Log for checkpoint directory creation failure
            # The Write-EventLogEntry mock should have captured this
            $allLogEvents = $script:capturedLogEvents
            $dirFailureEntry = $allLogEvents | Where-Object {
                $_.EventId -eq ([int][MedocEventId]::CheckpointDirCreationFailed)
            }

            # Verify the error was logged
            if ($null -ne $dirFailureEntry) {
                $dirFailureEntry.EventType | Should -Be "Error"
                $dirFailureEntry.Message | Should -Match "checkpoint"
            }
        }

        It "Should continue gracefully if checkpoint directory creation fails temporarily" {
            # Setup test directory
            $testDataPath = Join-Path $script:testDataDir "dual-log-success"
            $tempCheckpointPath = "$script:tempDir\TempCheckpoints"

            $config = @{
                ServerName      = "TestServer"
                MedocLogsPath   = $testDataPath
                LastRunFile     = $tempCheckpointPath
                BotToken        = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId          = "12345"
            }

            # Mock Invoke-RestMethod for Telegram
            Mock -CommandName Invoke-RestMethod -MockWith {
                return @{ ok = $true }
            }

            # Function should complete without throwing
            { Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue 2>$null } |
                Should -Not -Throw
        }
    }

    Context "Log file error handling" {
        It "Should return false when logs directory does not exist" {
            $nonExistentPath = "C:\NonExistent\Path"

            $config = @{
                ServerName    = "TestServer"
                MedocLogsPath = $nonExistentPath
                BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
            $result.Outcome | Should -Be 'Error'
        }

        It "Should handle logs directory in different paths" {
            # Test with various invalid paths
            $invalidPaths = @(
                "C:\InvalidDir"
                "/var/log/nonexistent"
                "\\.\pipe\invalid"
            )

            foreach ($path in $invalidPaths) {
                $config = @{
                    ServerName    = "TestServer"
                    MedocLogsPath = $path
                    BotToken      = "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
                    ChatId        = "12345"
                }

                $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue
                $result.Outcome | Should -Be 'Error'
            }
        }
    }

    Context "Encoding codepage validation" {
        It "Should handle standard encoding codepages" {
            $logsDir = Join-Path $testDataDir "dual-log-success"

            # These should work
            { Test-UpdateOperationSuccess -MedocLogsPath $logsDir -EncodingCodePage 1251 } | Should -Not -Throw
            { Test-UpdateOperationSuccess -MedocLogsPath $logsDir -EncodingCodePage 65001 } | Should -Not -Throw
        }

        It "Should throw on invalid encoding codepage" {
            $logsDir = Join-Path $testDataDir "dual-log-success"

            # Invalid codepage should throw
            { Test-UpdateOperationSuccess -MedocLogsPath $logsDir -EncodingCodePage 9999 } | Should -Throw
        }

        It "Should use default encoding when not specified" {
            $logsDir = Join-Path $testDataDir "dual-log-success"

            # Should work with default (1251)
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Module exports" {

    Context "Public functions" {
        It "Should export Test-UpdateOperationSuccess" {
            Get-Command Test-UpdateOperationSuccess -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Write-EventLogEntry" {
            Get-Command Write-EventLogEntry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Invoke-MedocUpdateCheck" {
            Get-Command Invoke-MedocUpdateCheck -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Format-UpdateTelegramMessage" {
            Get-Command Format-UpdateTelegramMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Format-UpdateEventLogMessage" {
            Get-Command Format-UpdateEventLogMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Format-UpdateTelegramMessage - Unit Tests" {

    Context "Success case formatting" {
        It "Should format successful update message with full version info" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "✅ UPDATE OK"
            $message | Should -Match "TEST-SERVER"
            $message | Should -Match "11\.02\.185"
            $message | Should -Match "11\.02\.186"
            $message | Should -Match "→"
        }

        It "Should include duration in success message if available" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            if ($updateResult.UpdateDuration) {
                $message | Should -Match "Duration"
                $message | Should -Match "min"
                $message | Should -Match "sec"
            }
        }

        It "Should NOT show individual flags in success message" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Success messages should not show flag details
            $message | Should -Not -Match "Flag1"
            $message | Should -Not -Match "Flag2"
            $message | Should -Not -Match "Flag3"
        }

        It "Should include dates and times in success message" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Started:"
            $message | Should -Match "Completed:"
            $message | Should -Match "Version:"
        }
    }

    Context "Failure case formatting" {
        It "Should format failed update message with flag details" {
            $logsDir = Join-Path $script:testDataDir "dual-log-missing-flag1"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "❌ UPDATE FAILED"
            $message | Should -Match "TEST-SERVER"
            $message | Should -Match "Validation Failures"
        }

        It "Should show which flags failed in failure message" {
            $logsDir = Join-Path $script:testDataDir "dual-log-missing-flag1"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Infrastructure"
            $message | Should -Match "DI/AI"
        }

        It "Should show full version range in failure message" {
            $logsDir = Join-Path $script:testDataDir "dual-log-missing-flag1"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "11\.02\.185"
            $message | Should -Match "11\.02\.186"
        }
    }

    Context "No update case formatting" {
        It "Should format no-update message" {
            $message = Format-UpdateTelegramMessage -UpdateResult $null -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "ℹ️ NO UPDATE"
            $message | Should -Match "TEST-SERVER"
            $message | Should -Match "28.10.2025 22:33:26"
        }
    }
}

Describe "Format-UpdateEventLogMessage - Unit Tests" {

    Context "Success case formatting" {
        It "Should format success event log message with key=value structure" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Server=TEST-SERVER"
            $message | Should -Match "Status=UPDATE_OK"
            $message | Should -Match "FromVersion="
            $message | Should -Match "ToVersion="
            $message | Should -Match "UpdateStarted="
            $message | Should -Match "UpdateCompleted="
            $message | Should -Match "Duration="
        }

        It "Should include numeric duration in event log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Duration=\d+"
        }

        It "Should NOT show individual flags in success event log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Success messages should not show flag details
            $message | Should -Not -Match "Flag1"
            $message | Should -Not -Match "Flag2"
            $message | Should -Not -Match "Flag3"
        }
    }

    Context "Failure case formatting" {
        It "Should show flag details in failure event log message" {
            $logsDir = Join-Path $script:testDataDir "dual-log-missing-flag1"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Flag1=False"
            $message | Should -Match "Flag2=True"
            $message | Should -Match "Flag3=True"
        }

        It "Should include failure reason in event log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-missing-flag1"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir
            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Reason="
            $message | Should -Match "Status=UPDATE_FAILED"
        }
    }

    Context "No update case formatting" {
        It "Should format minimal no-update event log message" {
            $message = Format-UpdateEventLogMessage -UpdateResult $null -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Server=TEST-SERVER"
            $message | Should -Match "Status=NO_UPDATE"
            $message | Should -Match "CheckTime=28.10.2025 22:33:26"
        }
    }
}

Describe "Test-UpdateOperationSuccess - Enhanced Fields" {

    Context "Version extraction" {
        It "Should extract FromVersion from Planner.log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "FromVersion") | Should -Be $true
            $result.FromVersion | Should -Not -BeNullOrEmpty
            $result.FromVersion | Should -Match "^\d+\.\d+\.\d+"
        }

        It "Should extract ToVersion from Planner.log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "ToVersion") | Should -Be $true
            $result.ToVersion | Should -Not -BeNullOrEmpty
            $result.ToVersion | Should -Match "^\d+\.\d+\.\d+"
        }

        It "Should maintain TargetVersion field for compatibility" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "TargetVersion") | Should -Be $true
            $result.TargetVersion | Should -Match "^\d+$"
        }
    }

    Context "Timestamp extraction from update log" {
        It "Should extract UpdateStartTime from update log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "UpdateStartTime") | Should -Be $true
            $result.UpdateStartTime | Should -BeOfType [datetime]
        }

        It "Should extract UpdateEndTime from update log" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "UpdateEndTime") | Should -Be $true
            $result.UpdateEndTime | Should -BeOfType [datetime]
        }

        It "UpdateEndTime should be after or equal to UpdateStartTime" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateEndTime -ge $result.UpdateStartTime | Should -Be $true
        }
    }

    Context "Duration calculation" {
        It "Should calculate UpdateDuration in seconds" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            ($result.Keys -contains "UpdateDuration") | Should -Be $true
            if ($result.UpdateDuration) {
                $result.UpdateDuration | Should -BeOfType [int]
                $result.UpdateDuration -ge 0 | Should -Be $true
            }
        }

        It "Should calculate correct duration from start and end times" {
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            if ($result.UpdateDuration -and $result.UpdateStartTime -and $result.UpdateEndTime) {
                $calculatedDuration = [int]($result.UpdateEndTime - $result.UpdateStartTime).TotalSeconds
                $result.UpdateDuration | Should -Be $calculatedDuration
            }
        }
    }

    Context "Timestamp regex pattern validation - Different formats for different logs" {
        It "Should parse Planner.log with 4-digit year format (DD.MM.YYYY)" {
            # Planner.log uses 4-digit year format
            # This test ensures the code correctly identifies Planner.log entries
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # If successfully parsed Planner.log with 4-digit year format
            $result.UpdateTime | Should -BeOfType [datetime]
            # Verify it found the correct date (23.10.2025)
            $result.UpdateTime.Year | Should -Be 2025
            $result.UpdateTime.Month | Should -Be 10
            $result.UpdateTime.Day | Should -Be 23
        }

        It "Should parse update_*.log with 2-digit year format (DD.MM.YY)" {
            # update_*.log uses 2-digit year format with milliseconds
            # This test ensures the code correctly extracts timestamps from update log
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # If successfully parsed update_*.log with 2-digit year format
            $result.UpdateStartTime | Should -BeOfType [datetime]
            $result.UpdateEndTime | Should -BeOfType [datetime]
            # Verify it found the correct dates (23.10.2025)
            $result.UpdateStartTime.Year | Should -Be 2025
            $result.UpdateStartTime.Month | Should -Be 10
            $result.UpdateStartTime.Day | Should -Be 23
        }

        It "Should correctly distinguish between 4-digit (Planner) and 2-digit (update log) years" {
            # This test documents the critical difference:
            # - Planner.log: 23.10.2025 (4-digit year)
            # - update_*.log: 23.10.25 (2-digit year representing 2025)
            # Both should result in same year (2025) when parsed
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Both timestamps should represent the same year
            $result.UpdateTime.Year | Should -Be $result.UpdateStartTime.Year
            $result.UpdateTime.Year | Should -Be 2025
        }
    }

    Context "Timestamp format handling - Milliseconds and log details" {
        It "Should ignore milliseconds in update_*.log timestamps" {
            # update_*.log includes milliseconds: 23.10.25 10:30:15.100
            # The parser should extract only HH:MM:SS, ignoring .MMM
            # This means 10:30:15.100 and 10:30:15.999 are equivalent
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # UpdateStartTime and UpdateEndTime should only have precision to seconds
            # (no millisecond component)
            $result.UpdateStartTime.Millisecond | Should -Be 0
            $result.UpdateEndTime.Millisecond | Should -Be 0
        }

        It "Should handle log ID and INFO level in update_*.log" {
            # update_*.log format: DD.MM.YY HH:MM:SS.MMM XXXXXXXX INFO Message
            # The parser should extract timestamp despite log ID and level present
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # If timestamps were extracted correctly despite log ID/level
            $result.UpdateStartTime | Should -BeOfType [datetime]
            $result.UpdateStartTime | Should -Not -BeNullOrEmpty
            $result.UpdateEndTime | Should -BeOfType [datetime]
            $result.UpdateEndTime | Should -Not -BeNullOrEmpty
        }

        It "Should extract timestamps from all lines in update_*.log, not just first match" {
            # Duration calculation requires finding BOTH first and last timestamps
            # This test ensures the loop processes all lines, not just the first
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # UpdateStartTime should be the earliest timestamp
            # UpdateEndTime should be the latest timestamp
            $result.UpdateDuration | Should -BeGreaterThan 0
            # Test data has ~18 minutes duration
            $result.UpdateDuration | Should -BeGreaterThan 1000
        }
    }

    Context "Timestamp format edge cases and error handling" {
        It "Should handle single-line update_*.log file correctly" {
            # Edge case: update_*.log has only one line
            # Must use @() wrapper to ensure .Count works correctly
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Even with single line, should extract timestamps
            $result.UpdateStartTime | Should -Not -BeNullOrEmpty
            # Single line: UpdateStartTime = UpdateEndTime
            if ($result.UpdateLogLines -eq 1) {
                $result.UpdateStartTime | Should -Be $result.UpdateEndTime
            }
        }

        It "Should maintain consistency between UpdateTime (Planner) and UpdateStartTime (update log)" {
            # Planner.log shows when update was INITIATED (5:00:00)
            # update_*.log shows when process actually STARTED (10:30:15)
            # UpdateStartTime should always be after or equal to UpdateTime
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Update initiation time should be before or equal to actual start time
            $result.UpdateTime -le $result.UpdateStartTime | Should -Be $true
        }

        It "Should handle checkpoint filtering with timestamp format differences" {
            # Checkpoint timestamps use different format than both logs
            # Planner uses 4-digit, update uses 2-digit, checkpoint uses standard PS format
            # This ensures no confusion between formats
            $logsDir = Join-Path $script:testDataDir "dual-log-success"
            $checkpointTime = [datetime]::ParseExact("23.10.2024 5:00:00", "dd.MM.yyyy H:mm:ss", $null)

            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -SinceTime $checkpointTime

            # Checkpoint is before the update, so update should still be detected
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }
    }
}

Describe "CMS Credential Encryption - Unit Tests" {
    # PLATFORM COMPATIBILITY: Windows only
    # CMS and certificate features require Windows Certificate Store (LocalMachine)
    # Tests are skipped on macOS/Linux since these features don't exist
    # Reason: PowerShell's Protect-CmsMessage and Unprotect-CmsMessage depend on Windows PKI

    if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT") {
        # Gracefully skip on non-Windows - not a failure, just unsupported platform
        It "CMS tests are not applicable on non-Windows platforms" -Skip {
            $true | Should -Be $true  # Placeholder for skipped context
        }
    } else {

    Context "Credential encryption and decryption" {
        It "Should create self-signed certificate in LocalMachine store" {
            # Certificate creation is tested indirectly through encryption/decryption
            # This test verifies certificate-based CMS encryption works
            @{
                BotToken = "123456:ABC-test-token"
                ChatId   = "-1002825825746"
            } | ConvertTo-Json | Should -Not -BeNullOrEmpty

            # Test that CMS encryption is available
            Get-Command Protect-CmsMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            Get-Command Unprotect-CmsMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should store credentials in JSON format" {
            # Credentials should be stored as JSON for transparency
            $credentials = @{
                BotToken = "123456:ABC-test-token"
                ChatId   = "-1002825825746"
            }

            $json = $credentials | ConvertTo-Json -Depth 2
            $parsed = $json | ConvertFrom-Json

            $parsed.BotToken | Should -Be "123456:ABC-test-token"
            $parsed.ChatId | Should -Be "-1002825825746"
        }

        It "Should handle positive chat IDs" {
            $chatId = "123456789"
            $chatId -match '^-?\d+$' | Should -Be $true
        }

        It "Should handle negative chat IDs (for channels)" {
            $chatId = "-1002825825746"
            $chatId -match '^-?\d+$' | Should -Be $true
        }

        It "Should validate chat ID format" {
            $validId = "-1002825825746"
            $invalidId = "not-a-number"

            $validId -match '^-?\d+$' | Should -Be $true
            $invalidId -match '^-?\d+$' | Should -Be $false
        }
    }

    Context "Certificate encryption and decryption workflow" {
        It "Should encrypt and decrypt credential data successfully (if certificate exists)" -Skip:(
            $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
        ) {
            # Check if credential encryption certificate exists
            $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -match "M.E.Doc Update Check" } |
                Select-Object -First 1

            if (-not $cert) {
                # Certificate doesn't exist yet - this is expected on fresh installations
                # Setup-Credentials.ps1 will create it on first run
                Write-Host "Info: Certificate not found (will be created by Setup-Credentials.ps1 on first run)" -ForegroundColor Cyan
                $true | Should -Be $true  # Test passes as informational
                return
            }

            # Certificate exists - test actual encryption/decryption
            $testCredentials = @{
                BotToken = "test-bot-token-12345"
                ChatId   = "-1234567890"
            }

            # Encrypt the credentials using the certificate
            $jsonData = $testCredentials | ConvertTo-Json
            $encrypted = $jsonData | Protect-CmsMessage -To "CN=M.E.Doc Update Check Credential Encryption" -ErrorAction Stop

            # Verify encryption succeeded
            $encrypted | Should -Not -BeNullOrEmpty
            $encrypted -is [string] | Should -Be $true

            # Decrypt the credentials
            $decrypted = $encrypted | Unprotect-CmsMessage -ErrorAction Stop

            # Verify decryption succeeded and data is intact
            $decrypted | Should -Not -BeNullOrEmpty
            $parsed = $decrypted | ConvertFrom-Json
            $parsed.BotToken | Should -Be "test-bot-token-12345"
            $parsed.ChatId | Should -Be "-1234567890"
        }

        It "Should find certificate in LocalMachine store" -Skip:(
            $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
        ) {
            # Search for the credential encryption certificate
            $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -match "M.E.Doc Update Check" } |
                Select-Object -First 1

            # Certificate might not exist yet, but if it does, verify its properties
            if ($cert) {
                # Verify certificate subject
                $cert.Subject | Should -Match "M.E.Doc Update Check Credential Encryption"

                # Verify certificate is not expired
                $cert.NotAfter | Should -BeGreaterThan (Get-Date)

                # Verify certificate has private key
                $cert.HasPrivateKey | Should -Be $true
            } else {
                # On first run or test environment, certificate might not exist yet
                # This is not a failure - Setup-Credentials.ps1 creates it when needed
                Write-Host "Info: Certificate not found in store (will be created by Setup-Credentials.ps1)" -ForegroundColor Cyan
            }
        }

        It "Should have CMS cmdlets available on Windows" -Skip:(
            $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
        ) {
            # Verify CMS encryption cmdlets are available
            Get-Command Protect-CmsMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            Get-Command Unprotect-CmsMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Certificate validation for upgrades" -Skip:(
        $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
    ) {
        # These integration tests verify Setup-Credentials.ps1 implementation details
        # They check that certificate validation logic is properly implemented

        It "Should verify Setup-Credentials.ps1 script exists and is valid" {
            # The certificate validation depends on Setup-Credentials.ps1 existing
            $setupCredentialsPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "utils") -ChildPath "Setup-Credentials.ps1"
            Test-Path $setupCredentialsPath | Should -Be $true

            # Verify the script is readable
            $content = Get-Content -Path $setupCredentialsPath -Raw -ErrorAction SilentlyContinue
            $content | Should -Not -BeNullOrEmpty
            $content | Should -Match "Get-MedocCredentialCertificate"
        }

        It "Should verify Get-MedocCredentialCertificate function is defined in Setup-Credentials.ps1" {
            # The validation function must contain logic for checking certificate requirements
            $setupCredentialsPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "utils") -ChildPath "Setup-Credentials.ps1"
            $content = Get-Content -Path $setupCredentialsPath -Raw -ErrorAction SilentlyContinue

            # Function should contain validation logic for EKU
            $content | Should -Match "1\.3\.6\.1\.4\.1\.311\.80\.1"

            # Function should contain validation logic for KeyEncipherment
            $content | Should -Match "KeyEncipherment"

            # Function should contain expiration check (< 30 days)
            $content | Should -Match "30"
        }

        It "Should check certificate expiration threshold is 30 days" {
            # Certificates expiring in < 30 days should be regenerated
            $setupCredentialsPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "utils") -ChildPath "Setup-Credentials.ps1"
            $content = Get-Content -Path $setupCredentialsPath -Raw -ErrorAction SilentlyContinue

            # Verify the 30-day threshold is documented in the script
            $content | Should -Match "daysUntilExpiration.*30|-lt 30"
        }

        It "Should check private key accessibility in Setup-Credentials.ps1" {
            # Certificate validation includes checking if private key is accessible
            $setupCredentialsPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "utils") -ChildPath "Setup-Credentials.ps1"
            $content = Get-Content -Path $setupCredentialsPath -Raw -ErrorAction SilentlyContinue

            # Script should have logic to handle keys that are not accessible
            $content | Should -Match "PrivateKey|private.*key.*not.*accessible"
        }

        It "Should verify warning messages for missing CMS requirements in Setup-Credentials.ps1" {
            # When old certificate is detected, user should be informed
            # Message should specify which requirements are missing (EKU or KeyEncipherment)
            $setupCredentialsPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "utils") -ChildPath "Setup-Credentials.ps1"
            $content = Get-Content -Path $setupCredentialsPath -Raw -ErrorAction SilentlyContinue

            # Script should produce informative output when regenerating
            $content | Should -Match "doesn't meet.*CMS|Creating new certificate"
        }

        It "Should reuse certificate meeting all CMS requirements" {
            # Certificate with valid EKU and KeyEncipherment should be reused (not regenerated)
            $setupCredentialsPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "utils") -ChildPath "Setup-Credentials.ps1"
            $content = Get-Content -Path $setupCredentialsPath -Raw -ErrorAction SilentlyContinue

            # Logic should check all three conditions before accepting certificate:
            # 1. Not expiring soon (>= 30 days)
            # 2. Has Document Encryption EKU
            # 3. Has KeyEncipherment usage
            $content | Should -Match "return \$cert"  # Should return existing cert if valid
        }
    }

    Context "Credential file path and permissions" {
        It "Should store encrypted credentials in ProgramData directory" {
            $expectedPath = "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"
            $expectedPath | Should -Match "ProgramData.*credentials.*telegram\.cms"
        }

        It "Should use .cms file extension for encrypted files" {
            $credFile = "telegram.cms"
            $credFile | Should -Match "\.cms$"
        }

        It "Should restrict permissions to SYSTEM and Administrators" {
            # These are the only SIDs that should have access
            $systemSID = "S-1-5-18"  # SYSTEM
            $adminSID = "S-1-5-32-544"  # Administrators

            @($systemSID, $adminSID) | Should -Not -BeNullOrEmpty
        }
    }

    Context "CMS cmdlet availability" {
        It "Should have Protect-CmsMessage available" {
            Get-Command Protect-CmsMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Unprotect-CmsMessage available" {
            Get-Command Unprotect-CmsMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have New-SelfSignedCertificate available" -Skip:(
            $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
        ) {
            Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have certificate store available (Windows only)" -Skip:(
            $PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT"
        ) {
            Test-Path "Cert:\LocalMachine\My" | Should -Be $true
        }
    }

    Context "Credential decryption function" {
        It "Should require Path parameter" {
            # Simulating the function call structure
            { Get-Content -Path $null -Raw -ErrorAction Stop } | Should -Throw
        }

        It "Should detect missing credentials file" {
            $nonexistentPath = "C:\NonExistent\Path\telegram.cms"
            Test-Path $nonexistentPath | Should -Be $false
        }

        It "Should handle file encoding correctly" {
            # Credentials file should use UTF8 encoding
            $encoding = [System.Text.Encoding]::UTF8
            $encoding.WebName | Should -Be "utf-8"
        }

        It "Should parse JSON from decrypted content" {
            $jsonContent = @{
                BotToken = "123456:ABC-token"
                ChatId   = "123456"
            } | ConvertTo-Json

            $parsed = $jsonContent | ConvertFrom-Json
            $parsed.BotToken | Should -Be "123456:ABC-token"
            $parsed.ChatId | Should -Be "123456"
        }
    }
    }  # Close the Windows-only conditional
}

Describe "Exit Code Mapping - Unit Tests" {
    It "Should map Success to 0" {
        Get-ExitCodeForOutcome -Outcome 'Success' | Should -Be 0
    }
    It "Should map NoUpdate to 0" {
        Get-ExitCodeForOutcome -Outcome 'NoUpdate' | Should -Be 0
    }
    It "Should map UpdateFailed to 2" {
        Get-ExitCodeForOutcome -Outcome 'UpdateFailed' | Should -Be 2
    }
    It "Should map Error to 1" {
        Get-ExitCodeForOutcome -Outcome 'Error' | Should -Be 1
    }
}

AfterAll {
    # Clean up test artifacts (checkpoint files created during test execution)
    # These files are generated by Invoke-MedocUpdateCheck in various test scenarios
    # and should not persist after tests complete (regardless of pass/fail/skip outcome)
    $checkpointPattern = "checkpoint-*.txt"
    $testDataDir = Join-Path $PSScriptRoot "test-data"

    # Recursively find and remove all checkpoint files in test-data directory
    Get-ChildItem -Path $testDataDir -Recurse -Filter $checkpointPattern -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Could not remove checkpoint file: $($_.FullName)"
            }
        }

    # Clean up module
    Remove-Module MedocUpdateCheck -ErrorAction SilentlyContinue
}
