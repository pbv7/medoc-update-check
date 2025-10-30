# Contributing to M.E.Doc Update Check

Thank you for your interest in contributing to this project! This document provides
comprehensive guidelines for developers, contributors, and community members. Whether you're
submitting code, documentation, or fixes, please follow these standards to maintain code
quality, consistency, and reliability.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Getting Started](#getting-started)
3. [Architecture and Design Principles](#architecture-and-design-principles)
4. [PowerShell Code Guidelines](#powershell-code-guidelines)
5. [Testing Guidelines](#testing-guidelines)
6. [Documentation Guidelines](#documentation-guidelines)
7. [Markdown Style Guide](#markdown-style-guide)
8. [Commit and Git Guidelines](#commit-and-git-guidelines)
9. [Code Quality Checklist](#code-quality-checklist)
10. [Common Patterns and Examples](#common-patterns-and-examples)
11. [Quick Reference](#quick-reference)
12. [Getting Help](#getting-help)
13. [Code of Conduct](#code-of-conduct)
14. [Summary](#summary)

---

## Project Overview

**Project Name**: M.E.Doc Update Status Check
**Purpose**: Monitor M.E.Doc server updates and send Telegram notifications
**Target Platform**: Windows (M.E.Doc servers in production)
**Development & Testing**: macOS and Linux with cross-platform PowerShell 7
**Architecture**: Self-contained per-server deployment with modular design
**Language**: PowerShell 7+ (modern, actively maintained by Microsoft)
**Testing**: Pester 5.0+ (runs on PowerShell 7+)

### Platform Support Note

This project is **developed and comprehensively tested on macOS and Linux**, but **intended
for Windows production servers**. Windows-specific features (Event Log, Task Scheduler,
certificate management) are tested in production on the developer's servers only. Broader
Windows testing coverage is needed.

**Contributors should be aware:**

- ✅ All changes are tested on macOS/Linux (CI/CD pipeline)
- ⚠️ Windows-specific code should be tested on actual Windows before submission
- ⚠️ If you deploy on Windows, report any issues to help improve coverage

**License**: See [LICENSE](LICENSE) file for details

### Key Concepts

- **Modular Design**: Core logic in `lib/MedocUpdateCheck.psm1`, configuration separate, wrapper minimal
- **Server-Specific Configuration**: Each server gets its own `Config-$env:COMPUTERNAME.ps1` file (hostname-based)
- **Checkpoint System**: Per-server `last_run_serverXX.txt` files to prevent duplicate notifications
- **Windows-1251 Encoding**: Support for Cyrillic (Ukrainian) text in M.E.Doc logs
- **Telegram Integration**: RESTful API calls to send notifications

---

## Getting Started

### For First-Time Contributors

1. **Fork the repository** (if using GitHub)
2. **Clone your fork** locally
3. **Create a feature branch**: `git checkout -b feature/your-feature-name`
4. **Read this document** thoroughly before making changes
5. **Follow the guidelines** in all sections below
6. **Test your changes** using the test framework
7. **Submit a pull request** with a clear description

### Development Setup

**Requirements**: PowerShell 7.0 or later

```powershell
# Verify PowerShell version
pwsh -Command '$PSVersionTable.PSVersion'
# Expected: 7.x or higher

# Clone the repository
git clone https://github.com/yourusername/medoc-update-check.git
cd medoc-update

# Install Pester if needed (PowerShell 7+ only)
pwsh -Command "Install-Module Pester -Force -SkipPublisherCheck"

# Run tests to verify setup
pwsh ./tests/Run-Tests.ps1

# Install PSScriptAnalyzer for code analysis
pwsh -Command "Install-Module PSScriptAnalyzer -Force"
```

---

## Architecture and Design Principles

### Core Principles

1. **Separation of Concerns**
   - `lib/MedocUpdateCheck.psm1`: Pure business logic (log parsing, update detection, message
     formatting) - no hardcoded values, no direct Telegram calls, no Event Log writes. All
     config-driven.
   - `Run.ps1`: Universal entry point - loads config, calls module functions, handles Telegram
     sending and Event Log writing
   - `configs/Config-$env:COMPUTERNAME.ps1`: Server-specific settings only (ServerName,
     MedocLogsPath, BotToken, ChatId, checkpoint location) - auto-generated filename
   - `utils/Setup-Credentials.ps1`: Credential encryption setup - creates/manages self-signed
     certificate, encrypts credentials using CMS
   - `utils/Setup-ScheduledTask.ps1`: Task Scheduler automation - creates scheduled task with
     PowerShell 7+ execution
   - `utils/Validate-Scripts.ps1`: Development validation - syntax checking for all PowerShell
     scripts
   - `utils/Get-TelegramCredentials.ps1`: Helper script - decrypts credentials when config
     loads

2. **No Hardcoded Values in Module**
   - All settings must come from configuration
   - All paths must be configurable
   - All credentials must be passed via config

3. **PowerShell 7+ Requirement**
   - All code must be compatible with PowerShell 7.0 or later
   - Use modern PowerShell features (string interpolation, nullable types, etc.)
   - Use `#Requires -Version 7.0` directive in all scripts
   - Don't break existing function signatures (backward compatibility within PS7+)
   - **NEVER use removed cmdlets or deprecated features** - see "Deprecated Features to AVOID" below

4. **Error Handling**
   - Return meaningful error objects, don't throw silently
   - Log all errors to Windows Event Log
   - Provide detailed error messages for debugging

5. **Idempotency**
   - Running the script multiple times should be safe
   - Checkpoint system prevents duplicate notifications
   - No partial state left on error

6. **Universal Code: System Variables Instead of Hardcoded Paths**
   - **NEVER hardcode** system paths like `C:\ProgramData` or `C:\Windows`
   - **ALWAYS use** PowerShell system variables for universal compatibility:
     - `$env:ProgramData` - System program data directory (default: `C:\ProgramData`)
     - `$env:COMPUTERNAME` - Server hostname (for config filenames, auto-detection)
     - `$env:SystemRoot` - Windows installation directory (default: `C:\Windows`)
     - `$env:TEMP`, `$env:TMP` - Temporary directory
     - `$env:USERNAME`, `$env:USERDOMAIN` - Current user info
   - **Why?** Different Windows installations may have custom drive layouts or paths
   - **Example - Hardcoded (❌ BAD):**

     ```powershell
     $credDir = "C:\ProgramData\MyApp\creds"
     ```

   - **Example - Universal (✅ GOOD):**

     ```powershell
     $credDir = "$env:ProgramData\MyApp\creds"
     ```

### File Organization

```text
Project Root/
├── lib/                                      # Core module (reusable, config-driven)
│   └── MedocUpdateCheck.psm1                 # Main module: 6 exported functions (business logic only)
├── configs/                                  # Server configurations (per-server)
│   ├── Config.template.ps1                   # Template with all options (copy and customize)
│   └── Config-$COMPUTERNAME.ps1              # Auto-named per-server config (user creates)
├── Run.ps1                                   # Universal entry point (all servers use this)
├── utils/                                    # Utility and helper scripts (development & deployment)
│   ├── Setup-Credentials.ps1                 # Credential encryption setup
│   ├── Setup-ScheduledTask.ps1               # Task Scheduler automation
│   ├── Get-TelegramCredentials.ps1           # Helper: decrypt credentials for config
│   └── Validate-Scripts.ps1                  # Development: validate PowerShell syntax
├── tests/                                    # Comprehensive test suite
│   ├── Run-Tests.ps1                         # Test runner script
│   ├── MedocUpdateCheck.Tests.ps1            # Pester tests (105+ test cases)
│   └── test-data/                            # Test log scenarios (Windows-1251 encoded)
│       ├── dual-log-success/                 # Successful update scenario
│       ├── dual-log-no-update/               # No update detected
│       ├── dual-log-missing-updatelog/       # Update log missing
│       ├── dual-log-missing-flag1/           # Infrastructure flag missing
│       ├── dual-log-missing-flag2/           # Service restart flag missing
│       └── dual-log-missing-flag3/           # Version confirmation flag missing
├── .github/
│   └── workflows/
│       └── tests.yml                         # CI/CD pipeline (GitHub Actions)
├── .gitignore                                # Git security settings
├── .markdownlint.json                        # Markdown linting configuration
├── README.md                                 # Main documentation (quick start, features)
├── DEPLOYMENT.md                             # Step-by-step deployment procedures
├── TESTING.md                                # Testing procedures and examples
├── SECURITY.md                               # Security, credentials, Event Log
├── CONTRIBUTING.md                           # This file (contributor guidelines)
├── AGENTS.md                                 # For AI agents (Claude, Copilot, Cursor)
├── CLAUDE.md                                 # Symlink to AGENTS.md (Claude Code compatibility)
├── CODE_OF_CONDUCT.md                        # Community standards
├── LICENSE                                   # Apache 2.0 license
└── NOTICE                                    # Attribution and dependencies
```

---

## PowerShell Code Guidelines

### Style Guide

1. **Naming Conventions**
   - Functions: `Verb-Noun` format (e.g., `Test-UpdateOperationSuccess`)
   - Variables: `$camelCase` (e.g., `$logPath`, `$botToken`)
   - Constants: `$CONSTANT_CASE` (e.g., `$ENCODING_CODEPAGE`)
   - Private functions: Prefix with underscore (e.g., `_Get-LogLines`)

2. **Function Documentation**
   - Always use comment-based help blocks
   - Include SYNOPSIS, DESCRIPTION, PARAMETER, OUTPUTS, EXAMPLE
   - Document all parameters with type and description
   - Document return values or side effects

3. **Parameter Declaration**

   ```powershell
   param(
       [Parameter(Mandatory = $true)]
       [ValidateNotNullOrEmpty()]
       [string]$MedocLogsPath,

       [Parameter(Mandatory = $false)]
       [int]$EncodingCodePage = 1251
   )
   ```

   - Always use `[Parameter(...)]` attributes
   - Always specify `Mandatory` and default values
   - Use `[ValidateXxx]` attributes where appropriate
   - Order: required parameters first, then optional with defaults

4. **Code Formatting**
   - Indentation: 4 spaces (not tabs)
   - Line length: Keep under 100 characters when possible
   - Braces: Opening brace on same line, closing on new line
   - Use explicit casting: `[int]$value` not `$value -as [int]`

5. **Variable Usage**
   - Declare variables near their first use
   - Use descriptive names: `$updateStartTime` not `$t1`
   - Avoid Hungarian notation: `$logPath` not `$strLogPath`
   - Use `$null` comparisons explicitly

6. **Error Handling**

   ```powershell
   try {
       # Operation
   } catch {
       Write-Error "Description: $_"
       return @{
           Status  = "Error"
           ErrorId = [MedocEventId]::GeneralError  # or specific error ID
           Message = "Descriptive error message"
       }
   }
   ```

   - Always catch specific exceptions when possible
   - Provide context in error messages
   - Return status objects with `Status`, `ErrorId` (MedocEventId enum), and `Message` fields
   - Use appropriate `MedocEventId` enum value for ErrorId
   - Log to Event Log for production use via `Write-EventLogEntry`
   - Never throw exceptions from core functions; return error status objects instead

7. **Comments - International Standard**

   **Language**: Always use English for all code comments and documentation
   - This is a **mandatory requirement** for international projects
   - Ensures consistency across all code and documentation
   - Facilitates code review and maintenance
   - Follows industry best practices for open-source projects

   **Comment Style Guidelines**:
   - Use comments to explain WHY, not WHAT
   - Bad: `# Increment counter`
   - Good: `# Move past the update start line to find result message`
   - One space after `#`: `# Comment` not `#Comment`
   - Capitalize first letter: `# This is a comment` not `# this is a comment`
   - End with period for complete sentences: `# Parse version from log.`
   - No period for fragments: `# Success case` (not `# Success case.`)

   Example: Correct Comment Format

   ```powershell
   # Skip entries before checkpoint time to avoid duplicate notifications
   if ($SinceTime -and $timestamp -le $SinceTime) {
       continue
   }
   ```

8. **String Handling**

   ```powershell
   # Use single quotes for literals
   $path = 'C:\Scripts'

   # Use double quotes for interpolation
   Write-Host "Found $count files"

   # Use @' '@ for multi-line strings
   $message = @'
   Line 1
   Line 2
   '@
   ```

9. **Return Values**
   - Return objects, not strings
   - Use consistent return types
   - Example from `Test-UpdateOperationSuccess`:

   ```powershell
   @{
       Success                = $true
       TargetVersion          = "11.02.186"
       UpdateTime             = [datetime]"2025-07-29 05:00:59"
       UpdateLogPath          = "D:\MedocSRV\LOG\update_2025-07-29.log"
       Flag1_Infrastructure   = $true
       Flag2_ServiceRestart   = $true
       Flag3_VersionConfirm   = $true
       Reason                 = "All success flags confirmed"
   }
   ```

### Common Patterns

1. **Configuration Validation**

   ```powershell
   $requiredKeys = @('ServerName', 'MedocLogsPath', 'BotToken', 'ChatId')
   foreach ($key in $requiredKeys) {
       if ($key -notin $config.Keys) {
           Write-Error "Missing required config key: $key"
           return $null
       }
   }
   ```

2. **File Path Handling**

   ```powershell
   # Normalize paths
   $logsPath = Resolve-Path $config.MedocLogsPath -ErrorAction Stop

   # Use Join-Path for combinations
   $checkpointPath = Join-Path $PSScriptRoot "last_run_server01.txt"
   ```

3. **Encoding Support**

   ```powershell
   $encoding = [System.Text.Encoding]::GetEncoding($EncodingCodePage)
   $logContent = Get-Content $logPath -Encoding $encoding
   ```

4. **DateTime Handling**

   ```powershell
   # Parse M.E.Doc format: "27.07.2025 5:00:59"
   $timestamp = [datetime]::ParseExact($line, "dd.MM.yyyy H:mm:ss", $null)

   # Save checkpoint
   $timestamp | Set-Content $checkpointFile
   ```

---

## Testing Guidelines

### Test Organization

1. **Structure**
   - All tests in `tests/MedocUpdateCheck.Tests.ps1`
   - Test data in `tests/test-data/` folder
   - Sample logs must be realistic and anonymized
   - Use Pester's `Describe`/`Context`/`It` syntax

2. **Test Coverage Requirements**
   - Minimum 80% code coverage (target: 90%+)
   - All exported functions must have tests
   - All error paths must be tested
   - All parameters must be tested

3. **Test Data Standards**
   - **Encoding**: Windows-1251 (Cyrillic support)
   - **Language**: Ukrainian (authentic M.E.Doc text)
   - **Format**: Realistic M.E.Doc log format
   - **Scenarios**: Success, failure, no-update, timeout, edge cases
   - **Anonymization**: Replace real server names, dates acceptable

4. **Test Naming**

   ```powershell
   It "Should detect successful update from log file" {
       # Pattern: "Should [expected behavior] [when/with...]"
   }
   ```

5. **Test Data Examples**
   - **Successful Update**: 7-minute update completing successfully
   - **Failed Update**: Initial failure, retry on next day with success
   - **No Update**: Multiple "no new updates" entries spanning hours
   - **Timeout**: 25-minute update exceeding 15-minute default timeout

6. **Mocking External Calls** (Critical for Unit Tests)

   When mocking functions that make external calls (API calls, file I/O, etc.), **always
   scope the mock to the module** to prevent accidental network calls:

   ```powershell
   # ✅ CORRECT: Mock is scoped to the module, won't affect other modules
   Mock Invoke-RestMethod {
       return @{ ok = $true; result = @{ message_id = 12345 } }
   } -ModuleName MedocUpdateCheck

   # ❌ WRONG: Global mock could affect unrelated code
   Mock Invoke-RestMethod {
       return @{ ok = $true; result = @{ message_id = 12345 } }
   }
   ```

   This prevents tests from:
   - Making actual network requests to Telegram API
   - Accidentally hitting production endpoints
   - Causing test flakiness due to network timeouts
   - Interfering with other modules' mocks

   **Pattern to follow for new external calls:**
   - `Mock CommandName { ... } -ModuleName MedocUpdateCheck` for internal module functions
   - `Mock CommandName { ... }` only for functions you're testing directly
   - Always include `-ModuleName` when mocking calls **within** module code

7. **Running Tests**

   ```powershell
   # Run all tests
   .\tests\Run-Tests.ps1

   # Run specific test file
   Invoke-Pester tests/MedocUpdateCheck.Tests.ps1

   # Run with coverage
   .\tests\Run-Tests.ps1 -OutputFormat JUnitXml
   ```

### Test Template

```powershell
Describe "Test-UpdateOperationSuccess" {
    BeforeEach {
        $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    }

    It "Should detect successful update from dual logs" {
        # Arrange
        $logsPath = Join-Path $script:testDataDir "dual-log-success"

        # Act
        $result = Test-UpdateOperationSuccess -MedocLogsPath $logsPath

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Success | Should -Be $true
    }
}
```

---

## Documentation Guidelines

### Documentation Hierarchy

1. **README.md** (Main Entry Point)
   - Quick start (3 steps)
   - Feature overview
   - Installation instructions
   - Configuration reference
   - Deployment scenarios
   - Troubleshooting
   - Link to other docs

2. **TESTING.md** (Testing Procedures)
   - Manual testing procedures
   - Automated testing with Pester
   - Test data format explanation
   - Troubleshooting common issues
   - CI/CD integration

3. **SECURITY.md** (Security Procedures)
   - Credential management
   - Event Log monitoring
   - Encoded value handling
   - Deployment security checklist

4. **CONTRIBUTING.md** (This File)
   - For all contributors
   - Code style guidelines
   - Testing requirements
   - Quality standards
   - How to contribute

5. **NOTICE** (Legal/Attribution)
   - Copyright information
   - Dependencies
   - External services

6. **CODE_OF_CONDUCT.md** (Community)
   - Contributor guidelines
   - Code of conduct
   - Community standards

### Documentation Standards for Human Contributors

#### Finding Existing Content (Before Writing)

**Critical:** Always check if content already exists before creating new documentation.

1. **Search existing docs first**

   ```bash
   # Search for topic in all markdown files
   grep -r "ServerName\|Event Log\|Windows-1251" *.md
   ```

2. **Check documentation map** in README.md for where content should go

3. **Prefer references over duplication**
   - If content exists elsewhere, link to it
   - Example: "For detailed Event Log queries, see [TESTING.md - Event Log Query Examples](TESTING.md#event-log-query-examples)"
   - Don't copy-paste; instead reference the authoritative source

#### Consistency Rules

**Single Source of Truth Principle:**

- One concept = one authoritative location
- All other files reference that location
- Examples of authoritative locations:
  - Event Log Queries → TESTING.md (Tier 1 consolidation)
  - ServerName Configuration → SECURITY.md (Tier 1 consolidation)
  - Windows-1251 Encoding → SECURITY.md (Tier 2 consolidation)
  - Glossary → README.md (Tier 2 addition)

**Maintaining Consistency:**

- When updating information, update the authoritative source
- Then verify cross-references in other docs still work
- Use find-and-replace carefully to update multiple references

#### Avoiding Duplication

**DON'T:**

```markdown
# In README.md
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 20

# Then again in TESTING.md
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'M.E.Doc Update Check'
} -MaxEvents 10

# And again in SECURITY.md...
```

**DO:**

```markdown
# In README.md
For Event Log queries, see [TESTING.md - Event Log Query Examples](TESTING.md#event-log-query-examples)

# In TESTING.md
## Event Log Query Examples
(One comprehensive location with all variations)

# In SECURITY.md
See [Event Log Query Examples in TESTING.md](TESTING.md#event-log-query-examples) for detailed queries.
```

#### Selecting the Appropriate Document

**README.md** - Quick overview, getting started, glossary

- Target: New users, quick reference
- Include: Project summary, feature list, example messages, glossary

**DEPLOYMENT.md** - Step-by-step procedures

- Target: System administrators
- Include: Setup steps, configuration, deployment patterns, credential management

**TESTING.md** - Test procedures and examples

- Target: QA, developers, testers
- Include: Test procedures, message formats, event log queries, version parsing

**SECURITY.md** - Security and credentials

- Target: Security administrators, ops
- Include: Credential management, CMS encryption, encoding, server naming, SYSTEM user

**CONTRIBUTING.md** - For contributors

- Target: Developers, maintainers
- Include: Code standards, testing, git workflow, documentation guidelines

**AGENTS.md** - For AI agents

- Target: Claude, Copilot, Cursor
- Include: Code generation guidelines, PowerShell standards, comment rules

#### Pre-Commit Documentation Checklist

**Critical:** Before submitting ANY documentation changes, use this comprehensive checklist:

**Search & Duplication Check (CRITICAL):**

- [ ] `grep -r "YourTopic" *.md` — Search for existing content
- [ ] Identify if topic is already documented elsewhere
- [ ] If found, reference it instead of duplicating
- [ ] Search for duplicates of THIS new content after writing
- [ ] Consolidate similar content if found scattered across files

**Consistency & Accuracy Check:**

- [ ] Verify content matches the actual codebase (check code examples, versions)
- [ ] **CRITICAL: Use function/section names, NOT line numbers** (see AGENTS.md for examples)
- [ ] Verify content matches actual test behavior (run tests to confirm)
- [ ] Check all references to other files/sections are correct
- [ ] Ensure terminology matches project glossary/standards
- [ ] Verify no hardcoded values that will become stale (use commands instead)
- [ ] Check all links are valid and point to correct sections
- [ ] Ensure glossary terms used consistently throughout

**Technical Quality Check:**

- [ ] Verify markdown linting passes (`npx markdownlint-cli2 *.md`)
- [ ] Check for duplicate headings (MD024)
- [ ] Verify proper heading hierarchy (MD025/MD026)
- [ ] Ensure blank lines before lists (MD032)
- [ ] Confirm fenced code blocks have language identifiers (MD031/MD040)
- [ ] No orphaned references (links to non-existent sections)
- [ ] Update Table of Contents if section structure changed

**Strategic Distribution Check:**

- [ ] Identify the audience (users vs developers vs AI agents)
- [ ] Place content in the right document for that audience
- [ ] Add cross-references in related docs (don't duplicate, reference)
- [ ] Verify related documentation links back (if needed)

**See Also:** [AGENTS.md - Pre-Commit Documentation Checklist](AGENTS.md#pre-commit-documentation-checklist) for detailed examples and patterns.

#### Documentation Update Workflow

1. **Identify the change**
   - Code change → Update related docs
   - New feature → Update appropriate doc sections
   - Bug fix → Add to troubleshooting if user-facing

2. **Find authoritative location**
   - Check existing docs first
   - Determine which file owns this topic
   - If unsure, use this priority: TESTING > SECURITY > DEPLOYMENT > README

3. **Update and verify**
   - Edit authoritative source (e.g., TESTING.md)
   - Update cross-references in other files
   - Test all links work
   - Check markdown linting passes

4. **Review standards**
   - Run markdown linting
   - Verify no duplication
   - Check glossary terms used consistently
   - Ensure examples are accurate

### Documentation Standards

1. **Always Include**
   - Purpose/description at top
   - Table of contents (if longer than 3 sections)
   - Code examples for complex concepts
   - Troubleshooting section for operational docs

2. **Avoid**
   - Redundant information between files
   - Outdated examples
   - Unexplained technical jargon
   - Dead links
   - Copy-pasting content (use references instead)

3. **Keep Updated**
   - Update docs when code changes
   - Update examples when function signatures change
   - Review docs during code review
   - Check for broken links annually

---

## Markdown Style Guide

### Markdown Linting Rules (markdownlint compatible)

**Critical Rules** (Must not violate):

1. **MD022** - Headings surrounded by blank lines

   ```markdown
   Good:

   ## Heading

   Content here

   Bad:
   ## Heading
   Content here
   ```

2. **MD031** - Code blocks surrounded by blank lines

   ```markdown
   Good:

   \`\`\`powershell
   code
   \`\`\`

   Bad:
   \`\`\`powershell
   code
   \`\`\`
   Content
   ```

3. **MD032** - Lists preceded and followed by blank lines

   ```markdown
   Good:

   - Item 1
   - Item 2

   Next paragraph

   Bad:
   - Item 1
   - Item 2
   Next paragraph
   ```

4. **MD040** - Code blocks must have language identifier

   ```markdown
   Good:
   \`\`\`powershell
   code
   \`\`\`

   Bad:
   \`\`\`
   code
   \`\`\`
   ```

5. **MD034** - Links must be markdown formatted

   ```markdown
   Good:
   [https://example.com](https://example.com)

   Bad:
   https://example.com
   ```

6. **MD013** - Line length (configured in `.markdownlint.json`)

   ```markdown
   Good:
   This explanation provides context about something complex in
   the codebase.

   Bad (too long):
   This explanation provides context about something very complex.
   ```

   **When fixing MD013:**
   - Break at logical sentence/clause boundaries
   - Preserve all information (never delete to shorten lines)
   - Acceptable exceptions: table cells, code blocks, URLs, file paths
   - Use proper indentation when breaking list items

**Warnings to Fix**:

1. **MD012** - No more than one consecutive blank line

   ```markdown
   Good:
   Line 1

   Line 2

   Bad:
   Line 1


   Line 2
   ```

### Markdown Structure

1. **Headings**
   - Start with `# Main Title` (H1)
   - Use `##` for sections (H2)
   - Use `###` for subsections (H3)
   - Maximum nesting: 4 levels

2. **Lists**
   - Use `-` for unordered lists
   - Use `1.` for ordered lists
   - Consistent indentation (2-4 spaces)
   - Blank line before and after

3. **Code Blocks**
   - Always include language identifier: `` ```powershell ``
   - Blank line before opening fence
   - Blank line after closing fence
   - Include descriptive text above code blocks

4. **Tables**

   ```markdown
   | Column 1 | Column 2 |
   |----------|----------|
   | Value 1  | Value 2  |
   ```

5. **Links and References**
   - Use markdown link format: `[text](url)`
   - Relative paths for internal files: `[filename.md](path/to/file.md)`
   - Full URLs for external links

### Markdown Formatting Examples

**Headers with blank lines:**

```markdown
# Main Title

## Section 1

### Subsection 1.1

## Section 2
```

**Code blocks with context:**

```markdown
To run tests, use the following command:

\`\`\`powershell
.\tests\Run-Tests.ps1
\`\`\`

This will run all Pester tests.
```

**Lists with blank lines:**

```markdown
Features:

- Feature 1
- Feature 2

Requirements:

1. PowerShell 5.1
2. Pester 5.0
```

---

## Commit and Git Guidelines

### Commit Message Format

This project follows **Conventional Commits** specification ([https://www.conventionalcommits.org/](https://www.conventionalcommits.org/)).

**Format:**

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Example:**

```text
feat(credentials): add CMS encryption with certificate rotation

Implement Cryptographic Message Syntax encryption for Telegram
credentials with automatic certificate rotation on expiry or
validation failure. Certificates meet CMS requirements for
Document Encryption and work with SYSTEM user.

- Create self-signed DocumentEncryptionCert with 5-year validity
- Validate existing certificates meet CMS requirements
- Auto-rotate if expired or missing required EKU
- Restrict permissions to SYSTEM + Administrators

Fixes: #42
```

**Types**:

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Test additions/modifications
- `refactor:` - Code restructuring (no behavior change)
- `perf:` - Performance improvements
- `style:` - Code formatting (no behavior change)
- `chore:` - Build, dependencies, tooling, CI/CD
- `ci:` - CI/CD configuration

**Scope** (optional but recommended):

- `credentials` - Credential/security changes
- `tests` - Test suite changes
- `docs` - Documentation changes
- `config` - Configuration changes
- `workflow` - GitHub Actions/CI changes

**Subject line rules:**

- Use imperative mood ("add" not "added" or "adds")
- Start with lowercase (unless proper noun)
- No period at end
- Maximum 50 characters

**Body** (optional for non-trivial changes):

- Explain WHY, not WHAT
- Wrap at 72 characters
- Separate from subject with blank line

**Footer** (optional):

- Reference issues: `Fixes: #123`, `Closes: #456`
- Breaking changes: `BREAKING CHANGE: description`

### ⚠️ PII & Sensitive Data - Critical Before Committing

**IMPORTANT:** Do NOT commit real PII, credentials, or organizational information.

**Never commit (PII - Personally Identifiable Information):**

- Real Telegram chat IDs or user identifiers (uniquely identifies person/organization)
- Email addresses with real names or domains (except generic `user@example.com`)
- Organizational structure details (office locations, divisions, departments, company names)

**Never commit (Sensitive Credentials & Secrets):**

- Real Telegram bot tokens, API keys, or any credentials
- Real server names or hostnames that identify infrastructure
- Infrastructure provider names or abbreviations
- Real IP addresses, domain names, or UNC network paths
- Configuration files with real values (only commit `Config.template.ps1`)

**Always use instead:**

- Generic examples: `MEDOC-SRV01`, `MEDOC-SRV02`, `MY-MEDOC-SERVER`, `TARGET-SERVER`
- Placeholders: `YOUR_SERVER_NAME`, `EXAMPLE-SERVER`
- Format-only: `192.168.0.x`, `user@example.com`, `123456:ABC...`

### Commit Checklist

Before committing, verify:

- [ ] **No real server names** (check examples use `MEDOC-SRV*` or `MY-*` pattern)
- [ ] **No IP addresses or domain names** (except format-only examples)
- [ ] **No credentials or sensitive data** (tokens, keys, real chat IDs)
- [ ] **No organizational structure details** (office names, divisions)
- [ ] All tests pass
- [ ] No PSScriptAnalyzer **errors** (warnings are acceptable and documented in AGENTS.md)
- [ ] No markdown linting violations
- [ ] Documentation updated if needed
- [ ] .gitignore patterns up to date

### What to Commit

**✅ DO Commit:**

- PowerShell code files (.ps1, .psm1)
- Test files (tests/*.ps1)
- Configuration templates (configs/Config.template.ps1)
- Documentation (.md files)
- Workflow files (.github/workflows/)
- .gitignore updates

**❌ DON'T Commit:**

- Real config files (configs/Config-*.ps1 - server-specific files, use .gitignore)
- Checkpoint files (last_run_*.txt)
- Log files (*.log)
- Credentials or tokens
- IDE files (.vscode/, .idea/)
- Backup files (`*.bak`, `*~`)

### .gitignore Maintenance

Current patterns protect:

```gitignore
# Sensitive configs (but template is tracked)
configs/Config-*.ps1
!configs/Config.template.ps1

# Runtime/checkpoint files
last_run_*.txt

# Logs and backups
*.log
*.bak

# IDE files
.vscode/
.idea/
```

When adding new files:

- Ask: "Does this contain sensitive data?"
- If yes, add to .gitignore
- If no, commit it
- Document the decision

---

## Code Quality Checklist

### Before Creating/Modifying Code

1. **PowerShell Code**
   - [ ] Follows naming conventions (Verb-Noun, camelCase)
   - [ ] Uses comment-based help on functions
   - [ ] Has proper parameter validation
   - [ ] Error handling is comprehensive
   - [ ] No hardcoded values (except examples)
   - [ ] Compatible with PowerShell 7.0+
   - [ ] No PSScriptAnalyzer **errors** (warnings only fail if blocking the build)

2. **Tests**
   - [ ] New functions have test coverage
   - [ ] Test data is realistic and anonymized
   - [ ] Tests follow Pester conventions
   - [ ] Edge cases are tested
   - [ ] All tests pass locally
   - [ ] Test output is clear and readable

3. **Documentation**
   - [ ] Function comments explain purpose
   - [ ] Code examples are accurate
   - [ ] README is up to date
   - [ ] Related docs are updated
   - [ ] All markdown passes linting
   - [ ] Links are correct and current

4. **Configuration**
   - [ ] Example configs are accurate
   - [ ] Placeholder values are clear (YOUR_BOT_TOKEN_HERE)
   - [ ] Comments explain each setting
   - [ ] Encoding defaults match production use

5. **Security**
   - [ ] No credentials in code
   - [ ] No real tokens or IDs in examples
   - [ ] Sensitive files in .gitignore
   - [ ] Error messages don't expose paths
   - [ ] File permissions are appropriate

### Running Quality Checks

#### PowerShell Script Validation

**IMPORTANT:** Two validation tools serve different purposes:

| Tool | Purpose | Required? |
|------|---------|-----------|
| **Validate-Scripts.ps1** | Syntax checking | ✅ Always |
| **PSScriptAnalyzer** | Code quality | ⚠️ Recommended |

##### Quick validation (recommended)

Always run syntax validation before committing:

```powershell
# Use the built-in validation utility (REQUIRED)
pwsh ./utils/Validate-Scripts.ps1

# With verbose details
pwsh ./utils/Validate-Scripts.ps1 -Verbose
```

##### Complete validation workflow

```powershell
# 1. Check PowerShell version
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
# Expected: 7.x or higher

# 2. Validate syntax of all scripts (REQUIRED)
pwsh ./utils/Validate-Scripts.ps1

# 3. Run unit tests
./tests/Run-Tests.ps1

# 4. Check code quality (optional but recommended)
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    pwsh -NoProfile -Command {
        Import-Module PSScriptAnalyzer -Force
        Invoke-ScriptAnalyzer -Path ./lib, ./utils, ./tests -Recurse
    }
} else {
    Write-Host "PSScriptAnalyzer not installed (optional)"
    Write-Host "Install with: pwsh -Command 'Install-Module PSScriptAnalyzer -Force'"
}
```

**What each tool checks:**

- **Validate-Scripts.ps1:** Syntax errors, parsing errors, invalid keywords, balanced brackets
- **PSScriptAnalyzer:** Code style, best practices, security issues, performance problems

##### Expected PSScriptAnalyzer Warnings

When you run PSScriptAnalyzer, you may see these warnings - **they are acceptable and do not need to be fixed:**

| Warning | Where | Reason | Status |
|---------|-------|--------|--------|
| **PSAvoidUsingWriteHost** | Test files, Run-Tests.ps1 | CLI scripts use colored console output | ✅ Expected - necessary for user-friendly output |
| **PSUseBOMForUnicodeEncodedFile** | Multiple files | Files contain Cyrillic (Ukrainian) text | ✅ Expected - BOM is optional |
| **PSReviewUnusedParameter** | Test mock functions | Mock functions must match signature | ✅ Expected - necessary for mocking |
| **PSUseShouldProcessForStateChangingFunctions** | MedocUpdateCheck.psm1:617 | Helper function, not state-changing | ✅ Expected - helpers don't need ShouldProcess |

**Important:** These are style warnings, not errors. They don't affect functionality or
security. The project legitimately needs `Write-Host` for interactive scripts and status
messages with colors.

**CI/CD Behavior:** GitHub Actions only fails on PSScriptAnalyzer **Errors**, not warnings.
See AGENTS.md for complete list of expected warnings.

#### Other Checks

```powershell
# Run Pester tests
./tests/Run-Tests.ps1

# Check markdown (requires Node.js)
npm install -g markdownlint-cli
markdownlint "**/*.md"
```

---

## Credential and ServerName Handling

### Secure Credential Storage (SYSTEM User Compatible)

This project uses CMS (Cryptographic Message Syntax) encryption with self-signed LocalMachine
certificate for credentials to work with Task Scheduler running as SYSTEM user.

**Key Points for Contributors:**

1. **Never modify credential handling without SYSTEM user testing**
   - Any credential-related changes must work when running as SYSTEM user
   - Use CMS encryption with LocalMachine certificate (not user-scoped encryption)
   - Test with SYSTEM user context in Task Scheduler before submitting PR

2. **Utility: Setup-Credentials.ps1**
   - Located in `utils/Setup-Credentials.ps1`
   - Creates/verifies self-signed certificate in LocalMachine\My store
   - Certificate: CN=M.E.Doc Update Check Credential Encryption, 5-year validity, NonExportable RSA-2048
   - Encrypts credentials using Protect-CmsMessage with certificate public key
   - Sets restrictive file permissions (SYSTEM + Administrators only)
   - Supports both interactive and non-interactive modes
   - Auto-rotates certificate if expiring (< 30 days)

3. **Config File Credential Loading**
   - `Config.template.ps1` sources `utils/Get-TelegramCredentials.ps1`
   - Automatically loads encrypted credentials from `$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms`
   - Decrypts using Unprotect-CmsMessage with LocalMachine certificate private key
   - Works transparently in SYSTEM user context
   - Never stores plain text credentials in config files

### Hybrid ServerName Detection

Implement ServerName auto-detection with manual override capability:

```powershell
# Pattern for ServerName handling
$serverName = if ($env:MEDOC_SERVER_NAME) {
    $env:MEDOC_SERVER_NAME  # Use admin-set environment variable
} else {
    $env:COMPUTERNAME       # Fall back to Windows hostname
}

# Allow explicit override in config
# $serverName = "MY_EXPLICIT_NAME"
```

**Best Practices:**

- Always provide hybrid detection (env var + fallback)
- Never hardcode server names in module code
- Allow explicit override for production safety
- Document the three options in comments
- Test auto-detection with different computer names

---

## Common Patterns and Examples

### Pattern 1: Module Function with Documentation

```powershell
function Test-UpdateOperationSuccess {
    <#
    .SYNOPSIS
        Finds and validates latest M.E.Doc update operation in dual logs.

    .DESCRIPTION
        Analyzes both Planner.log and update_YYYY-MM-DD.log files to detect
        and validate successful update completion via three-phase validation
        (infrastructure ready, service restarted, version confirmed).

    .PARAMETER MedocLogsPath
        Path to the M.E.Doc logs directory containing Planner.log and
        update_YYYY-MM-DD.log files.

    .PARAMETER EncodingCodePage
        Log file encoding code page (default: 1251 for Windows-1251/Cyrillic).

    .OUTPUTS
        [System.Collections.Hashtable] with keys:
        - Success: [bool] Update completed successfully with all flags
        - TargetVersion: [string] Updated version number (e.g., "11.02.186")
        - UpdateTime: [datetime] When update started in Planner.log
        - UpdateLogPath: [string] Path to the update_YYYY-MM-DD.log file
        - Flag1_Infrastructure: [bool] Infrastructure ready flag
        - Flag2_ServiceRestart: [bool] Service restart flag
        - Flag3_VersionConfirm: [bool] Version confirmation flag
        - Reason: [string] Human-readable status message

        Returns $null if no update found or validation fails.

    .EXAMPLE
        $result = Test-UpdateOperationSuccess -MedocLogsPath "D:\MedocSRV\LOG"
        if ($result.Success) {
            Write-Host "Update to version $($result.TargetVersion) succeeded"
            Write-Host "All validation flags confirmed: $($result.Reason)"
        }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MedocLogsPath,

        [Parameter(Mandatory = $false)]
        [int]$EncodingCodePage = 1251
    )

    # Implementation...
}
```

### Pattern 2: Error Handling with Dual Logging (Event Log + Stderr/Stdout)

**Critical:** All errors must be logged to Windows Event Log **first**, then optionally to console. This ensures:

- **Scheduled tasks** capture errors in persistent Event Log (stderr is lost)
- **Manual runs** see immediate console feedback + Event Log entries (complete debugging picture)
- **Consistency** - same error visibility regardless of execution context

**Logging Strategy by Message Type:**

#### Errors (halt execution)

```powershell
# Pattern: Log to Event Log FIRST, then Write-Error for stderr
try {
    $response = Invoke-RestMethod -Uri $telegramUrl `
        -Method Post `
        -Body ($payload | ConvertTo-Json) `
        -ErrorAction Stop

    Write-EventLogEntry -Message "Telegram notification sent successfully" `
        -EventType "Information" `
        -EventId ([MedocEventId]::Success)
} catch {
    $errorMsg = "Failed to send Telegram notification: $_"

    # Log to Event Log FIRST (persistent for scheduled tasks)
    Write-EventLogEntry -Message $errorMsg `
        -EventType "Error" `
        -EventId ([MedocEventId]::TelegramSendError)

    # Also write to stderr for manual run visibility
    Write-Error $errorMsg

    return $false
}
```

#### Warnings (non-fatal, continue execution)

```powershell
# Pattern: Log to Event Log, then Write-Warning for stderr
$warnMsg = "EncodingCodePage $($Config.EncodingCodePage) may be invalid. Using default 1251 instead."

# Log to Event Log FIRST
Write-EventLogEntry -Message $warnMsg `
    -EventType "Warning" `
    -EventId ([MedocEventId]::ConfigInvalidValue)

# Also write to stderr for manual run visibility
Write-Warning $warnMsg

$Config.EncodingCodePage = 1251
```

#### Informational (audit trail + manual visibility)

```powershell
# Pattern: Log to Event Log, then Write-Host for stdout
$infoMsg = "Update completed: Version 11.02.185 → 11.02.186"

# Log to Event Log FIRST
Write-EventLogEntry -Message $infoMsg `
    -EventType "Information" `
    -EventId ([MedocEventId]::Success)

# Also write to stdout for manual run visibility (helpful context)
Write-Host "✅ $infoMsg"
```

#### Infrastructure Warnings (Event Log only, no console)

```powershell
# Pattern: Event Log only for Event Log infrastructure issues
# (These are operational details, not application errors)
try {
    [System.Diagnostics.EventLog]::CreateEventSource($EventLogSource, $EventLogName)
} catch {
    # Write-Warning only (stderr for manual run, no Event Log to avoid circular)
    Write-Warning "Could not create Event Log source: $_"
    return
}
```

**Rationale:**

| Context | Event Log | stderr/stdout | Why |
|---------|-----------|---------------|-----|
| **Scheduled Task** | ✅ Captured (persistent) | ❌ Lost | Only Event Log visible |
| **Manual Run** | ✅ Created (audit trail) | ✅ Visible (immediate) | Complete debugging picture |
| **Error Visibility** | ✅ Permanent record | ✅ Immediate feedback | Best of both worlds |

**Benefits:**

1. Scheduled task: Errors always queryable via Event Log (no debugging blind spots)
2. Manual run: User sees both Event Log entries PLUS console feedback (immediate help)
3. Consistency: Same behavior whether running automated or manually
4. Auditability: All errors permanently recorded in Event Log
5. Debuggability: Problems never "disappear" into lost stderr streams

### Pattern 3: Configuration Validation

```powershell
function Invoke-MedocUpdateCheck {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            # Validation logic
            if ($_ -is [hashtable]) {
                $true
            } else {
                throw "Config must be a hashtable"
            }
        })]
        [hashtable]$Config
    )

    # Validate required keys
    $requiredKeys = @('ServerName', 'MedocLogsPath', 'BotToken', 'ChatId', 'CheckpointFile')
    foreach ($key in $requiredKeys) {
        if ($key -notin $Config.Keys -or [string]::IsNullOrWhiteSpace($Config[$key])) {
            Write-Error "Missing or empty required config key: $key"
            return $null
        }
    }

    # Validate paths
    if (-not (Test-Path $Config.MedocLogsPath)) {
        Write-Error "M.E.Doc logs directory not found: $($Config.MedocLogsPath)"
        return $null
    }

    # Continue with implementation...
}
```

### Pattern 4: Test with Sample Data

```powershell
Describe "Test-UpdateOperationSuccess" {
    BeforeAll {
        $script:testDataDir = Join-Path $PSScriptRoot "test-data"
        Import-Module (Join-Path $PSScriptRoot "..\lib\MedocUpdateCheck.psm1") -Force
    }

    Context "Successful Update Scenarios" {
        It "Should detect successful update from dual logs" {
            # Arrange
            $logsPath = Join-Path $script:testDataDir "dual-log-success"

            # Act
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsPath

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.Flag1_Infrastructure | Should -Be $true
            $result.Flag2_ServiceRestart | Should -Be $true
            $result.Flag3_VersionConfirm | Should -Be $true
        }

        It "Should extract correct version string" {
            # Arrange
            $logsPath = Join-Path $script:testDataDir "dual-log-success"

            # Act
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsPath

            # Assert
            $result.TargetVersion | Should -Match "^\d+\.\d+\.\d+$"
        }
    }

    Context "Error Handling" {
        It "Should return null when logs directory doesn't exist" {
            # Arrange
            $logsPath = "C:\NonExistent\Path\Logs"

            # Act
            $result = Test-UpdateOperationSuccess -MedocLogsPath $logsPath -ErrorAction SilentlyContinue

            # Assert
            $result | Should -BeNullOrEmpty
        }
    }
}
```

### Pattern 5: Markdown Section with Code Examples

```markdown
## Testing Update Detection

To test the update detection logic, use the dual-log test data:

```powershell
$result = Test-UpdateOperationSuccess `
    -MedocLogsPath ".\tests\test-data\dual-log-success" `
    -EncodingCodePage 1251

Write-Host "Update detected: $($result.Success)"
Write-Host "Version: $($result.TargetVersion)"
Write-Host "All flags confirmed: $($result.Flag1_Infrastructure -and $result.Flag2_ServiceRestart -and $result.Flag3_VersionConfirm)"
```

### Test Scenarios

| Scenario | Directory | Expected Result |
|----------|-----------|-----------------|
| Successful | dual-log-success | Success = $true, all flags = $true |
| No Updates | dual-log-no-update | $null (no update detected) |
| Missing Flag 1 | dual-log-missing-flag1 | Success = $false (infrastructure flag missing) |
| Missing Flag 2 | dual-log-missing-flag2 | Success = $false (service restart flag missing) |
| Missing Flag 3 | dual-log-missing-flag3 | Success = $false (version confirmation missing) |
| Failed Update | dual-log-failed | Success = $false (update did not complete) |
| Timeout | dual-log-timeout | $null (exceeded timeout) |

---

## Quick Reference

### File Checklist When Adding New Code

```text
For new PowerShell files:
  ✓ Has #Requires -Version 7.0
  ✓ Has comment-based help
  ✓ Follows naming conventions
  ✓ No hardcoded values
  ✓ Error handling implemented
  ✓ No PSScriptAnalyzer warnings
  ✓ Validated with: pwsh -NoProfile -Command "Test-Path './filename.ps1'"

For new tests:
  ✓ Uses Describe/Context/It structure
  ✓ Has sample test data
  ✓ Tests success and failure paths
  ✓ Tests are readable and documented
  ✓ All tests pass

For documentation:
  ✓ Markdown passes linting
  ✓ Links are correct
  ✓ Code examples are accurate
  ✓ Examples can be copy-pasted
  ✓ References related docs

For configuration:
  ✓ Uses placeholder values
  ✓ Has descriptive comments
  ✓ Includes all required keys
  ✓ Supports all deployment scenarios
```

### Common Issues and Fixes

| Issue | Solution |
|-------|----------|
| Markdown lint warnings | Run markdownlint, fix MD022, MD031, MD032, MD034, MD040, MD012 |
| PSScriptAnalyzer errors | Run `Invoke-ScriptAnalyzer`, fix warnings before committing |
| Test failures | Check test data paths, verify encoding (1251), ensure sample files exist |
| Encoding problems | Use `GetEncoding(1251)` for M.E.Doc logs, test with Ukrainian text |
| Module not loading | Verify `#Requires` directive, check file path, ensure proper export list |
| Credentials in repo | Check .gitignore patterns, verify placeholder values used |

---

## Getting Help

- **Code Questions**: Refer to PowerShell Core docs
- **Pester Questions**: See [Pester docs](https://pester.dev/)
- **Markdown Lint**: Check [markdownlint rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)
- **Architecture Questions**: Review project [README.md](README.md) and this document
- **Test Data**: See [TESTING.md - Test Data & Encoding](TESTING.md#test-data--encoding) for format documentation

---

## Code of Conduct

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md).
By participating in this project you agree to abide by its terms.

---

## Deprecated Features to AVOID

This project requires **PowerShell 7.0 or later**. PowerShell 7 removed many legacy cmdlets and features. **NEVER use these in new code:**

### ❌ Event Log Cmdlets (Removed in PS7+)

| Cmdlet | Replacement | Why |
|--------|------------|-----|
| `Get-EventLog` | Use `Get-WinEvent -FilterHashtable` | Cmdlet removed in PS7+ |
| `Write-EventLog` | Use `[System.Diagnostics.EventLog]::WriteEntry()` | Cmdlet removed in PS7+ |
| `New-EventLog` | Use `[System.Diagnostics.EventLog]::CreateEventSource()` | Cmdlet removed in PS7+ |
| `Clear-EventLog` | Use `[System.Diagnostics.EventLog]::Clear()` | Cmdlet removed in PS7+ |

**This Project:** Uses .NET `System.Diagnostics.EventLog` class instead ✅

### ❌ WMI Cmdlets (Removed in PS7+)

| Cmdlet | Replacement | Why |
|--------|------------|-----|
| `Get-WmiObject` | Use `Get-CimInstance` | Cmdlet removed in PS7+ |
| `Invoke-WmiMethod` | Use `Invoke-CimMethod` | Cmdlet removed in PS7+ |
| `Remove-WmiObject` | Use `Remove-CimInstance` | Cmdlet removed in PS7+ |
| `Register-WmiEvent` | Use `Register-CimIndicationEvent` | Cmdlet removed in PS7+ |

**This Project:** Doesn't use WMI, so no changes needed ✅

### ❌ Removed Modules (Removed in PS7+)

| Module | Replacement | Why |
|--------|------------|-----|
| `PSScheduledJob` | Use native `Register-ScheduledTask` | Module removed entirely in PS7+ |
| `PSWorkflow` | Not recommended for replacement | Module removed in PS7+ |

**This Project:** Uses native Task Scheduler cmdlets instead ✅

### ❌ Legacy Syntax (Outdated, should avoid)

```powershell
# ❌ DON'T: Legacy New-Object syntax
$obj = New-Object System.Diagnostics.EventLog

# ✅ DO: Modern constructor syntax
$obj = [System.Diagnostics.EventLog]::new()
```

```powershell
# ❌ DON'T: String concatenation
$msg = "Server: " + $name + " Status: " + $status

# ✅ DO: String interpolation
$msg = "Server: $name Status: $status"
```

### ✅ Modern PowerShell 7+ Features - USE THESE

See [AGENTS.md - PowerShell 7+ Features for Code Generation](AGENTS.md#powershell-7-features-for-code-generation) for detailed guidance on:

1. **String Interpolation** - Clean, readable strings
2. **Ternary Operator** - Concise conditionals
3. **Null Coalescing** - Smart defaults
4. **Constructor Syntax** - Modern object creation
5. **Array Methods** - Functional operations

### Code Review Checklist

Before submitting code, verify:

- ✅ No `Get-EventLog`, `Write-EventLog`, `New-EventLog` usage
- ✅ No `Get-WmiObject` or other WMI cmdlets
- ✅ No `PSScheduledJob` module imports
- ✅ No legacy `New-Object` syntax
- ✅ Using string interpolation, not concatenation
- ✅ Using `::new()` for constructors
- ✅ Using `Get-WinEvent` for Event Log queries

### Search Before Committing

```powershell
# Search for removed cmdlets in your changes
$removed = @('Get-EventLog', 'Write-EventLog', 'New-EventLog', 'Get-WmiObject')
$removed | ForEach-Object {
    if (Select-String -Path *.ps1 -Pattern $_ -Quiet) {
        Write-Warning "Found removed cmdlet: $_"
    }
}
```

---

## Summary

These guidelines ensure:

1. **Consistency** across codebase
2. **Quality** through standards and automation
3. **Clarity** in documentation
4. **Security** through practices and patterns
5. **Maintainability** for future development

For any questions or ambiguities, refer to existing code examples in the project as the reference implementation.

---

**License:** See [LICENSE](LICENSE) file for details
**Note:** For release versions and history, check git tags: `git tag -l` or `git describe --tags`
