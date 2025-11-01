# Documentation Maintenance Guide for Agents

Comprehensive guidelines for maintaining high-quality, non-stale documentation by following
single-source-of-truth principles and avoiding duplication.

## Critical Principle: Never Hardcode Dynamic Values

**CRITICAL:** Avoid creating "stale" documentation that requires manual updates for each file.
This project follows a single-source-of-truth approach.

### Never Hardcode (Always Reference Instead)

**❌ DON'T:**

```markdown
**Version:** 1.0
**Last Updated:** October 2025
**Author:** John Doe
**License:** Apache 2.0
**Timestamp:** 2025-10-27
```

**✅ DO:**

```markdown
**Authors:** See [README.md](README.md#authors) for list of authors
**License:** See [LICENSE](LICENSE) file for details
**Note:** For release versions, check git tags: `git tag -l`
```

### Why This Matters

1. **Single Source of Truth**
   - Authors listed only in README.md
   - License terms only in LICENSE file
   - Versions only in git tags
   - No duplication = no sync issues

2. **Zero Maintenance Burden**
   - No manual updates needed when authors change
   - No stale dates or versions
   - License updates happen in one place
   - Git history handles timestamps

3. **Always Accurate**
   - Git commit shows actual update time
   - Git tags show actual releases
   - README.md is source of author info
   - LICENSE file is source of legal terms

## Dynamic Value Documentation

When documenting numeric or dynamic values (test counts, file sizes, line counts, version
numbers), **provide commands to obtain them** instead of hardcoding the values. This prevents
documentation from becoming stale.

### ❌ DON'T (Hardcoded Values - Will Become Stale)

```markdown
- **Test Count:** 74 tests passing
- **Module Size:** 265+ lines
- **Pester Version:** 5.7.1
- **Total Files:** 42 files
- **Checkpoint Size:** ~2KB per checkpoint
```

### ✅ DO (Provide Commands to Obtain Values)

```markdown
- **Test Count:** Run `./tests/Run-Tests.ps1` to verify test coverage
  (output shows "Tests Passed: X")
- **Module Size:** Check with
  `(Get-Content ./lib/MedocUpdateCheck.psm1 | Measure-Object -Line).Lines`
- **Pester Version:** Check with
  `Import-Module Pester -PassThru | Select-Object Version`
- **Total Files:** List with
  `Get-ChildItem -Recurse -File | Measure-Object | Select-Object Count`
- **Checkpoint Size:** Check with
  `Get-Item $checkpointPath | Select-Object -ExpandProperty Length`
```

### Why Dynamic Values Matter

1. **No Stale Documentation**
   - Values update automatically as code changes
   - No manual edits needed when metrics change
   - Users always see accurate information

2. **Educational Value**
   - Developers and AI agents learn how to measure metrics
   - Commands are reusable for troubleshooting
   - Demonstrates diagnostic techniques

3. **Transparency**
   - Shows exactly how values are calculated
   - Builds confidence in documentation accuracy
   - Enables independent verification

### When to Hardcode

Only hardcode values in these cases:

- **Historical examples:** "In version 1.0, we had 45 tests" (marked as historical)
- **Fixed constants:** "Event ID 1000 is reserved for success" (unchanging by design)
- **Design requirements:** "Requires PowerShell 7.0 or later" (architectural constraint)
- **Configuration templates:** `$BotToken = "YOUR_BOT_TOKEN_HERE"` (placeholder for user input)

## Best Practices for Documentation

### ✅ Reference External Sources

```markdown
# Correct approach - reference, don't copy
**License:** See [LICENSE](LICENSE) file for details
**Authors:** See [README.md](README.md#authors) for contributors
**Version:** Check git tags with `git describe --tags`
**Last Modified:** See `git log <filename>` for history
```

### ❌ Avoid Copying Information

```markdown
# Wrong approach - creates maintenance burden
**License:** Apache License 2.0, granted under terms...
**Authors:** John Doe, Jane Smith, Bob Jones
**Version:** 2.1.4 (updated 2025-10-27)
**Last Modified:** Yesterday at 3:45 PM
```

## Markdown Link Format

Always use markdown links to point to actual sources:

```markdown
- [README.md](README.md#authors) - for author information
- [LICENSE](LICENSE) - for license details
- [SECURITY.md](SECURITY.md) - for security procedures
- [CONTRIBUTING.md](CONTRIBUTING.md) - for contribution guidelines
```

## Table of Responsibility

| Information | Location | Update Method |
|---|---|---|
| Authors/Contributors | README.md | Edit file directly |
| License Terms | LICENSE file | Edit file directly |
| Release Versions | Git tags | `git tag -a vX.Y.Z` |
| Last Updated | Git history | Automatic via commits |
| Code Examples | Documentation files | Edit markdown directly |
| Markdown Style | .markdownlint.json | Config file |

## Line Number References - AVOID (Fragile)

Documentation must NOT reference code by line number. Line numbers change whenever code is
edited, making references stale and misleading.

### ❌ DON'T (Fragile - will break on edits)

```markdown
See lib/MedocUpdateCheck.psm1 (lines XX-YY) for the enum definition.
Uses .NET EventLog class (lib/MedocUpdateCheck.psm1:AAA-BBB).
Update the outcome mapping (around line ZZZ in module).
TESTING.md lines CCC-DDD show the quick reference.
```

### ✅ DO (Stable - survives code edits)

```markdown
See the `MedocEventId` enum definition in lib/MedocUpdateCheck.psm1.
Uses .NET EventLog class in the `Write-EventLogEntry` function.
Update the outcome switch statement in `Invoke-MedocUpdateCheck`.
See the "Event ID Quick Reference" section in TESTING.md.
```

### Why

- Line numbers change frequently with code edits
- Future maintainers see stale, incorrect references
- Developers might make changes in wrong locations
- Function/section names remain stable

**Exception:** Line numbers in code *examples* within backticks (e.g., showing error output)
are acceptable.

## Before Writing/Modifying Documentation

### Critical Workflow

Always follow this workflow to maintain quality and avoid duplication:

#### 1. Search Existing Documentation First

Before proposing or writing ANY documentation:

```powershell
# Search for existing content
grep -r "YourTopicHere" *.md

# Examples:
grep -r "Event Log" *.md
grep -r "ServerName" *.md
grep -r "Windows-1251" *.md
grep -r "encoding" *.md
```

If content exists, reference it instead of duplicating it.

#### 2. Identify Authoritative Source

When content exists in multiple places, identify which file is authoritative:

| Topic | Authoritative Source | Policy |
|-------|----------------------|--------|
| Event Log Queries | TESTING.md | Other files link only |
| ServerName Configuration | SECURITY.md | Other files link only |
| Windows-1251 Encoding | SECURITY.md | Other files link only |
| Glossary Terms | README.md | Use consistently everywhere |
| Code Examples | TESTING.md | Link from other docs |
| Deployment Steps | DEPLOYMENT.md | Reference from others |

#### 3. Prefer References Over Duplication

**DON'T:**

```markdown
# In README.md
Get-WinEvent ...filter...
# Then again in TESTING.md
Get-WinEvent ...filter...  # Same code!
```

**DO:**

```markdown
# In README.md
For detailed queries, see
[TESTING.md - Event Log Query Examples](TESTING.md#event-log-query-examples)

# In TESTING.md (authoritative location)
## Event Log Query Examples
(single comprehensive location)
```

## Proposing Documentation Improvements

If you identify documentation issues during work:

### 1. Diagnose the Problem

- Is there duplication? (20+ identical lines)
- Is information scattered? (Same topic in 3+ files)
- Is content inconsistent? (Different versions of same info)
- Are links broken? (References to non-existent files)
- Is clarity poor? (Terms undefined, examples missing)

### 2. Propose Solutions

Format for proposing improvements:

```markdown
## Proposed Improvement: [Topic Name]

**Problem:** [What's wrong]
**Locations:** [Which files affected]
**Current Impact:** [Why this matters]

**Proposed Solution:**
- Create single authoritative section in [FILE.md]
- Update references in [other files]
- Estimated effort: [X hours]

**Example:**
[Show before/after]
```

### 3. Implement With User Approval

- Present analysis to user
- Get approval before implementing
- Execute systematically
- Verify all tests pass after changes
- Check markdown linting passes

## Pre-Commit Documentation Checklist

Before submitting ANY documentation changes (additions, modifications, or fixes):

### Search & Duplication Check (CRITICAL)

- [ ] `grep -r "YourTopic" *.md` — Search for existing content
- [ ] Identify if topic is already documented elsewhere
- [ ] If found, reference it instead of duplicating
- [ ] Search for duplicates of THIS new content after writing
- [ ] Consolidate similar content if found scattered across files

### Consistency & Accuracy Check

- [ ] Verify content matches the actual codebase (check code examples, versions)
- [ ] **CRITICAL: Use function/section names, NOT line numbers**
- [ ] Verify content matches actual test behavior (run tests to confirm)
- [ ] Check all references to other files/sections are correct
- [ ] Ensure terminology matches project glossary/standards
- [ ] Verify no hardcoded values that will become stale (use commands instead)
- [ ] Check all links are valid and point to correct sections
- [ ] Ensure glossary terms used consistently throughout

### Technical Quality Check

- [ ] Verify markdown linting passes (`npx markdownlint-cli2 *.md`)
- [ ] Check for duplicate headings (MD024)
- [ ] Verify proper heading hierarchy (MD025/MD026)
- [ ] Ensure blank lines before lists (MD032)
- [ ] Confirm fenced code blocks have language identifiers (MD031/MD040)
- [ ] No orphaned references (links to non-existent sections)
- [ ] Update Table of Contents if section structure changed

### Strategic Distribution Check

- [ ] Identify the audience (users vs developers vs AI agents)
- [ ] Place content in the right document for that audience
- [ ] Add cross-references in related docs (don't duplicate, reference)
- [ ] Verify related documentation links back (if needed)

## Examples of Good Documentation Consolidation

### Pattern A: Scattered Examples

- Before: Same code in 4 files
- After: Code in TESTING.md, links in others
- Files Modified: README.md, SECURITY.md, DEPLOYMENT.md

### Pattern B: Multiple Explanations

- Before: ServerName explained 3 different ways
- After: Single explanation in SECURITY.md, references elsewhere
- Files Modified: README.md, CONTRIBUTING.md

### Pattern C: Information Scattered

- Before: Encoding tips across multiple files
- After: Complete guide in SECURITY.md with links
- Files Modified: AGENTS.md, TESTING.md, CONTRIBUTING.md

## Examples of Good Documentation Proposals

**Good:** "I notice Event Log examples appear in 4 files with different -MaxEvents values
(10, 20, 50, 1). Should I consolidate to TESTING.md with clear use cases for each scenario?"

**Good:** "ServerName config is explained 3 different ways in README, SECURITY, and
CONTRIBUTING. Users don't know which approach to use. Should I create comprehensive guide in
SECURITY.md with clear scenarios?"

**Good:** "Windows-1251 encoding is mentioned 7 times across docs but never fully explained.
Should I create a section in SECURITY.md covering why, when, how, troubleshooting, and
configuration?"

**Bad:** "Let me add Event Log examples to every file that mentions them."

**Bad:** "I'll copy-paste ServerName explanation into all three documents for redundancy."

**Bad:** "I found a typo, I'll fix it locally without checking if it appears elsewhere."

## Preventing Documentation Drift

### Single Source of Truth Rules

1. **Authors**: Reference README.md#authors, never copy to other files
2. **License**: Reference LICENSE file, never copy legal text
3. **Versions**: Use `git tag` commands, never hardcode version numbers
4. **Event IDs**: Use TESTING.md as authoritative table, other files reference or extract
5. **Event Log Queries**: Keep comprehensive examples in TESTING.md only
6. **Test Information**: Use command-based references, not hardcoded counts

### Cross-File Consistency Checks

Before committing documentation changes, verify:

```powershell
# 1. Event ID consistency check
Write-Host "Checking Event ID consistency..."
$eventIds = @(1000, 1001, 1100, 1101, 1200, 1201, 1202, 1203, 1204,
              1300, 1301, 1302, 1303, 1400, 1401, 1500, 1900)
foreach ($id in $eventIds) {
    $readmeMatches = (Get-Content README.md | Select-String $id `
        | Measure-Object).Count
    $testingMatches = (Get-Content TESTING.md | Select-String $id `
        | Measure-Object).Count
    $securityMatches = (Get-Content SECURITY.md | Select-String $id `
        | Measure-Object).Count
    Write-Host "Event ID $id - README: $readmeMatches, " +
               "TESTING: $testingMatches, SECURITY: $securityMatches"
}

# 2. Markdown link validation
Write-Host "Checking markdown links..."
$links = Get-Content *.md | Select-String '\[.*\]\(.*\)' -AllMatches `
    | ForEach-Object { $_.Matches }
foreach ($link in $links) {
    Write-Host "Link found: $($link.Value)"
}

# 3. Hardcoded value check
Write-Host "Checking for hardcoded metrics..."
Get-Content *.md | Select-String '(74 tests|265 lines|test count|total tests)' `
    -IgnoreCase
```

## Quality Gates Before Merge

**All of the following must pass before committing:**

- ✅ All tests passing (`./tests/Run-Tests.ps1` - run to verify current count)
- ✅ Syntax validation passing (`pwsh ./utils/Validate-Scripts.ps1`)
- ✅ Markdown linting passing (GitHub Actions check)
- ✅ No hardcoded dynamic values in documentation
- ✅ Event ID consistency across all files
- ✅ Cross-references verified and working
- ✅ Code comments explain "why", not "what"
- ✅ Windows-1251 encoding used for test data

---

**For more information:**

- See [AGENTS-TOOLS-AND-WORKFLOW.md](AGENTS-TOOLS-AND-WORKFLOW.md) for git workflow
- See [AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md) for code standards
