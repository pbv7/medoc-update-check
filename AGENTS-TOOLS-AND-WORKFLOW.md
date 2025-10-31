# Tools & Workflow Guide for Agents

Complete guide for tool selection, git workflow, CI/CD setup, and development practices for
the M.E.Doc Update Check project.

## Tool Selection Hierarchy (Agents)

When accomplishing a task, agents should consider tools in this order:

### 1. PREFERRED: Internal Agent Capabilities (If Available)

- Agent-native tools (file read/write, bash execution, search)
- MCP (Model Context Protocol) server tools if available
- Agent Task delegation (specialized sub-agents for complex work)
- Example: Use Grep tool instead of bash `grep`, Read tool instead of `cat`

### 2. SECOND CHOICE: Project-Provided Tools

- `./tests/Run-Tests.ps1` - PowerShell testing (local execution)
- `./utils/Validate-Scripts.ps1` - PowerShell syntax validation
- `./.markdownlint.json` - Markdown linting config (requires cli)

### 3. THIRD CHOICE: Remote Execution (No Installation)

- `npx` tools - Markdown linting (`npx markdownlint-cli2`)
- `gh` (GitHub CLI) - PR creation, issue management
- These run in isolated environments, no system pollution

### 4. LAST RESORT: Local Installation (Ask First)

- `Install-Module` (PowerShell modules)
- `npm install -g` (global node packages)
- `pipx` / `uvx` (Python tools)
- **MUST ask user permission first**

## Tool Availability Decision Matrix

| Task | Preferred Method | Alt Method | Notes |
|------|-----------------|-----------|-------|
| File reading | Agent Read tool | `cat` via bash | Faster, safer with agent tools |
| Pattern search | Agent Grep tool | `grep` / `rg` via bash | Grep tool optimized for this |
| Line counting | Agent Read + count | `awk` / `wc` via bash | Read tool sufficient for most |
| Markdown linting | `npx markdownlint-cli2` | MCP markdown tool | Remote exe preferred over local install |
| GitHub operations | `gh` CLI via bash | MCP github tool | If available, use MCP; else gh CLI |
| PowerShell tests | `./tests/Run-Tests.ps1` via bash | N/A | Project-provided, always available |
| Code analysis | MCP code analysis | PSScriptAnalyzer via bash | Use MCP if available for speed |

## When to Use Each Category

### 1. Internal Agent Tools (ALWAYS FIRST)

**Why preferred:**

- ✅ No external dependencies
- ✅ Built-in to agent (always available)
- ✅ Consistent output format
- ✅ Direct integration with agent capabilities
- ✅ No network latency (offline capable)

**Examples:**

- Read files → Use **Read tool** (not `cat`)
- Search code → Use **Grep tool** (not bash `grep`)
- Find files → Use **Glob tool** (not bash `find`)
- Execute code → Use **Bash tool** (for actual commands)
- Explore codebase → Use **Task/Explore agent** (not manual searching)

### 2. MCP Tools (If Configured)

**Why important:**

- ✅ Specialized domain knowledge
- ✅ Persistent connections (faster)
- ✅ Standard interface across agents
- ✅ Better error handling
- ✅ Agent-native integration

**Examples:**

- Docker operations → `mcp__docker-mcp-toolkit__*`
- GitHub operations → `mcp__github__*` (if available)
- Web fetching → WebFetch tool (built-in)
- Slash commands → SlashCommand tool (project-specific)

**When using MCP:**

- Check available tools first: `ListMcpResourcesTool`
- Use MCP tools before external CLIs when available
- Prefer specialized MCP agents for domain tasks

### 3. Project-Provided Tools

**Why use:**

- ✅ No external dependencies needed
- ✅ Tested and validated for this project
- ✅ Already configured correctly
- ✅ Part of development workflow

**Available:**

- `./tests/Run-Tests.ps1` - Test runner
- `./utils/Validate-Scripts.ps1` - PowerShell validator
- `.markdownlint.json` - Markdown linting config

### 4. Remote CLI Tools (No Installation)

**npx (Node Package Executor):**

- Use for: Markdown linting validation
- How: `npx markdownlint-cli2 *.md`
- Advantage: No installation, always latest version
- When: Before committing changes

**gh (GitHub CLI):**

- Use for: PR creation, issue management, workflow checks
- Advantage: Better than manual git, handles formatting
- When: User explicitly asks to create PR
- Note: Requires authentication (user's responsibility)

**Others:**

- `uvx` (Python) - Use if documenting Python tools (rare in this project)
- `pipx` (Python) - Use if documenting Python tools (rare in this project)

### 5. Local Installation (Request Permission)

**When to request:**

- User explicitly asks to install
- Installation needed for essential feature
- No alternative agent tool available

**How to request:**

```text
"Would you like to install Pester locally for testing? This will add it to your PowerShell installation."
```

**Always check first:**

```powershell
if (Get-Module -ListAvailable -Name Pester) {
    # Already installed, use it
} else {
    # Ask user before installing
}
```

## Decision Tree for Agents

```text
Need to accomplish task?
├─ Can agent do it natively?
│  ├─ YES → Use internal agent tool (Read, Grep, Glob, Bash)
│  └─ NO → Continue
│
├─ Is MCP server available for this?
│  ├─ YES → Use MCP tool
│  └─ NO → Continue
│
├─ Is project-provided tool available?
│  ├─ YES → Use project tool (./utils/*, ./tests/*)
│  └─ NO → Continue
│
├─ Can remote CLI accomplish it? (No local install)
│  ├─ YES → Use npx / gh / web fetch
│  └─ NO → Continue
│
└─ Local installation needed?
   ├─ YES → Ask user permission first
   └─ NO → Research alternatives or Task agent
```

## Usage Examples

**✅ GOOD: Use internal agent tools first:**

```text
Task: Find all lines mentioning "TODO" in code
Solution: Use Grep tool (not bash grep)
Result: Fast, consistent, no external dependencies
```

**✅ GOOD: Use MCP if available:**

```text
Task: Check GitHub PR status
Check: If mcp__github tool available
If yes: Use MCP GitHub tool
If no: Use gh CLI as fallback
```

**✅ GOOD: Use project tools:**

```text
Task: Validate PowerShell syntax
Use: ./utils/Validate-Scripts.ps1 via Bash tool
Why: Project-tested, no external dependencies
```

**✅ GOOD: Use remote CLI when needed:**

```text
Task: Validate markdown before commit
Use: npx markdownlint-cli2 *.md
Why: No installation, always latest, removes local bloat
```

**✅ GOOD: Ask before installing:**

```text
"Would you like to install PSScriptAnalyzer locally for code quality checks?"
Check if available first, only suggest if not installed
```

**❌ BAD: Automatically install:**

```bash
npm install -g markdownlint-cli  # Bad: user not asked
Install-Module Pester -Force      # Bad: user not asked
```

**❌ BAD: Ignore available tools:**

```bash
# Bad: bash grep instead of Grep tool
grep "pattern" file.txt

# Bad: bash cat instead of Read tool
cat file.txt

# Bad: ignore MCP tools
Use gh CLI without checking mcp__github availability
```

## Git Workflow for Agents

### Branch Strategy

**main** - Production-ready code

- All tests passing
- Code reviewed
- Ready to deploy to servers

All changes go through **feature** or **fix** branches with PR-based workflow. No develop
branch.

### Making Changes

1. **Create feature or fix branch** from `main`:

   ```powershell
   git checkout main
   git pull origin main
   git checkout -b feature/your-feature-name
   # OR
   git checkout -b fix/your-bug-description
   ```

2. **Make changes** and test locally:

   ```powershell
   ./tests/Run-Tests.ps1
   ```

3. **Commit with meaningful message:**

   ```text
   Add feature description

   - What was changed
   - Why it was changed
   - Any breaking changes or warnings
   ```

4. **Push and open PR:**

   ```powershell
   git push origin feature/your-feature-name
   ```

5. **GitHub Actions runs automatically:**

   - Tests run on Windows (PowerShell 7+ - latest)
   - Code quality checks
   - Markdown linting
   - Results appear in PR checks tab

6. **All tests must pass before merge:**

   - All tests passing (verify with: `./tests/Run-Tests.ps1`)
   - No PSScriptAnalyzer issues
   - Markdown validation passing
   - No merge conflicts

## Commit Message Format

This project uses **Conventional Commits** format
([https://www.conventionalcommits.org/](https://www.conventionalcommits.org/)).

**Format:**

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Example for AI agents:**

```text
feat(credentials): add CMS encryption with certificate rotation

Implement Cryptographic Message Syntax encryption for Telegram
credentials with automatic certificate rotation on expiry or
validation failure. Certificates now meet CMS requirements for
Document Encryption and are readable by SYSTEM user.

- Create self-signed DocumentEncryptionCert with 5-year validity
- Validate existing certificates meet CMS requirements
- Auto-rotate if expired or missing required EKU
- Restrict permissions to SYSTEM + Administrators
```

### ⚠️ IMPORTANT - No Agent Banners in Commits

**NEVER include** these in commit messages:

- ❌ `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- ❌ `Co-Authored-By: Claude <noreply@anthropic.com>`
- ❌ Any AI agent attribution banners

**Why:** These are only for specific contexts (pull requests, documentation) - NOT for
commits that will be in permanent git history.

**Types:**

- `feat:` New feature or enhancement
- `fix:` Bug fix
- `test:` Test additions or fixes
- `docs:` Documentation changes
- `refactor:` Code restructuring without behavior change
- `perf:` Performance improvements
- `style:` Code formatting (no behavior change)
- `chore:` Build, dependencies, tooling, CI/CD
- `ci:` CI/CD configuration

**Scope** (optional but recommended):

- `credentials` - Credential/security changes
- `tests` - Test suite changes
- `docs` - Documentation
- `config` - Configuration
- `workflow` - GitHub Actions/CI

**Subject line rules:**

- Use imperative mood ("add" not "added")
- Start lowercase (unless proper noun)
- No period at end
- Maximum 50 characters

**Body** (optional for non-trivial changes):

- Explain WHY, not WHAT
- Wrap at 72 characters
- Separate from subject with blank line

## Markdown Linting Guidelines

This project uses GitHub Actions markdown linting. Common issues and fixes:

### MD022: Heading Spacing

**Issue:** Missing blank line before heading

**Auto-fix:** Add blank line before every `##`, `###`, etc.

### MD031: Code Fence Language

**Issue:** Fenced code block missing language identifier

**Auto-fix:** Always include language after backticks:

- `powershell` for PowerShell
- `bash` for shell scripts
- `markdown` for markdown examples
- `json` for JSON files
- `yaml` for YAML files
- `text` if truly language-agnostic

### MD032: List Spacing

**Issue:** Missing blank line before list

**Auto-fix:** Add blank line before any ordered or unordered list.

### MD040: Fenced Code Language

**Issue:** Code fence missing language (stricter version of MD031)

**Auto-fix:** Same as MD031 above.

### MD013: Line Length

**Issue:** Line exceeds maximum length (check `.markdownlint.json` for current limit)

**Why this rule exists?** Long lines are harder to read in standard editors and version
control diffs. This project enforces line length limits to maintain readability across
different tools and environments.

**Auto-fix Guidelines:**

1. **Break long sentences** at logical points (after commas, conjunctions, or clauses)
2. **Preserve all information** — never delete content to shorten lines
3. **Exceptions that are acceptable:**
   - Table cells in markdown tables (breaking them destroys table structure)
   - Code blocks and code fence examples (preserve exact formatting)
   - URLs in markdown links (keep complete links)
   - File paths and directory structures

4. **How to break lines properly:**

   ```markdown
   # ❌ WRONG: Single very long line
   This is a very long explanation that provides important context about...

   # ✅ CORRECT: Break at logical point with proper indentation
   This is a very long explanation that provides important context
   about...
   ```

5. **Special cases:**
   - **Bullet points:** Break after dash, keeping content indented
   - **Descriptions:** Break after punctuation or logical clause boundaries
   - **Code in markdown:** Keep on single line (exception to length rule)

**Before committing:** Run `npx markdownlint-cli2 *.md` and fix any MD013 violations in your
changes.

## Agent Interaction Guidelines

### What Agents Should Ask Before Acting

**ALWAYS ask user permission before:**

- Installing modules locally (`Install-Module` on user's system)
- Modifying configuration files with real server names
- Creating credentials or secrets
- Running destructive operations (delete, reset)
- Making changes to `Run.ps1` (should stay universal)

### What Agents Can Do Automatically

**No need to ask for:**

- Adding functions to `lib/MedocUpdateCheck.psm1`
- Creating new test files in `tests/`
- Adding documentation files
- Creating feature branches
- Running `./tests/Run-Tests.ps1` to validate work
- Fixing markdown linting issues in docs
- Refactoring code (if tests still pass)

### What Agents Should Report

**Always inform user about:**

- Test results (passing/failing count)
- Markdown linting issues found
- Breaking changes to existing functions
- Security concerns in proposed changes
- Dependencies that need installation (ask permission)
- Changes that affect deployment or configuration

---

**For more information:**

- See [AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md) for code standards
- See [AGENTS-TESTING.md](AGENTS-TESTING.md) for testing practices
- See [AGENTS-DOCUMENTATION.md](AGENTS-DOCUMENTATION.md) for documentation guidelines
