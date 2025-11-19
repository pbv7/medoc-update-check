# AI Agent Guide

Quick-start reference for AI agents working on the M.E.Doc Update Check project. This file
provides essential context and links to specialized guides to help AI coding agents (Claude,
Gemini, GitHub Copilot, Cursor, Codeium, etc.) work effectively on this codebase.

**File:** [CLAUDE.md](CLAUDE.md) / [GEMINI.md](GEMINI.md) (universal, despite the filename)

**For humans:** See [README.md](README.md) for project overview and [CONTRIBUTING.md](CONTRIBUTING.md)
for contribution guidelines.

## Project Overview

**Project:** M.E.Doc Update Check

**Purpose:** Automated script to monitor M.E.Doc server updates and send Telegram notifications

**Language:** PowerShell 7+ (Windows native)

**Scope:** Windows-only, enterprise M.E.Doc server monitoring

**Authors:** See [README.md](README.md#authors) for list of authors and contributors

**License:** See [LICENSE](LICENSE) file for details

### Key Constraints

- **Requires PowerShell 7.0 or later** (modern, cross-platform, actively maintained by Microsoft)
- Cyrillic text support required: **Windows-1251 encoding** for M.E.Doc logs (not UTF-8)
- No external dependencies beyond PowerShell built-ins and standard modules
- Cross-platform testing: Workflow tests on Windows via GitHub Actions

## Dual-Log Update Detection Strategy

The project uses a robust three-phase validation approach to detect M.E.Doc server updates:

### Phase 1: Update Trigger Detection (Planner.log)

- Searches for "Завантаження оновлення ezvit.X.X.X-X.X.X.upd" entries
- Confirms an update was initiated on the server
- Extracts timestamp and target version number from filename

### Phase 2: Update Log File Location

- Dynamically constructs path to `update_YYYY-MM-DD.log` (DATE = update start date)
- M.E.Doc creates separate detailed logs during update process
- If log missing → update marked as FAILED

### Phase 3: Success Flag Validation (3 Mandatory Flags)

All three flags must be present for SUCCESS. Missing any flag = FAILURE:

1. **Infrastructure Validation**
   - Pattern: `IsProcessCheckPassed DI: True, AI: True`
   - Confirms: .NET infrastructure validation successful

2. **Service Restart Success**
   - Pattern: `Службу ZvitGrp запущено` (service started, accepts variations like
     "з підвищенням прав" - with elevated privileges)
   - Confirms: Core ZvitGrp service successfully restarted
   - Real log example: `Службу ZvitGrp запущено з підвищенням прав`

3. **Version Confirmation**
   - Pattern: `Версія програми - {TARGET_VERSION}` (program version - {number})
   - Confirms: System reports expected version number
   - Real log example: `Версія програми - 186` means v11.02.186 confirmed

## Project Structure

```text
medoc-update/
├── Run.ps1                          # Universal entry point (DO NOT EDIT per-server)
├── lib/
│   └── MedocUpdateCheck.psm1        # Core module with all business logic
├── configs/
│   └── Config.template.ps1          # Template with all configuration options documented
├── utils/
│   ├── Setup-Credentials.ps1        # Credential encryption helper
│   ├── Setup-ScheduledTask.ps1      # Task Scheduler automation helper
│   └── Validate-Scripts.ps1         # PowerShell syntax validator
├── tests/
│   ├── Run-Tests.ps1                # Test runner
│   ├── MedocUpdateCheck.Tests.ps1   # Pester test cases
│   └── test-data/                   # Dual-log test data (Windows-1251 encoded)
├── .github/
│   └── workflows/
│       └── tests.yml                # GitHub Actions CI/CD
├── CLAUDE.md                        # This file - for AI agents (alias)
├── GEMINI.md                        # This file - for AI agents (alias)
├── README.md                        # Human-focused project overview
├── CONTRIBUTING.md                  # Human contribution guidelines
├── SECURITY.md                      # Security best practices
├── TESTING.md                       # Human-focused testing guide
├── CODE_OF_CONDUCT.md               # Community guidelines
├── LICENSE                          # Apache 2.0 license
└── NOTICE                           # Attribution
```

## Quick Start for Agents

### 1. Code Standards & Conventions

PowerShell coding style, naming conventions, language features, and removed cmdlets to avoid.

**→ See [AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md)**

Key points:

- Use PowerShell 7+ modern features (ternary operator, string interpolation, `::new` syntax)
- **NEVER** use removed PS7+ cmdlets: `Get-EventLog`, `Get-WmiObject`, `PSScheduledJob`
- Use `$env:` variables for paths, never hardcode `C:\ProgramData`
- All comments in English
- **CRITICAL:** Planner.log uses 4-digit year regex (`\d{4}`), update_*.log uses 2-digit
  (`\d{2}`)

### 2. Testing

Test data, Pester syntax, enum usage, and validation procedures.

**→ See [AGENTS-TESTING.md](AGENTS-TESTING.md)**

Key points:

- Add `using module "..\lib\MedocUpdateCheck.psm1"` at top of test files to access enums
- Use `[MedocEventId]::Success` (not hardcoded event ID numbers)
- Test data in `tests/test-data/` is Windows-1251 encoded (NOT UTF-8)
- Use `$script:` scope for BeforeAll variables in Pester
- Run `./tests/Run-Tests.ps1` before committing

### 3. Security & Credentials

PII concerns, credential handling, and security practices.

**→ See [AGENTS-SECURITY.md](AGENTS-SECURITY.md)**

Key points:

- **NEVER** commit real Telegram tokens, chat IDs, server names, or IP addresses
- Use `utils/Setup-Credentials.ps1` for encrypted CMS credentials
- Certificates must meet CMS requirements: Document Encryption EKU, KeyEncipherment usage
- No hardcoded paths (use `$env:ProgramData`, `$env:COMPUTERNAME`, etc.)
- Pre-commit security checklist included

### 4. Documentation Maintenance

Single-source-of-truth principles, avoiding stale documentation, and avoiding duplication.

**→ See [AGENTS-DOCUMENTATION.md](AGENTS-DOCUMENTATION.md)**

Key points:

- **NEVER** hardcode dynamic values (test counts, line counts, versions)
- **Always** reference instead (e.g., "Run `./tests/Run-Tests.ps1` to verify test coverage")
- Reference authors from README.md, license from LICENSE file, versions from git tags
- Avoid line number references in documentation (use function/section names instead)
- Pre-commit documentation checklist included

### 5. Tools & Workflow

Tool selection hierarchy, git workflow, CI/CD setup, and agent interaction guidelines.

**→ See [AGENTS-TOOLS-AND-WORKFLOW.md](AGENTS-TOOLS-AND-WORKFLOW.md)**

Key points:

- Use agent tools first (Read, Grep, Glob), then project tools, then remote CLI, then ask
  for local installation
- All changes go through feature/fix branches with PR-based workflow (no direct main commits)
- Use Conventional Commits format: `<type>(<scope>): <subject>`
- **NEVER** include agent attribution banners in commits
- Complete markdown linting before submitting

## Exit Code Semantics

The `Invoke-MedocUpdateCheck` function returns structured results mapped to exit codes:

- **0** — Normal completion (Success or NoUpdate)
- **1** — Error (configuration, I/O, Telegram issues)
- **2** — UpdateFailed (validation failure)

## Common Pitfalls

### Do's

- Keep functions in `lib/MedocUpdateCheck.psm1`
- Use `Verb-Noun` naming convention
- Test data files are Windows-1251 encoded
- Use `$script:` scope in Pester BeforeAll blocks
- Document why, not what
- Run `./tests/Run-Tests.ps1` to validate work
- Check markdown before submitting changes
- Follow branch strategy (feature/fix branches from main)
- Ask user before installing modules locally
- Use `utils/Setup-Credentials.ps1` for credential encryption
- Implement hybrid ServerName detection (env var or fallback)
- Ensure all credential handling works with SYSTEM user
- **Add `using module` at top of test files to access enum types**
- **Use enum values directly in tests: `[MedocEventId]::Success`** (not hardcoded numbers)

### Don'ts

- Don't use `[datetime]$parameter = $null` (type conversion error)
- Don't commit real credentials or secrets
- Don't edit `Run.ps1` for per-server customization
- Don't assume UTF-8 for M.E.Doc logs
- Don't use deprecated Pester syntax (`-HaveKey`)
- Don't skip markdown linting before submitting
- Don't commit test data in UTF-8 format
- Don't forget blank lines before headings/lists in markdown
- Don't auto-install modules without user permission
- Don't store plain text credentials in config files
- Don't hardcode ServerName in code or configs
- Don't use user-key encryption for credentials (won't work with SYSTEM user)

## Quick Reference: What Agents Should Know

### When Modifying Event ID Logic

Event IDs are centralized in the `MedocEventId` enum in `lib/MedocUpdateCheck.psm1`:

1. **Add new Event IDs to enum first** (in the `MedocEventId` enum definition)
2. **Use enum value in code** instead of hardcoded numbers
3. **Update Test-UpdateOperationSuccess** if function returns new Status/ErrorId combinations
4. **Document in SECURITY.md** - Update Event ID reference tables
5. **Update README.md** - Ensure Event ID range list is complete
6. **Add test case** in `tests/MedocUpdateCheck.Tests.ps1`
7. **Run validation:** `pwsh ./utils/Validate-Scripts.ps1` && `./tests/Run-Tests.ps1`
8. **Verify consistency** across all files

### Validation Before Committing

```powershell
# Step 1: Syntax validation (REQUIRED)
pwsh ./utils/Validate-Scripts.ps1

# Step 2: Run tests
./tests/Run-Tests.ps1

# Step 3: Check markdown
npx markdownlint-cli2 *.md

# Step 4: Code quality (optional)
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    pwsh -NoProfile -Command {
        Import-Module PSScriptAnalyzer -Force
        Invoke-ScriptAnalyzer -Path './lib' -Recurse
    }
}
```

## Links & Resources

**Specialized Agent Guides:**

- [AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md) - Code style and conventions
- [AGENTS-TESTING.md](AGENTS-TESTING.md) - Testing practices and procedures
- [AGENTS-SECURITY.md](AGENTS-SECURITY.md) - Security and credentials
- [AGENTS-DOCUMENTATION.md](AGENTS-DOCUMENTATION.md) - Documentation maintenance
- [AGENTS-TOOLS-AND-WORKFLOW.md](AGENTS-TOOLS-AND-WORKFLOW.md) - Tools and git workflow

**Human Documentation:**

- [README.md](README.md) - Project overview
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [TESTING.md](TESTING.md) - Testing guide (human-focused)
- [SECURITY.md](SECURITY.md) - Security best practices
- [LICENSE](LICENSE) - Apache 2.0 license

---

**For help or feedback:** Check the main project repository or contact maintainers via
[README.md](README.md#authors)

**Note:** For the latest version, check the git commit history
