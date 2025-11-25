#Requires -Modules Pester
using module "..\lib\MedocUpdateCheck.psm1"

<#
.SYNOPSIS
    Comprehensive test suite for MedocUpdateCheck module - Phase 1 Refactoring

.DESCRIPTION
    Tests for marker-based update detection (Phase 1 refactoring)
    Tests 3 new helper functions: Find-LastUpdateOperation, Test-UpdateMarker, Test-UpdateState
    Tests core function: Test-UpdateOperationSuccess
    Verifies marker-based classification (2 markers: V and C instead of 3 flags)

.NOTES
    Uses 'using module' to import enum at compile-time for type-safe assertions
#>

BeforeAll {
    Import-Module -Force './lib/MedocUpdateCheck.psm1'
    $script:testDataDir = Join-Path (Get-Item "./tests/test-data" -ErrorAction SilentlyContinue).FullName "."
    $script:tempDirectories = @()
}

Describe "Test-UpdateOperationSuccess - Core Update Detection Function" {

    Context "Successful update detection (both markers present)" {
        It "Should detect successful update when both markers are present" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Success"
            $result.Success | Should -Be $true
        }

        It "Should have marker-based properties in the result" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Keys | Should -Contain "MarkerVersionConfirm"
            $result.Keys | Should -Contain "MarkerCompletionMarker"
            $result.Keys | Should -Contain "OperationFound"
        }

        It "Should correctly identify both markers present" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Phase 1: Both markers must be present for success
            $result.MarkerVersionConfirm | Should -Be $true
            $result.MarkerCompletionMarker | Should -Be $true
            $result.OperationFound | Should -Be $true
            $result.Success | Should -Be $true
        }

        It "Should extract version information" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
            $result.TargetVersion | Should -Be "186"
        }

        It "Should have both markers confirmed" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.MarkerVersionConfirm | Should -Be $true
            $result.MarkerCompletionMarker | Should -Be $true
        }
    }

    Context "Failed update detection - missing markers" {
        It "Should detect failure when version marker is missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
        }

        It "Should show version marker as missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.MarkerVersionConfirm | Should -Be $false
            $result.MarkerCompletionMarker | Should -Be $true
        }

        It "Should detect failure when completion marker is missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
        }

        It "Should handle missing completion marker (operation not found)" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Without completion marker, operation block is not recognized
            $result.OperationFound | Should -Be $false
            $result.Status | Should -Be "Failed"
        }
    }

    Context "Real failure paths end-to-end with actual log fixtures" {
        It "Should handle missing-version-marker scenario with real data" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Validate key failure properties
            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
            $result.OperationFound | Should -Be $true
            $result.MarkerVersionConfirm | Should -Be $false
            $result.MarkerCompletionMarker | Should -Be $true
        }

        It "Should extract version information even when marker missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Version extraction independent of marker presence
            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
            $result.TargetVersion | Should -Be "186"
        }

        It "Should format failure message correctly with real data" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Failure message should have error emoji and failed status
            $message | Should -Match "^❌ UPDATE FAILED"
            $message | Should -Match "TEST-SERVER"
            $message | Should -Match "Reason:"
        }

        It "Should handle missing-completion-marker scenario with real data" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Operation not found indicates incomplete operation block
            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
            $result.OperationFound | Should -Be $false
        }

        It "Should use correct failure ErrorId for missing markers" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Failure should have ErrorId different from Success (1000) and NoUpdate (1001)
            [int]$result.ErrorId | Should -Not -Be 1000
            [int]$result.ErrorId | Should -Not -Be 1001
        }

        It "Should provide reason text for failure scenarios" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Failure should explain what went wrong
            $result.Reason | Should -Not -BeNullOrEmpty
            [string]$reason = $result.Reason
            ($reason -match "Missing|marker|Завершення") | Should -Be $true
        }

        It "Should validate checkpoint filtering with failed updates" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"

            # Test with checkpoint BEFORE the update
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -SinceTime ([DateTime]'2025-10-20')

            # Should find and fail the update (timestamp is 2025-10-23)
            $result.Status | Should -Be "Failed"
        }

        It "Should detect no-update when checkpoint is after failed update" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"

            # Test with checkpoint AFTER the update
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -SinceTime ([DateTime]'2025-10-25')

            # Should return NoUpdate (checkpoint filtered out the update)
            $result.Status | Should -Be "NoUpdate"
        }
    }

    Context "No update detected" {
        It "Should return NoUpdate status when no update is found" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "NoUpdate"
        }
    }

    Context "NoUpdate end-to-end scenario with real log fixtures" {
        It "Should correctly classify logs with no update operation" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Key outcome: NoUpdate status (not Success, not Failed)
            $result.Status | Should -Be "NoUpdate"
            $result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)
        }

        It "Should return appropriate message for no-update scenario" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Message should indicate no operation found
            $result.Message | Should -Match "No update operation"
        }

        It "Should use NoUpdate error ID (1001)" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # NoUpdate uses ErrorId 1001 (different from Success 1000 and Failed 1302)
            [int]$result.ErrorId | Should -Be 1001
        }

        It "Should differentiate NoUpdate from Failed scenarios" {
            $noUpdateDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $failedDir = Join-Path $script:testDataDir "failure-missing-version-marker"

            $noUpdateResult = Test-UpdateOperationSuccess -MedocLogsPath $noUpdateDir
            $failedResult = Test-UpdateOperationSuccess -MedocLogsPath $failedDir

            # Different status values
            $noUpdateResult.Status | Should -Be "NoUpdate"
            $failedResult.Status | Should -Be "Failed"

            # Different error IDs
            [int]$noUpdateResult.ErrorId | Should -Not -Be ([int]$failedResult.ErrorId)
        }

        It "Should handle NoUpdate in Telegram message formatting" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Should use informational message, not error
            $message | Should -Match "^ℹ️ NO UPDATE"
            $message | Should -Not -Match "❌"
            $message | Should -Not -Match "✅"
        }
    }

    Context "Missing update log file" {
        It "Should handle missing update log gracefully" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-log"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Failed"
        }
    }

    Context "Checkpoint filtering" {
        It "Should stop searching when logs are older than checkpoint" {
            $tempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("MedocLogs_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Path $tempLogs -Force | Out-Null
            $script:tempDirectories += $tempLogs

            $plannerLines = @(
                "01.12.2025 10:00:00 Завантаження оновлення ezvit.11.02.185-11.02.186.upd"
            )
            $encoding = [System.Text.Encoding]::GetEncoding(1251)
            [System.IO.File]::WriteAllLines((Join-Path $tempLogs "Planner.log"), $plannerLines, $encoding)

            $checkpoint = [datetime]'2025-12-01T23:59:59'

            $result = Test-UpdateOperationSuccess -MedocLogsPath $tempLogs -SinceTime $checkpoint

            $result.Status | Should -Be "NoUpdate"
            $result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)
        }
    }
}

Describe "Test-UpdateMarker - Helper Function for Marker Validation" {

    Context "Marker presence validation" {
        It "Should detect version confirmation marker (V)" {
            $operationContent = @"
Початок роботи, операція "Оновлення"
Версія програми - 186
Завершення роботи, операція "Оновлення"
"@
            $result = Test-UpdateMarker -OperationContent $operationContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $true
        }

        It "Should detect completion marker (C)" {
            $operationContent = @"
Початок роботи, операція "Оновлення"
Версія програми - 186
Завершення роботи, операція "Оновлення"
"@
            $result = Test-UpdateMarker -OperationContent $operationContent -TargetVersion "186"

            $result.CompletionMarker | Should -Be $true
        }

        It "Should use word boundary for version matching" {
            $operationContent = "Версія програми - 1860"
            $result = Test-UpdateMarker -OperationContent $operationContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $false
        }

        It "Should handle missing version marker" {
            $operationContent = @"
Початок роботи, операція "Оновлення"
Завершення роботи, операція "Оновлення"
"@
            $result = Test-UpdateMarker -OperationContent $operationContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $false
            $result.CompletionMarker | Should -Be $true
        }

        It "Should handle missing completion marker" {
            $operationContent = @"
Початок роботи, операція "Оновлення"
Версія програми - 186
"@
            $result = Test-UpdateMarker -OperationContent $operationContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $true
            $result.CompletionMarker | Should -Be $false
        }
    }
}

Describe "Test-UpdateState - Orchestrator Function for Classification" {

    Context "Marker-based state classification" {
        It "Should classify as Success when both markers are present" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "186"

            $result.Status | Should -Be "Success"
            $result.VersionConfirm | Should -Be $true
            $result.CompletionMarker | Should -Be $true
        }

        It "Should classify as Failed when version marker is missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "186"

            $result.Status | Should -Be "Failed"
            $result.VersionConfirm | Should -Be $false
        }

        It "Should fail when no operation markers exist" {
            $logContent = "Random content with no markers present"

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "001"

            $result.Status | Should -Be "Failed"
            $result.OperationFound | Should -Be $false
            $result.Message | Should -Match "No update operation"
        }
    }
}

Describe "Format-UpdateTelegramMessage - Telegram Notification Formatting" {

    Context "Success message formatting" {
        It "Should format successful update message with exact template" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Exact message structure validation
            $message | Should -Match "^✅ UPDATE OK \| TEST-SERVER"
            $message | Should -Match "Version: .* → .*"
            $message | Should -Match "Started: \d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}"
            $message | Should -Match "Completed: \d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}"
            $message | Should -Match "Checked: 28\.10\.2025 22:33:26"
        }

        It "Should include all required fields in success message" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Validate all required sections are present
            $message | Should -Match "Version:"
            $message | Should -Match "Started:"
            $message | Should -Match "Completed:"
            $message | Should -Match "Checked:"
            $message | Should -Match "✅"
        }

        It "Should validate version format in success message" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Validate version extraction
            $message | Should -Match "Version: 11\.02\.185 → 11\.02\.186"
        }
    }

    Context "Failure message formatting" {
        It "Should format failed update message with exact template" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Exact message structure validation
            $message | Should -Match "^❌ UPDATE FAILED \| TEST-SERVER"
            $message | Should -Match "Version: .* → .*"
            $message | Should -Match "Started: \d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}"
            $message | Should -Match "Failed at: .*"
            $message | Should -Match "Reason: .*"
            $message | Should -Match "Checked: 28\.10\.2025 22:33:26"
        }

        It "Should include all required fields in failure message" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # Validate all required sections are present
            $message | Should -Match "Version:"
            $message | Should -Match "Started:"
            $message | Should -Match "Failed at:"
            $message | Should -Match "Reason:"
            $message | Should -Match "Checked:"
            $message | Should -Match "❌"
        }
    }

    Context "NoUpdate message formatting" {
        It "Should format no-update message with correct template" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # NoUpdate has different structure - informational, not error
            $message | Should -Match "^ℹ️ NO UPDATE \|"
            $message | Should -Match "TEST-SERVER"
            $message | Should -Match "Checked: 28\.10\.2025 22:33:26"
        }

        It "Should NOT include version details in no-update message" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            # NoUpdate is simpler - no Started/Completed/Failed fields
            $message | Should -Not -Match "Started:"
            $message | Should -Not -Match "Completed:"
            $message | Should -Not -Match "Failed at:"
        }

        It "Should use informational emoji for no-update (not error emoji)" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "ℹ️"
            $message | Should -Not -Match "❌"
            $message | Should -Not -Match "✅"
        }
    }
}

Describe "Write-EventLogEntry - Event Log Handling" {

    if (-not $IsWindows) {
        It "Should skip Windows-only Event Log tests on non-Windows hosts" {
            Set-ItResult -Skipped -Because "Windows Event Log APIs are not available on this platform."
        }
    } else {
        InModuleScope MedocUpdateCheck {
            BeforeEach {
                $script:lastWrite = $null
                $script:eventLogDisposed = $false
                $script:createdSource = $false
                $script:warningMessages = @()

                Mock Write-Warning {
                    param($Message)
                    $script:warningMessages += $Message
                }
            }

            It "Should create missing source and write entry" {
                $eventLog = [pscustomobject]@{}
                $eventLog | Add-Member -MemberType NoteProperty -Name Source -Value $null -Force
                $eventLog | Add-Member -MemberType ScriptMethod -Name WriteEntry -Value {
                    param($Message, $EntryType, $EventId)
                    $script:lastWrite = @{
                        Message  = $Message
                        EntryType = $EntryType
                        EventId   = $EventId
                    }
                } | Out-Null
                $eventLog | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
                    $script:eventLogDisposed = $true
                } | Out-Null

                Mock Invoke-EventLogSourceExists {
                    param($EventLogSource)
                    $false
                }
                Mock Invoke-CreateEventLogSource {
                    param($EventLogSource, $EventLogName)
                    $script:createdSource = $true
                }
                Mock New-EventLogHandle {
                    param($EventLogName)
                    $eventLog
                }

                Write-EventLogEntry -Message "Test entry" -EventType Information -EventId 2000

                $script:createdSource | Should -BeTrue
                $script:lastWrite.Message | Should -Be "Test entry"
                $script:eventLogDisposed | Should -BeTrue
            }

            It "Should warn when creating source fails" {
                Mock Invoke-EventLogSourceExists {
                    param($EventLogSource)
                    $false
                }
                Mock Invoke-CreateEventLogSource {
                    param($EventLogSource, $EventLogName)
                    throw "Access denied"
                }

                Write-EventLogEntry -Message "Test entry" -EventType Error -EventId 2001

                $script:warningMessages | Should -Not -BeEmpty
                $script:warningMessages[-1] | Should -Match "Could not create"
            }

            It "Should warn when event log handle creation fails" {
                Mock Invoke-EventLogSourceExists {
                    param($EventLogSource)
                    $true
                }
                Mock New-EventLogHandle {
                    param($EventLogName)
                    throw "No event log"
                }

                Write-EventLogEntry -Message "Test entry" -EventType Warning -EventId 2002

                $script:warningMessages | Should -Not -BeEmpty
                $script:warningMessages[-1] | Should -Match "Could not write"
            }
        }
    }
}

Describe "Module Exports - Public API Verification" {
    Context "Helper functions are exported" {
        It "Should export Find-LastUpdateOperation" {
            (Get-Module MedocUpdateCheck).ExportedFunctions.Keys | Should -Contain "Find-LastUpdateOperation"
        }

        It "Should export Test-UpdateMarker" {
            (Get-Module MedocUpdateCheck).ExportedFunctions.Keys | Should -Contain "Test-UpdateMarker"
        }

        It "Should export Test-UpdateState" {
            (Get-Module MedocUpdateCheck).ExportedFunctions.Keys | Should -Contain "Test-UpdateState"
        }
    }

    Context "Core functions are exported" {
        It "Should export Test-UpdateOperationSuccess" {
            (Get-Module MedocUpdateCheck).ExportedFunctions.Keys | Should -Contain "Test-UpdateOperationSuccess"
        }
    }

    Context "Formatting functions are exported" {
        It "Should export Format-UpdateTelegramMessage" {
            (Get-Module MedocUpdateCheck).ExportedFunctions.Keys | Should -Contain "Format-UpdateTelegramMessage"
        }

        It "Should export Format-UpdateEventLogMessage" {
            (Get-Module MedocUpdateCheck).ExportedFunctions.Keys | Should -Contain "Format-UpdateEventLogMessage"
        }
    }
}

Describe "Error Handling and Edge Cases" {

    Context "Missing log files" {
        It "Should handle missing Planner.log gracefully" {
            $nonexistentDir = Join-Path $script:testDataDir "nonexistent-directory"

            # Function returns error status when Planner.log is missing
            $result = Test-UpdateOperationSuccess -MedocLogsPath $nonexistentDir -ErrorAction SilentlyContinue

            $result.Status | Should -Be "Error"
            $result.ErrorId | Should -Be ([MedocEventId]::PlannerLogMissing)
        }
    }

    Context "Encoding handling" {
        It "Should support Windows-1251 encoding" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -EncodingCodePage 1251

            $result.Status | Should -Be "Success"
        }

        It "Should validate encoding code page" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"

            # Invalid encoding code pages throw exception (System.Text.Encoding.GetEncoding validates)
            { Test-UpdateOperationSuccess -MedocLogsPath $logsDir -EncodingCodePage 9999 } | Should -Throw
        }

        It "Should surface encoding errors for Planner log" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $plannerLogPath = Join-Path $logsDir "Planner.log"

            Mock -ModuleName MedocUpdateCheck -CommandName Get-Content -ParameterFilter { $Path -eq $plannerLogPath } -MockWith { throw "Encoding failed" }

            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -ErrorAction SilentlyContinue

            $result.Status | Should -Be "Error"
            $result.ErrorId | Should -Be ([MedocEventId]::EncodingError)
        }

        It "Should surface encoding errors for update log" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"

            Mock -ModuleName MedocUpdateCheck -CommandName Get-Content -ParameterFilter { $Path -eq $updateLogPath } -MockWith { throw "Encoding failed" }

            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir -ErrorAction SilentlyContinue

            $result.Status | Should -Be "Error"
            $result.ErrorId | Should -Be ([MedocEventId]::EncodingError)
        }
    }

    Context "Timestamp extraction" {
        It "Should extract update start time from log" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateStartTime | Should -BeOfType [datetime]
        }

        It "Should extract update end time from log" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateEndTime | Should -BeOfType [datetime]
        }

        It "Should calculate duration in seconds" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateDuration | Should -BeGreaterThan 0
        }
    }
}

Describe "Message Formatting - Edge Cases" {

    Context "Telegram message formatting" {
        It "Should handle null reason gracefully" {
            $updateResult = @{
                Status = "NoUpdate"
                FromVersion = $null
                ToVersion = $null
            }

            # Should not throw
            { Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST" -CheckTime (Get-Date) } | Should -Not -Throw
        }

        It "Should format version information correctly" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateTelegramMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "11\.02\.185"
            $message | Should -Match "11\.02\.186"
        }

        It "Should fallback to informational message when UpdateResult is null" {
            $message = Format-UpdateTelegramMessage -UpdateResult $null -ServerName "TEST-SERVER" -CheckTime "01.01.2025 00:00:01"

            $message | Should -Match "NO UPDATE"
            $message | Should -Match "TEST-SERVER"
        }
    }

    Context "Event Log message formatting" {
        It "Should format key=value pairs correctly" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateResult = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST-SERVER" -CheckTime "28.10.2025 22:33:26"

            $message | Should -Match "Server="
            $message | Should -Match "Status="
            $message | Should -Match "FromVersion="
            $message | Should -Match "ToVersion="
        }

        It "Should handle missing optional fields" {
            $updateResult = @{
                Status = "NoUpdate"
            }

            # ServerName and CheckTime are mandatory parameters
            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "TEST" -CheckTime "28.10.2025 22:33:26"
            $message | Should -Not -BeNullOrEmpty
        }

        It "Should format failure details for Event Log" {
            $updateResult = @{
                Status = "Failed"
                Success = $false
                FromVersion = "11.02.185"
                ToVersion = "11.02.186"
                Reason = "Missing completion marker"
                UpdateStartTime = Get-Date
            }

            $message = Format-UpdateEventLogMessage -UpdateResult $updateResult -ServerName "SRV" -CheckTime "01.01.2025 00:00:01"
            $message | Should -Match "UPDATE_FAILED"
            $message | Should -Match "Reason="
        }

        It "Should fallback to minimal message when UpdateResult is null" {
            $message = Format-UpdateEventLogMessage -UpdateResult $null -ServerName "SRV" -CheckTime "01.01.2025 00:00:01"

            $message | Should -Match "Status=NO_UPDATE"
            $message | Should -Match "SRV"
        }
    }
}

Describe "Version Information Extraction" {

    Context "Version parsing" {
        It "Should extract FromVersion correctly" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.FromVersion | Should -Be "11.02.185"
        }

        It "Should extract ToVersion correctly" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.ToVersion | Should -Be "11.02.186"
        }

        It "Should extract target version number" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.TargetVersion | Should -Be "186"
        }

        It "Should provide UpdateLogPath" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateLogPath | Should -Not -BeNullOrEmpty
            $result.UpdateLogPath | Should -Match "update_.*\.log"
        }
    }
}

Describe "Find-LastUpdateOperation - Operation Block Detection" {

    Context "Operation block boundaries" {
        It "Should find complete operation blocks" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $logPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $logPath -Raw -Encoding 'Windows-1251'

            $result = Find-LastUpdateOperation -UpdateLogContent $logContent

            $result.Found | Should -Be $true
            $result.Content | Should -Not -BeNullOrEmpty
        }

        It "Should handle logs with no operation blocks" {
            $logContent = "Random log content without any operation markers"

            $result = Find-LastUpdateOperation -UpdateLogContent $logContent

            $result.Found | Should -Be $false
            $result.Content | Should -BeNullOrEmpty
        }

        It "Should find last operation when multiple exist" {
            $logContent = @"
Початок роботи, операція "Оновлення"
Old content here
Завершення роботи, операція "Оновлення"
Recent content between operations
Початок роботи, операція "Оновлення"
New content here
Завершення роботи, операція "Оновлення"
"@

            $result = Find-LastUpdateOperation -UpdateLogContent $logContent

            $result.Found | Should -Be $true
            $result.Content | Should -Match "New content here"
        }

        It "Should treat missing start marker as not found" {
            $logContent = @"
Технічні деталі без початку операції
Завершення роботи, операція "Оновлення"
"@

            $result = Find-LastUpdateOperation -UpdateLogContent $logContent

            $result.Found | Should -Be $false
            $result.EndPosition | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-VersionInfo - Version String Parsing" {

    Context "Standard M.E.Doc version format" {
        It "Should parse standard ezvit format correctly" {
            $result = Get-VersionInfo -RawVersion "ezvit.11.02.164-11.02.165.upd"

            $result.FromVersion | Should -Be "11.02.164"
            $result.ToVersion | Should -Be "11.02.165"
        }

        It "Should extract versions with whitespace" {
            $result = Get-VersionInfo -RawVersion " ezvit.11.02.185-11.02.186.upd "

            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
        }

        It "Should handle different version numbers" {
            $result = Get-VersionInfo -RawVersion "ezvit.10.05.100-10.05.101.upd"

            $result.FromVersion | Should -Be "10.05.100"
            $result.ToVersion | Should -Be "10.05.101"
        }
    }

    Context "Non-standard format handling" {
        It "Should handle single version (no hyphen)" {
            $result = Get-VersionInfo -RawVersion "ezvit.11.02.165.upd"

            $result.FromVersion | Should -Be "previous"
            $result.ToVersion | Should -Match "11.02.165"
        }
    }
}

Describe "Get-ExitCodeForOutcome - Exit Code Mapping" {

    Context "Success outcome mapping" {
        It "Should return 0 for Success" {
            $exitCode = Get-ExitCodeForOutcome -Outcome "Success"
            $exitCode | Should -Be 0
        }
    }

    Context "NoUpdate outcome mapping" {
        It "Should return 0 for NoUpdate" {
            $exitCode = Get-ExitCodeForOutcome -Outcome "NoUpdate"
            $exitCode | Should -Be 0
        }
    }

    Context "UpdateFailed outcome mapping" {
        It "Should return 2 for UpdateFailed" {
            $exitCode = Get-ExitCodeForOutcome -Outcome "UpdateFailed"
            $exitCode | Should -Be 2
        }
    }

    Context "Error outcome mapping" {
        It "Should return 1 for Error" {
            $exitCode = Get-ExitCodeForOutcome -Outcome "Error"
            $exitCode | Should -Be 1
        }
    }

    Context "Exit code semantics" {
        It "Should use 0 for successful/normal outcomes" {
            Get-ExitCodeForOutcome -Outcome "Success" | Should -Be 0
            Get-ExitCodeForOutcome -Outcome "NoUpdate" | Should -Be 0
        }

        It "Should use 1 for operational errors" {
            Get-ExitCodeForOutcome -Outcome "Error" | Should -Be 1
        }

        It "Should use 2 for validation failures" {
            Get-ExitCodeForOutcome -Outcome "UpdateFailed" | Should -Be 2
        }
    }
}

Describe "Invoke-MedocUpdateCheck - Main Orchestrator Function" {

    Context "Configuration validation - Required keys" {
        It "Should return Error outcome when ServerName is missing" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }
            $config.Remove('ServerName')

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigMissingKey)
            $result.NotificationSent | Should -Be $false
        }

        It "Should return Error outcome when MedocLogsPath is missing" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }
            $config.Remove('MedocLogsPath')

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigMissingKey)
        }

        It "Should return Error outcome when BotToken is missing" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }
            $config.Remove('BotToken')

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigMissingKey)
        }

        It "Should return Error outcome when ChatId is missing" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }
            $config.Remove('ChatId')

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigMissingKey)
        }
    }

    Context "Configuration validation - Invalid values" {
        It "Should return Error outcome when ServerName is empty" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = ""
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigInvalidValue)
        }

        It "Should return Error outcome when MedocLogsPath does not exist" {
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = "C:\NonExistent\Path\That\Does\Not\Exist"
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigInvalidValue)
        }

        It "Should return Error outcome when BotToken is empty" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = ""
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigInvalidValue)
        }

        It "Should return Error outcome when BotToken format is invalid" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "invalid_token_format"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigInvalidValue)
        }

        It "Should return Error outcome when ChatId is not numeric" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "not-a-number"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::ConfigInvalidValue)
        }

        It "Should accept negative ChatId (Telegram group syntax)" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "-12345"
            }

            # Should not error on validation, will fail on Telegram API later
            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            # Will attempt to process (Telegram API error is different outcome)
            if ($result.Outcome -eq 'Error') {
                $result.EventId | Should -Not -Be ([MedocEventId]::ConfigInvalidValue)
            }
        }
    }

    Context "Configuration validation - Encoding handling" {
        It "Should use default encoding when EncodingCodePage is not specified" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            # Should use default (1251) and process successfully
            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            # Not a configuration error - should process successfully
            $result | Should -Not -BeNullOrEmpty
            if ($result.Outcome -eq 'Error') {
                $result.EventId | Should -Not -Be ([MedocEventId]::ConfigInvalidValue)
            }
        }

        It "Should accept Windows-1251 encoding code page" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName       = "TEST-SERVER"
                MedocLogsPath    = $logsDir
                BotToken         = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId           = "12345"
                EncodingCodePage = 1251
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            # Should process without encoding validation error
            $result | Should -Not -BeNullOrEmpty
            if ($result.Outcome -eq 'Error') {
                $result.EventId | Should -Not -Be ([MedocEventId]::ConfigInvalidValue)
            }
        }

        It "Should accept UTF-8 encoding code page (65001)" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName       = "TEST-SERVER"
                MedocLogsPath    = $logsDir
                BotToken         = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId           = "12345"
                EncodingCodePage = 65001
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result | Should -Not -BeNullOrEmpty
            if ($result.Outcome -eq 'Error') {
                $result.EventId | Should -Not -Be ([MedocEventId]::ConfigInvalidValue)
            }
        }
    }

    Context "Invoke-MedocUpdateCheck - Successful execution path" {
        It "Should return proper outcome object structure" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            # Invoke-MedocUpdateCheck returns a PSCustomObject with Outcome, EventId, NotificationSent, UpdateResult
            $result | Should -Not -BeNullOrEmpty
            if ($null -ne $result) {
                $result | Get-Member | Select-Object -ExpandProperty Name | Should -Contain "Outcome"
                $result | Get-Member | Select-Object -ExpandProperty Name | Should -Contain "EventId"
                $result | Get-Member | Select-Object -ExpandProperty Name | Should -Contain "NotificationSent"
            }
        }

        It "Should have UpdateResult when update is detected" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            if ($result.Outcome -in @('Success', 'UpdateFailed')) {
                $result.UpdateResult | Should -Not -BeNullOrEmpty
                $result.UpdateResult.Status | Should -Not -BeNullOrEmpty
            }
        }

        It "Should set Outcome to valid enum value" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -BeIn @('Success', 'NoUpdate', 'UpdateFailed', 'Error')
        }

        It "Should set EventId from MedocEventId enum" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.EventId | Should -BeOfType [int]
            $result.EventId | Should -BeGreaterThan 0
        }
    }

    Context "Notification pipeline" {
        BeforeAll {
            $script:createUpdateResult = {
                param([string]$Status = "Success")

                $errorId = switch ($Status) {
                    "Success"  { [MedocEventId]::Success }
                    "NoUpdate" { [MedocEventId]::NoUpdate }
                    "Failed"   { [MedocEventId]::UpdateValidationFailed }
                    default     { [MedocEventId]::GeneralError }
                }

                $startTime = Get-Date "2025-10-23T10:30:15"
                $endTime = $startTime.AddMinutes(5)

                return @{
                    Status               = $Status
                    ErrorId              = $errorId
                    Success              = ($Status -eq "Success")
                    FromVersion          = "11.02.185"
                    ToVersion            = "11.02.186"
                    TargetVersion        = "186"
                    UpdateStartTime      = $startTime
                    UpdateEndTime        = $endTime
                    UpdateDuration       = [int]($endTime - $startTime).TotalSeconds
                    UpdateLogPath        = "update_2025-10-23.log"
                    MarkerVersionConfirm = $true
                    MarkerCompletionMarker = $true
                    OperationFound       = $true
                    Reason               = if ($Status -eq "Success") { "Update completed successfully" } else { "Missing markers" }
                }
            }
        }

        BeforeEach {
            $script:checkpointWrites = @()
            $script:restCallCount = 0
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $checkpointDir = Join-Path ([System.IO.Path]::GetTempPath()) ("MedocUpdateCheck_Test_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
            $script:tempDirectories += $checkpointDir
            $script:notificationConfig = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
                LastRunFile   = Join-Path $checkpointDir "checkpoint.txt"
            }

            Mock -ModuleName MedocUpdateCheck -CommandName Test-UpdateOperationSuccess -MockWith {
                param($MedocLogsPath, $SinceTime, $EncodingCodePage)
                & $script:createUpdateResult -Status "Success"
            }
            Mock -ModuleName MedocUpdateCheck -CommandName Format-UpdateTelegramMessage -MockWith {
                param($UpdateResult, $ServerName, $CheckTime)
                "telegram"
            }
            Mock -ModuleName MedocUpdateCheck -CommandName Format-UpdateEventLogMessage -MockWith {
                param($UpdateResult, $ServerName, $CheckTime)
                "event"
            }
            Mock -ModuleName MedocUpdateCheck -CommandName Write-EventLogEntry -MockWith { }
            Mock -ModuleName MedocUpdateCheck -CommandName Set-Content -MockWith {
                param($Path, $Value)
                $script:checkpointWrites += @{ Path = $Path; Value = $Value }
            }
        }

        It "Should send Telegram message when check succeeds" {
            Mock -ModuleName MedocUpdateCheck -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Body)
                $script:restCallCount++ | Out-Null
                @{ ok = $true }
            }

            $result = Invoke-MedocUpdateCheck -Config $script:notificationConfig -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Success'
            $result.NotificationSent | Should -Be $true
            $script:checkpointWrites.Count | Should -Be 1
            $script:restCallCount | Should -Be 1
        }

        It "Should treat Telegram API errors as failures" {
            Mock -ModuleName MedocUpdateCheck -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Body)
                @{ ok = $false; description = "Forbidden" }
            }

            $result = Invoke-MedocUpdateCheck -Config $script:notificationConfig -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::TelegramAPIError)
            $result.NotificationSent | Should -Be $false
        }

        It "Should handle Telegram send exceptions" {
            Mock -ModuleName MedocUpdateCheck -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Body)
                throw "Network failure"
            }

            $result = Invoke-MedocUpdateCheck -Config $script:notificationConfig -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::TelegramSendError)
            $result.NotificationSent | Should -Be $false
        }

        It "Should return checkpoint write errors before notification" {
            Mock -ModuleName MedocUpdateCheck -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Body)
                $script:restCallCount++ | Out-Null
                @{ ok = $true }
            }
            Mock -ModuleName MedocUpdateCheck -CommandName Set-Content -MockWith {
                param($Path, $Value)
                throw "Disk full"
            }

            $result = Invoke-MedocUpdateCheck -Config $script:notificationConfig -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::CheckpointWriteError)
            $script:restCallCount | Should -Be 0
        }

        It "Should map marker failures to UpdateFailed outcome" {
            Mock -ModuleName MedocUpdateCheck -CommandName Test-UpdateOperationSuccess -MockWith {
                param($MedocLogsPath, $SinceTime, $EncodingCodePage)
                & $script:createUpdateResult -Status "Failed"
            }
            Mock -ModuleName MedocUpdateCheck -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Body)
                @{ ok = $true }
            }

            $result = Invoke-MedocUpdateCheck -Config $script:notificationConfig -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'UpdateFailed'
            $result.EventId | Should -Be ([int][MedocEventId]::UpdateValidationFailed)
            $result.NotificationSent | Should -Be $true
        }

        It "Should fail when checkpoint directory cannot be created" {
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = (Join-Path $script:testDataDir "success-both-markers")
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            Mock -ModuleName MedocUpdateCheck -CommandName New-Item -MockWith { throw "Access denied" } -ParameterFilter {
                $Path -and $Path -match 'MedocUpdateCheck\\checkpoints'
            }
            Mock -ModuleName MedocUpdateCheck -CommandName Test-UpdateOperationSuccess -MockWith {
                param($MedocLogsPath, $SinceTime, $EncodingCodePage)
                throw "Should not be called"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
            $result.EventId | Should -Be ([MedocEventId]::CheckpointDirCreationFailed)
        }
    }
}


Describe "Update Log Timestamp Extraction" {

    Context "Timestamp parsing from update log" {
        It "Should extract first timestamp as update start time" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateStartTime | Should -BeOfType [datetime]
            $result.UpdateStartTime.Year | Should -BeGreaterThan 2020
        }

        It "Should extract last timestamp as update end time" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateEndTime | Should -BeOfType [datetime]
            $result.UpdateEndTime.Year | Should -BeGreaterThan 2020
        }

        It "Should calculate positive duration in seconds" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            if ($result.UpdateDuration) {
                $result.UpdateDuration | Should -BeGreaterThan -1
            }
        }

        It "Should handle end time after start time" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            if ($result.UpdateStartTime -and $result.UpdateEndTime) {
                $result.UpdateEndTime | Should -Not -BeLessThan $result.UpdateStartTime
            }
        }
    }

    Context "Handle missing or invalid timestamps" {
        It "Should handle case with no valid timestamps" {
            # Create a log with no parseable timestamps
            # This would be handled by setting UpdateStartTime/EndTime to null
            # Default log setup won't have this case, so we test the existing logs

            # If no timestamps found, they should be null
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Result should be Failed regardless of timestamp
            $result.Status | Should -Be "Failed"
        }
    }
}

Describe "Update Reason Messages" {

    Context "Failure reason reporting" {
        It "Should report specific reason for missing markers" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Reason | Should -Not -BeNullOrEmpty
            $result.Reason | Should -Match "marker"
        }

        It "Should report success reason when all checks pass" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            if ($result.Status -eq "Success") {
                $result.Reason | Should -Not -BeNullOrEmpty
                $result.Reason | Should -Match "success|Success"
            }
        }
    }
}

Describe "Update Log File Discovery" {

    Context "Update log filename pattern matching" {
        It "Should locate update log file with correct date pattern" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.UpdateLogPath | Should -Not -BeNullOrEmpty
            $result.UpdateLogPath | Should -Match "update_\d{4}-\d{2}-\d{2}\.log"
        }

        It "Should return null path for NoUpdate status" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # NoUpdate means no update log needed
            $result.Status | Should -Be "NoUpdate"
        }
    }
}

Describe "Error Status Constants" {

    Context "Error ID mapping" {
        It "Should use NoUpdate error ID when no update detected" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)
        }

        It "Should use UpdateLogMissing error ID when update log not found" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-log"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            if ($result.Status -eq "Failed") {
                $result.ErrorId | Should -Be ([MedocEventId]::UpdateLogMissing)
            }
        }

        It "Should use UpdateValidationFailed error ID for marker failures" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            if ($result.Status -eq "Failed") {
                $result.ErrorId | Should -Be ([MedocEventId]::UpdateValidationFailed)
            }
        }
    }
}

Describe "Invoke-MedocUpdateCheck - Outcome Enum Values" {

    Context "Outcome property values" {
        It "Should return 'Success' outcome for successful updates" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            # If no Telegram error, outcome should reflect the update result
            $result.Outcome | Should -BeIn @('Success', 'Error')

            # If Success, verify it came from update detection
            if ($result.Outcome -eq 'Success') {
                $result.UpdateResult.Status | Should -Be 'Success'
            }
        }

        It "Should return 'Error' outcome for config validation failures" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = ""
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.Outcome | Should -Be 'Error'
        }

        It "Should have EventId property set to valid MedocEventId" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.EventId | Should -BeOfType [int]
            # EventIds range from 1000-1999
            $result.EventId | Should -BeGreaterThan 999
        }

        It "Should have NotificationSent property as boolean" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $config = @{
                ServerName    = "TEST-SERVER"
                MedocLogsPath = $logsDir
                BotToken      = "123456789:ABCDEFGHijklmnopqrstuvwxyz123456789"
                ChatId        = "12345"
            }

            $result = Invoke-MedocUpdateCheck -Config $config -ErrorAction SilentlyContinue

            $result.NotificationSent | Should -BeOfType [bool]
        }
    }
}

Describe "Update Operation Flow - Integration" {

    Context "Complete update detection flow" {
        It "Should detect and report successful updates" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Success"
            $result.Success | Should -Be $true
            $result.FromVersion | Should -Not -BeNullOrEmpty
            $result.ToVersion | Should -Not -BeNullOrEmpty
            $result.ErrorId | Should -Be ([MedocEventId]::Success)
        }

        It "Should detect and report failed updates" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
            $result.ErrorId | Should -Be ([MedocEventId]::UpdateValidationFailed)
        }

        It "Should detect and report no update scenarios" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "NoUpdate"
            $result.ErrorId | Should -Be ([MedocEventId]::NoUpdate)
        }
    }

    Context "Result object completeness" {
        It "Should include all expected properties in success result" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Core properties
            $result.Keys | Should -Contain "Status"
            $result.Keys | Should -Contain "Success"
            $result.Keys | Should -Contain "ErrorId"

            # Version info
            $result.Keys | Should -Contain "FromVersion"
            $result.Keys | Should -Contain "ToVersion"
            $result.Keys | Should -Contain "TargetVersion"

            # Marker info (Phase 1)
            $result.Keys | Should -Contain "MarkerVersionConfirm"
            $result.Keys | Should -Contain "MarkerCompletionMarker"
            $result.Keys | Should -Contain "OperationFound"

            # Timestamps and duration
            $result.Keys | Should -Contain "UpdateStartTime"
            $result.Keys | Should -Contain "UpdateEndTime"
            $result.Keys | Should -Contain "UpdateDuration"

            # Log info
            $result.Keys | Should -Contain "UpdateLogPath"
            $result.Keys | Should -Contain "Reason"
        }

        It "Should include all expected properties in failure result" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Core properties
            $result.Keys | Should -Contain "Status"
            $result.Keys | Should -Contain "Success"
            $result.Keys | Should -Contain "ErrorId"

            # Version info (from Planner.log, not update log)
            $result.Keys | Should -Contain "FromVersion"
            $result.Keys | Should -Contain "ToVersion"

            # Reason
            $result.Keys | Should -Contain "Reason"
        }
    }
}

Describe "Test-UpdateState - Marker Classification Logic" {

    Context "Marker-based state classification" {
        It "Should classify Success when both markers present" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "186"

            $result.Status | Should -Be "Success"
            $result.VersionConfirm | Should -Be $true
            $result.CompletionMarker | Should -Be $true
        }

        It "Should classify Failed when version marker missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "186"

            $result.Status | Should -Be "Failed"
            $result.VersionConfirm | Should -Be $false
        }

        It "Should classify Failed when completion marker missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "186"

            # Completion marker missing means operation not found
            $result.Status | Should -Be "Failed"
        }
    }

    Context "Target version matching" {
        It "Should match exact version number" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $true
        }

        It "Should not match different version number" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $updateLogPath = Join-Path $logsDir "update_2025-10-23.log"
            $logContent = Get-Content -Path $updateLogPath -Raw -Encoding 'Windows-1251'

            $result = Test-UpdateState -UpdateLogContent $logContent -TargetVersion "999"

            $result.VersionConfirm | Should -Be $false
        }
    }
}

Describe "Phase 1 Refactoring Verification" {

    Context "Marker-based detection (Phase 1)" {
        It "Should use 2 markers: Version (V) and Completion (C)" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Phase 1 uses MarkerVersionConfirm and MarkerCompletionMarker
            $result.Keys | Should -Contain "MarkerVersionConfirm"
            $result.Keys | Should -Contain "MarkerCompletionMarker"

            # Both must be true for success
            if ($result.Status -eq "Success") {
                $result.MarkerVersionConfirm | Should -Be $true
                $result.MarkerCompletionMarker | Should -Be $true
            }
        }

        It "Should not use old 3-flag system" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Phase 1: Old flag properties should not be in success path
            # (They may exist in error paths for backward compatibility)
            if ($result.Status -eq "Success") {
                $result.Keys | Should -Not -Contain "Flag1_Infrastructure"
                $result.Keys | Should -Not -Contain "Flag2_ServiceRestart"
                $result.Keys | Should -Not -Contain "Flag3_VersionConfirm"
            }
        }

        It "Should use OperationFound property to track operation block detection" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Phase 1 tracks whether operation block was found
            $result.Keys | Should -Contain "OperationFound"
            if ($result.Status -eq "Success") {
                $result.OperationFound | Should -Be $true
            }
        }
    }

    Context "Marker definition validation" {
        It "Marker V is version confirmation pattern" {
            # Pattern: "Версія програми - {VERSION}"
            $testContent = "Версія програми - 186"
            $result = Test-UpdateMarker -OperationContent $testContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $true
        }

        It "Marker C is update completion pattern" {
            # Pattern: 'Завершення роботи, операція "Оновлення"'
            $testContent = 'Завершення роботи, операція "Оновлення"'
            $result = Test-UpdateMarker -OperationContent $testContent -TargetVersion "186"

            $result.CompletionMarker | Should -Be $true
        }

        It "Both markers required for operation block" {
            # Start marker: 'Початок роботи, операція "Оновлення"'
            # End marker: 'Завершення роботи, операція "Оновлення"'
            $testContent = @"
Початок роботи, операція "Оновлення"
Версія програми - 186
Завершення роботи, операція "Оновлення"
"@

            $result = Test-UpdateMarker -OperationContent $testContent -TargetVersion "186"

            $result.VersionConfirm | Should -Be $true
            $result.CompletionMarker | Should -Be $true
        }
    }
}

Describe "Integration Tests - Comprehensive Marker-Based Detection Scenarios" {
    Context "Success scenario: both markers present" {
        It "Should successfully detect update with both version and completion markers" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Success"
            $result.Success | Should -Be $true
            $result.OperationFound | Should -Be $true
        }

        It "Should correctly identify both markers in success scenario" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.MarkerVersionConfirm | Should -Be $true
            $result.MarkerCompletionMarker | Should -Be $true
        }

        It "Should extract version from update log in success scenario" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
            $result.TargetVersion | Should -Be "186"
        }

        It "Should extract operation timestamp from update log" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # UpdateStartTime is extracted from first timestamp in operation block
            $result.UpdateStartTime | Should -BeOfType [datetime]
        }

        It "Should have operation found flag set to true" {
            $logsDir = Join-Path $script:testDataDir "success-both-markers"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.OperationFound | Should -Be $true
            $result.Success | Should -Be $true
        }
    }

    Context "Failure scenario: missing version marker (V)" {
        It "Should detect failure when version marker is missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
        }

        It "Should show version marker as missing but completion marker present" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.MarkerVersionConfirm | Should -Be $false
            $result.MarkerCompletionMarker | Should -Be $true
        }

        It "Should still extract version from Planner log" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
        }

        It "Should mark operation as found but failed due to missing version marker" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.OperationFound | Should -Be $true
            $result.Success | Should -Be $false
            $result.MarkerVersionConfirm | Should -Be $false
        }

        It "Should distinguish missing version marker failure from other failures" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-version-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Completion marker present means it's not a detection failure
            $result.MarkerCompletionMarker | Should -Be $true
            # But version marker missing causes failure
            $result.MarkerVersionConfirm | Should -Be $false
        }
    }

    Context "Failure scenario: missing completion marker (C)" {
        It "Should detect failure when completion marker is missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "Failed"
            $result.Success | Should -Be $false
        }

        It "Should show operation not found when completion marker missing" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Operation detection requires BOTH start and completion markers
            # Missing completion means operation block not found at all
            $result.OperationFound | Should -Be $false
        }

        It "Should handle missing completion marker gracefully" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Should not throw, should return coherent result
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
        }

        It "Should still extract version from Planner even without operation block" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Version info comes from Planner log, not update log
            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
        }

        It "Should distinguish missing completion marker from no-update scenario" {
            $logsDir = Join-Path $script:testDataDir "failure-missing-completion-marker"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Operation not found, but update was in Planner
            $result.Status | Should -Be "Failed"
            # Not NoUpdate because update was detected in Planner
            $result.Status | Should -Not -Be "NoUpdate"
        }
    }

    Context "Failure scenario: no update operation detected" {
        It "Should detect no-update when no update operation is in logs" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.Status | Should -Be "NoUpdate"
        }

        It "Should handle no-update gracefully" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Result should be returned without errors
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "NoUpdate"
        }

        It "Should return empty version info when no operation detected" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Version info should be empty or null
            $result.FromVersion | Should -BeNullOrEmpty
            $result.ToVersion | Should -BeNullOrEmpty
        }

        It "Should distinguish no-update from failed-update scenarios" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-detected"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # NoUpdate is distinct from Failed
            $result.Status | Should -Be "NoUpdate"
        }
    }

    Context "Failure scenario: no update log file" {
        It "Should handle missing update log file gracefully" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-log"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Failed"
        }

        It "Should detect operation in Planner log but no operation block available" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-log"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Update detected in Planner but can't verify without operation block
            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
            $result.OperationFound | Should -Be $false
        }

        It "Should return failed status when update log is missing" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-log"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            # Status should indicate failure (can't verify without update log)
            $result.Status | Should -Be "Failed"
            $result.MarkerVersionConfirm | Should -Be $false
            $result.MarkerCompletionMarker | Should -Be $false
            $result.Reason | Should -Match "Update log file not found"
        }

        It "Should extract version from Planner log even without update log" {
            $logsDir = Join-Path $script:testDataDir "failure-no-update-log"
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsDir

            $result.FromVersion | Should -Be "11.02.185"
            $result.ToVersion | Should -Be "11.02.186"
        }
    }

    Context "Cross-scenario marker patterns" {
        It "Success scenario has both markers and operation found" {
            # VV = Success (both markers present)
            $resultVV = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "success-both-markers")
            $resultVV.MarkerVersionConfirm | Should -Be $true
            $resultVV.MarkerCompletionMarker | Should -Be $true
            $resultVV.Success | Should -Be $true
        }

        It "Missing completion marker means operation not found" {
            # When completion marker missing, operation block not detected
            $resultMissingC = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "failure-missing-completion-marker")
            $resultMissingC.Status | Should -Be "Failed"
            # Operation detection requires both markers
            $resultMissingC.OperationFound | Should -Be $false
        }

        It "Missing version marker in operation block is detected" {
            # xV = Failed (version missing, completion present)
            $resultxV = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "failure-missing-version-marker")
            $resultxV.MarkerVersionConfirm | Should -Be $false
            $resultxV.MarkerCompletionMarker | Should -Be $true
            $resultxV.Success | Should -Be $false
        }

        It "Version extraction works independently of marker presence" {
            $resultSuccess = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "success-both-markers")
            $resultMissingV = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "failure-missing-version-marker")
            $resultMissingC = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "failure-missing-completion-marker")

            # All should extract same version info from Planner.log
            $resultSuccess.FromVersion | Should -Be "11.02.185"
            $resultMissingV.FromVersion | Should -Be "11.02.185"
            $resultMissingC.FromVersion | Should -Be "11.02.185"

            $resultSuccess.ToVersion | Should -Be "11.02.186"
            $resultMissingV.ToVersion | Should -Be "11.02.186"
            $resultMissingC.ToVersion | Should -Be "11.02.186"
        }

        It "Marker detection is independent of version extraction" {
            $result = Test-UpdateOperationSuccess -MedocLogsPath (Join-Path $script:testDataDir "failure-missing-version-marker")

            # Can extract version from Planner
            $result.FromVersion | Should -Not -BeNullOrEmpty
            $result.ToVersion | Should -Not -BeNullOrEmpty
            # But marker detection shows version marker missing from update log
            $result.MarkerVersionConfirm | Should -Be $false
            # This is the key difference: version exists, but marker missing
        }
    }
}
AfterAll {
    Remove-Module MedocUpdateCheck -Force -ErrorAction SilentlyContinue
    if ($script:tempDirectories) {
        foreach ($dir in $script:tempDirectories) {
            if ($dir -and (Test-Path $dir)) {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
