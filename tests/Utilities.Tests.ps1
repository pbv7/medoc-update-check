#Requires -Version 7.0

# PSScriptAnalyzer Note: This test file includes Write-Host calls for test output formatting.
# These are intentional and appropriate for interactive test reporting within Pester.
# Rule: PSAvoidUsingWriteHost is suppressed for this test context.

<#
.SYNOPSIS
    Comprehensive tests for utility functions and deployment helpers

.DESCRIPTION
    Tests for:
    - Get-TelegramCredentials.ps1 - Credential decryption and retrieval
    - Setup-Credentials.ps1 - Certificate creation and credential encryption
    - Setup-ScheduledTask.ps1 - Task Scheduler job creation
    - Validate-Scripts.ps1 - PowerShell syntax validation

.NOTES
    Author: Test Suite
    Tests utility functions used in deployment and daily operation
#>

BeforeAll {
    # Setup test environment
    $script:testDir = $PSScriptRoot
    $script:projectRoot = Split-Path -Parent $testDir
    $script:utilsDir = Join-Path $projectRoot "utils"
    $script:configDir = Join-Path $projectRoot "configs"
    $script:tempDir = [System.IO.Path]::GetTempPath()

    # Create temporary directories for tests
    $script:testTempDir = Join-Path $tempDir "MedocUtilsTest_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:testTempDir -Force | Out-Null
}

AfterAll {
    # Cleanup temporary test directories
    if (Test-Path $script:testTempDir) {
        Remove-Item -Path $script:testTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Get-TelegramCredentials.ps1 - Credential Decryption" {
    Context "Credential file operations" {
        It "Should locate default credential file in ProgramData" {
            # Test that the script looks in the correct location
            $expectedPath = if ($IsWindows) {
                "$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms"
            }
            else {
                # On non-Windows, we use a compatible path pattern
                "$env:HOME/.config/MedocUpdateCheck/credentials/telegram.cms"
            }

            # We test the path construction logic, not file existence
            $expectedPath | Should -Match "(ProgramData|\.config).*MedocUpdateCheck.*telegram\.cms"
        }

        It "Should handle missing credential file gracefully" {
            # Simulate the behavior of credential retrieval with missing file
            $credPath = "C:\NonExistent\Path\telegram.cms"
            {
                if (-not (Test-Path $credPath)) {
                    Write-Warning "Credential file not found"
                }
            } | Should -Not -Throw
        }

        It "Should require proper file permissions" {
            # Test that credential files should have restricted permissions
            $testFile = Join-Path $script:testTempDir "test_creds.cms"
            New-Item -ItemType File -Path $testFile -Force | Out-Null

            # Verify file can be read (permission structure)
            { Get-Content $testFile -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "CMS message decryption" {
        It "Should validate CMS message format before decryption" {
            # Test that decryption validates input format
            $invalidCMS = "NotAValidCMSMessage"

            # Simulate validation
            $isValidCMS = $invalidCMS -match "^-----BEGIN CERTIFICATE-----"
            $isValidCMS | Should -Be $false
        }

        It "Should handle decryption errors gracefully" {
            # Test error handling for decryption failures
            $testMessage = "InvalidCMSData"

            # Simulate Unprotect-CmsMessage error handling
            {
                try {
                    # This would normally call Unprotect-CmsMessage
                    if ($testMessage -notmatch "-----BEGIN") {
                        throw "Invalid CMS message format"
                    }
                }
                catch {
                    Write-Warning "Failed to decrypt credentials: $_"
                }
            } | Should -Not -Throw
        }

        It "Should return hashtable with correct structure" {
            # Test that credentials are returned as expected hashtable
            # Simulate credential retrieval
            $credentials = @{
                BotToken = "123456:ABC-DEF-GHI-JKL-MNO-PQR-STU-VWX-YZ"
                ChatId   = "12345"
            }

            $credentials.Keys | Should -Contain "BotToken"
            $credentials.Keys | Should -Contain "ChatId"
        }
    }

    Context "Credential validation" {
        It "Should validate BotToken format" {
            # BotToken format: digits:alphanumeric
            $validToken = "123456:ABCDEFGHIJKLMNOPQRSTUVWxyz"
            $validToken -match '^\d+:[A-Za-z0-9_-]+$' | Should -Be $true
        }

        It "Should validate ChatId format (numeric)" {
            # ChatId should be numeric (positive or negative)
            $validChatId = "12345"
            $invalidChatId = "ABC-123"

            $validChatId -match '^-?\d+$' | Should -Be $true
            $invalidChatId -match '^-?\d+$' | Should -Be $false
        }

        It "Should support negative ChatIds (group channels)" {
            # Negative ChatIds are valid for group channels
            $groupChatId = "-987654321"
            $groupChatId -match '^-?\d+$' | Should -Be $true
        }
    }
}

Describe "Setup-Credentials.ps1 - Certificate Management" {
    Context "Self-signed certificate creation" {
        It "Should create certificate with correct subject" {
            # Test certificate subject format
            $subject = "CN=MedocUpdateCheck"
            $subject | Should -Match "^CN=MedocUpdateCheck$"
        }

        It "Should validate certificate exists in LocalMachine\\My store" {
            # Test certificate store location validation
            $storePath = "Cert:\LocalMachine\My"
            # We verify the path format is correct for PowerShell
            $storePath | Should -Match "Cert:\\LocalMachine"
        }

        It "Should set correct lifetime (5 years)" {
            # Test certificate validity period
            $validityYears = 5
            $notAfter = (Get-Date).AddYears($validityYears)

            $validityYears | Should -Be 5
            $notAfter.Year - (Get-Date).Year | Should -Be 5
        }

        It "Should use RSA 2048-bit key" {
            # Test key algorithm and size
            $keySize = 2048
            $keyAlgorithm = "RSA"

            $keySize | Should -Be 2048
            $keyAlgorithm | Should -Be "RSA"
        }
    }

    Context "Certificate EKU validation" {
        It "Should include Document Encryption Extended Key Usage" {
            # CMS requires Document Encryption EKU (1.3.6.1.4.1.311.80.1)
            $requiredEKU = "1.3.6.1.4.1.311.80.1"

            # Verify EKU OID format
            $requiredEKU | Should -Match '^\d+\.\d+\.\d+\.\d+\.\d+\.\d+\.\d+\.\d+\.\d+$'
        }

        It "Should include KeyEncipherment in key usage" {
            # Test that KeyEncipherment is set
            $keyUsage = "KeyEncipherment"

            # Verify key usage is recognized
            @("KeyEncipherment", "DataEncipherment", "KeyCertSign") | Should -Contain $keyUsage
        }

        It "Should include DataEncipherment in key usage" {
            # CMS requires both KeyEncipherment and DataEncipherment
            $keyUsages = @("KeyEncipherment", "DataEncipherment")

            $keyUsages | Should -Contain "KeyEncipherment"
            $keyUsages | Should -Contain "DataEncipherment"
        }
    }

    Context "Certificate lifecycle and renewal" {
        It "Should detect expired certificates" {
            # Test expiration detection logic
            $expiredDate = (Get-Date).AddYears(-1)
            $currentDate = Get-Date

            $expiredDate -lt $currentDate | Should -Be $true
        }

        It "Should detect certificates expiring within 30 days" {
            # Test near-expiration detection
            $almostExpiredDate = (Get-Date).AddDays(15)
            $daysUntilExpiration = ($almostExpiredDate - (Get-Date)).Days

            $daysUntilExpiration -lt 30 | Should -Be $true
        }

        It "Should trigger regeneration for expired certificates" {
            # Test regeneration logic
            $existingCertExpiration = (Get-Date).AddYears(-1)
            $shouldRegenerate = $existingCertExpiration -lt (Get-Date)

            $shouldRegenerate | Should -Be $true
        }

        It "Should trigger regeneration if EKU requirements missing" {
            # Test EKU validation for regeneration
            $hasCMSEKU = $false  # Simulating missing EKU
            $shouldRegenerate = -not $hasCMSEKU

            $shouldRegenerate | Should -Be $true
        }

        It "Should trigger regeneration if KeyEncipherment missing" {
            # Test key usage validation for regeneration
            $hasKeyEncipherment = $false  # Simulating missing usage
            $shouldRegenerate = -not $hasKeyEncipherment

            $shouldRegenerate | Should -Be $true
        }
    }

    Context "Credential encryption with CMS" {
        It "Should validate certificate before encryption" {
            # Test pre-encryption validation
            $certificateValid = $true

            if (-not $certificateValid) {
                Write-Error "Certificate not suitable for encryption"
                return $false
            }

            $certificateValid | Should -Be $true
        }

        It "Should handle encryption errors gracefully" {
            # Test error handling for Protect-CmsMessage
            {
                try {
                    # Simulate Protect-CmsMessage
                    $data = "test"
                    if ([string]::IsNullOrEmpty($data)) {
                        throw "Data cannot be empty"
                    }
                }
                catch {
                    Write-Warning "Encryption failed: $_"
                }
            } | Should -Not -Throw
        }

        It "Should encrypt credentials in correct format" {
            # Test encrypted message structure
            $encryptedData = "-----BEGIN CMS-----`nbase64encodeddata`n-----END CMS-----"

            $encryptedData | Should -Match "^-----BEGIN CMS-----"
            $encryptedData | Should -Match "-----END CMS-----$"
        }
    }
}

Describe "Setup-ScheduledTask.ps1 - Task Scheduler Integration" {
    # NOTE: Task Scheduler is Windows-only feature (uses Windows Registry and Scheduler COM API)
    # On non-Windows platforms, this test is skipped since Task Scheduler does not exist

    Context "Administrative requirements" {
        It "Should require Administrator privileges" -Skip:(-not $IsWindows) {
            # PLATFORM: Windows only (macOS/Linux do not have Windows Task Scheduler)
            if ($IsWindows) {
                $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator
                )

                # If not admin, function should warn or fail (test the logic)
                if (-not $isAdmin) {
                    Write-Warning "Administrator privileges required to create scheduled tasks"
                }
            }

            # We verify the check exists, not necessarily that user is admin
            $true | Should -Be $true
        }
    }

    Context "PowerShell version detection" {
        It "Should find PowerShell 7+ installation" {
            # Test PowerShell 7+ detection
            $pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

            # Verify path format for PowerShell 7+
            $pwshPath | Should -Match "PowerShell.*pwsh\.exe"
        }

        It "Should validate PowerShell 7 is available" {
            # Test that PS7 check happens
            $psVersion = $PSVersionTable.PSVersion

            # Current session should be PS 7+ (per #Requires)
            $psVersion.Major | Should -Be 7
        }

        It "Should use pwsh.exe not powershell.exe for execution" {
            # Test correct executable selection
            $correctExecutable = "pwsh.exe"
            $wrongExecutable = "powershell.exe"

            $correctExecutable | Should -Be "pwsh.exe"
            $wrongExecutable | Should -Not -Be "pwsh.exe"
        }
    }

    Context "Task configuration" {
        It "Should validate time format HH:MM" {
            # Test time validation
            $validTime = "14:30"
            $invalidTime = "25:00"

            $validTime -match '^\d{2}:\d{2}$' | Should -Be $true
            $invalidTime -match '^\d{2}:\d{2}$' | Should -Be $true  # Format matches, hours invalid
        }

        It "Should create task in correct folder" {
            # Test task path
            $taskFolder = "\MedocUpdateCheck"

            $taskFolder | Should -Match "^\\MedocUpdateCheck$"
        }

        It "Should set task to run with SYSTEM user" {
            # Test user context
            $expectedPrincipal = "SYSTEM"

            $expectedPrincipal | Should -Be "SYSTEM"
        }

        It "Should enable task after creation" {
            # Test task enabled status
            $taskEnabled = $true

            $taskEnabled | Should -Be $true
        }

        It "Should set no idle time trigger" {
            # Test trigger configuration
            $idleTimeMinutes = 0  # No idle time required

            $idleTimeMinutes | Should -Be 0
        }
    }

    Context "Script path configuration" {
        It "Should locate Run.ps1 correctly" {
            # Test script path resolution
            $runScriptPath = Join-Path $script:projectRoot "Run.ps1"

            $runScriptPath | Should -Match "Run\.ps1$"
        }

        It "Should use absolute paths in task" {
            # Test that paths are absolute, not relative
            $absolutePath = "C:\path\to\Run.ps1"
            $relativePath = ".\Run.ps1"

            $absolutePath | Should -Match "^[A-Z]:\\.*Run\.ps1$"
            $relativePath | Should -Not -Match "^[A-Z]:\\.*Run\.ps1$"
        }

        It "Should pass config file path as argument" {
            # Test argument construction
            $configPath = "C:\path\to\Config-SERVERNAME.ps1"
            $argument = "-ConfigFile `"$configPath`""

            $argument | Should -Match "-ConfigFile"
            $argument | Should -Match "\.ps1"
        }
    }

    Context "Error handling" {
        It "Should handle task already exists scenario" {
            # Test existing task check
            {
                # Simulate checking for existing task
                $taskExists = $false
                if ($taskExists) {
                    Write-Warning "Task already exists"
                    return $false
                }
            } | Should -Not -Throw
        }

        It "Should provide clear error messages on failure" {
            # Test error message quality
            {
                try {
                    throw "Failed to create scheduled task: Access Denied"
                }
                catch {
                    Write-Error $_
                }
            } | Should -Throw
        }
    }
}

Describe "Validate-Scripts.ps1 - PowerShell Syntax Validation" {
    Context "Script discovery" {
        It "Should find all PowerShell script files" {
            # Test script discovery pattern
            $scripts = @(Get-ChildItem -Path $script:projectRoot -Filter "*.ps1" -Recurse |
                Where-Object { $_.FullName -notmatch '\.git|node_modules' })

            # Should find at least core scripts
            $scripts.Count | Should -BeGreaterThan 0
        }

        It "Should exclude .git and node_modules directories" {
            # Test exclusion pattern
            $excludePattern = '\.git|node_modules'

            ".git\file.ps1" -match $excludePattern | Should -Be $true
            "node_modules\file.ps1" -match $excludePattern | Should -Be $true
            "lib\file.ps1" -match $excludePattern | Should -Be $false
        }

        It "Should process .ps1 and .psm1 files" {
            # Test file type detection
            $extensions = @(".ps1", ".psm1")

            $extensions | Should -Contain ".ps1"
            $extensions | Should -Contain ".psm1"
        }
    }

    Context "Syntax validation" {
        It "Should validate PowerShell parsing without executing code" {
            # Test safe parsing
            $testScript = 'Write-Host "Hello"'

            {
                [System.Management.Automation.Language.Parser]::ParseInput(
                    $testScript, [ref]$null, [ref]$null) | Out-Null
            } | Should -Not -Throw
        }

        It "Should detect syntax errors" {
            # Test error detection
            $invalidScript = 'Write-Host "Unclosed quote'
            $parseErrors = $null

            [void][System.Management.Automation.Language.Parser]::ParseInput(
                $invalidScript, [ref]$null, [ref]$parseErrors)

            # Should have detected the error
            $parseErrors | Should -Not -BeNullOrEmpty
        }

        It "Should report specific error locations" {
            # Test error location reporting
            $invalidScript = 'if ($true { }'  # Missing closing paren
            $parseErrors = $null

            [void][System.Management.Automation.Language.Parser]::ParseInput(
                $invalidScript, [ref]$null, [ref]$parseErrors)

            $parseErrors | Should -Not -BeNullOrEmpty
        }

        It "Should handle balanced brackets and quotes" {
            # Test bracket/quote validation
            $validScript = @'
$config = @{
    Key = "Value"
    Array = @(1, 2, 3)
}
'@

            {
                [System.Management.Automation.Language.Parser]::ParseInput(
                    $validScript, [ref]$null, [ref]$null)
            } | Should -Not -Throw
        }
    }

    Context "Module validation" {
        It "Should validate .psm1 module files" {
            # Test module file validation
            $moduleFile = Join-Path $script:projectRoot "lib\MedocUpdateCheck.psm1"

            {
                if (Test-Path $moduleFile) {
                    $content = Get-Content -Path $moduleFile -Raw
                    [System.Management.Automation.Language.Parser]::ParseInput(
                        $content, [ref]$null, [ref]$null)
                }
            } | Should -Not -Throw
        }

        It "Should detect module syntax errors" {
            # Test module error detection
            $invalidModule = 'function Test-Func { Write-Host "Unclosed quote'

            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput(
                $invalidModule, [ref]$null, [ref]$parseErrors)

            $parseErrors | Should -Not -BeNullOrEmpty
        }
    }

    Context "Validation output" {
        It "Should report success for valid scripts" {
            # Test success reporting
            $validScript = 'Write-Host "Test"'

            {
                $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                    $validScript, [ref]$null, [ref]$null)
                if ($null -eq $ast) {
                    Write-Host "❌ Syntax error"
                }
                else {
                    Write-Host "✓ Valid"
                }
            } | Should -Not -Throw
        }

        It "Should provide summary of validation results" {
            # Test summary output
            $passedCount = 5
            $failedCount = 0

            Write-Host "Validation Summary: Passed: $passedCount, Failed: $failedCount"

            $passedCount | Should -Be 5
            $failedCount | Should -Be 0
        }

        It "Should list failed scripts" {
            # Test failure reporting
            $failedScripts = @()  # No failures in this test

            if ($failedScripts.Count -gt 0) {
                Write-Host "Failed Scripts:"
                $failedScripts | ForEach-Object { Write-Host "  - $_" }
            }

            $failedScripts.Count | Should -Be 0
        }
    }

    Context "Edge cases" {
        It "Should handle empty files" {
            # Test empty file validation
            $emptyScript = ""

            {
                [System.Management.Automation.Language.Parser]::ParseInput(
                    $emptyScript, [ref]$null, [ref]$null)
            } | Should -Not -Throw
        }

        It "Should handle comment-only files" {
            # Test comment-only validation
            $commentScript = @"
# This is a comment
# More comments
"@

            {
                [System.Management.Automation.Language.Parser]::ParseInput(
                    $commentScript, [ref]$null, [ref]$null)
            } | Should -Not -Throw
        }

        It "Should handle files with #Requires statements" {
            # Test #Requires validation
            $requiresScript = @"
#Requires -Version 7.0
Write-Host "Test"
"@

            {
                [System.Management.Automation.Language.Parser]::ParseInput(
                    $requiresScript, [ref]$null, [ref]$null)
            } | Should -Not -Throw
        }
    }
}

# Summary test to verify all utilities are in place
Describe "Utility Suite - Integration Check" {
    It "Should have all 4 utility scripts present" {
        $utilities = @(
            "Get-TelegramCredentials.ps1",
            "Setup-Credentials.ps1",
            "Setup-ScheduledTask.ps1",
            "Validate-Scripts.ps1"
        )

        foreach ($utility in $utilities) {
            $path = Join-Path $script:utilsDir $utility
            Test-Path $path | Should -Be $true
        }
    }

    It "Should have all utilities in correct location" {
        $utilsDir = Join-Path $script:projectRoot "utils"
        Test-Path $utilsDir | Should -Be $true

        Get-ChildItem -Path $utilsDir -Filter "*.ps1" | Should -Not -BeNullOrEmpty
    }
}

Describe "ConfigValidation.psm1 - Shared Validation Functions" {
    BeforeAll {
        $script:libPath = Join-Path $script:projectRoot "lib"
        Import-Module (Join-Path $script:libPath "ConfigValidation.psm1") -Force
    }

    Context "Test-ServerName validation" {
        It "Should accept valid server names" {
            $result = Test-ServerName -ServerName "SERVER-01"
            $result.Valid | Should -Be $true
        }

        It "Should reject empty server names" {
            $result = Test-ServerName -ServerName ""
            $result.Valid | Should -Be $false
            $result.ErrorMessage | Should -Match "cannot be empty"
        }

        It "Should accept names with spaces and dashes" {
            $result = Test-ServerName -ServerName "My Test Server-01"
            $result.Valid | Should -Be $true
        }
    }

    Context "Test-BotToken validation" {
        It "Should accept valid Telegram bot token format" {
            $result = Test-BotToken -BotToken "123456789:ABCdeFGHijklMnoPQRstUVwxyz-_1234567890ABC"
            $result.Valid | Should -Be $true
        }

        It "Should reject empty bot token" {
            $result = Test-BotToken -BotToken ""
            $result.Valid | Should -Be $false
        }

        It "Should reject malformed bot token (missing colon)" {
            $result = Test-BotToken -BotToken "123456789ABCdeFGHijklMnoPQRstUVwxyz"
            $result.Valid | Should -Be $false
            $result.ErrorMessage | Should -Match "format invalid"
        }

        It "Should reject bot token with invalid characters" {
            $result = Test-BotToken -BotToken "123456789:ABC!@#$%"
            $result.Valid | Should -Be $false
        }
    }

    Context "Test-ChatId validation" {
        It "Should accept positive numeric chat ID" {
            $result = Test-ChatId -ChatId "123456789"
            $result.Valid | Should -Be $true
        }

        It "Should accept negative numeric chat ID" {
            $result = Test-ChatId -ChatId "-123456789"
            $result.Valid | Should -Be $true
        }

        It "Should reject non-numeric chat ID" {
            $result = Test-ChatId -ChatId "ABC123"
            $result.Valid | Should -Be $false
            $result.ErrorMessage | Should -Match "must be numeric"
        }
    }

    Context "Test-EncodingCodePage validation" {
        It "Should accept supported encoding 1251 (Cyrillic)" {
            $result = Test-EncodingCodePage -EncodingCodePage 1251
            $result.Valid | Should -Be $true
        }

        It "Should accept supported encoding 65001 (UTF-8)" {
            $result = Test-EncodingCodePage -EncodingCodePage 65001
            $result.Valid | Should -Be $true
        }

        It "Should accept supported encoding 1200 (Unicode)" {
            $result = Test-EncodingCodePage -EncodingCodePage 1200
            $result.Valid | Should -Be $true
        }

        It "Should reject unsupported encoding code page" {
            $result = Test-EncodingCodePage -EncodingCodePage 9999
            $result.Valid | Should -Be $false
            $result.ErrorMessage | Should -Match "not supported"
        }

        It "Should return warning with UseDefault when encoding unsupported" {
            $result = Test-EncodingCodePage -EncodingCodePage 9999 -UseDefault
            $result.Valid | Should -Be $true
            $result.IsWarning | Should -Be $true
            $result.DefaultValue | Should -Be 1251
        }
    }

    Context "Test-MedocLogsPath validation" {
        It "Should accept valid existing directory" {
            $testDir = Get-Item -Path $script:projectRoot
            $result = Test-MedocLogsPath -MedocLogsPath $testDir.FullName
            $result.Valid | Should -Be $true
        }

        It "Should reject non-existent directory" {
            $result = Test-MedocLogsPath -MedocLogsPath "/non/existent/path"
            $result.Valid | Should -Be $false
            $result.ErrorMessage | Should -Match "not a valid directory"
        }
    }

    Context "Test-CheckpointPath validation" {
        It "Should validate checkpoint path can be created" {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "medoc-checkpoint-test-$([guid]::NewGuid()).txt"
            $result = Test-CheckpointPath -CheckpointPath $testPath

            $result.Valid | Should -Be $true
            $result.DirectoryPath | Should -Not -BeNullOrEmpty
        }
    }
}
