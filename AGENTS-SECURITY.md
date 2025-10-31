# Security & Credentials Guide for Agents

Critical security guidelines, PII concerns, credential handling, and security best practices
for the M.E.Doc Update Check project.

## ⚠️ PII & Sensitive Data Warning - CRITICAL FOR CODE GENERATION

**Before committing ANY code, examples, or documentation:**

### NEVER Include (PII - Personally Identifiable Information)

- Real chat IDs or user identifiers (uniquely identifies person/organization)
- Email addresses with real names or domains (except generic `user@example.com`)
- Organizational structure details (office locations, departments, company names)

### NEVER Include (Sensitive Credentials & Secrets)

- Real API keys, tokens, or credentials (Telegram bot tokens, etc.)
- Real server names or hostnames that identify infrastructure
- Infrastructure provider names or abbreviations
- Real IP addresses, domain names, or network paths

### Always Use Instead

- Generic server names: `MEDOC-SRV01`, `MY-MEDOC-SERVER`, `TARGET-SERVER`
- Placeholder format: `YOUR_SERVER_NAME`, `EXAMPLE-SERVER`, `HOSTNAME_HERE`
- Generic examples: `192.168.0.x`, `user@example.com`, `123456:ABC...` (obviously fake)

### Pre-Commit Checklist

- [ ] No real server names in code or examples
- [ ] No IP addresses or domain names
- [ ] No email patterns beyond generic examples
- [ ] All server examples use generic names (MEDOC-SRV*, MY-*, etc.)
- [ ] Config templates use `YOUR_VALUE_HERE` placeholders
- [ ] No real tokens, keys, or credentials in examples

## Credentials & Secrets (SYSTEM User Compatible)

**IMPORTANT:** This project uses CMS (Cryptographic Message Syntax) encryption with
self-signed LocalMachine certificate for credentials compatible with Task Scheduler running
as SYSTEM user.

### Never Commit

- Telegram bot tokens (plain text)
- Chat IDs (plain text)
- Server names (credentials, but ServerName can be auto-detected)
- API keys
- Domain credentials
- Usernames or email addresses

### Secure Credential Handling

- Use `utils/Setup-Credentials.ps1` to encrypt credentials securely
- Credentials stored as encrypted CMS message:
  `$env:ProgramData\MedocUpdateCheck\credentials\telegram.cms`
- Encrypted with self-signed certificate in LocalMachine\My store (readable by SYSTEM user)
- Certificate: 5-year validity, NonExportable RSA-2048 key
- Config files load credentials using `utils/Get-TelegramCredentials.ps1`
- Document in `Config.template.ps1` as placeholders only
- Use GitHub Secrets for CI/CD

## Certificate Validation for Upgrades

When `Setup-Credentials.ps1` runs, it validates existing certificates meet CMS requirements:

### Check 1: Certificate Expiration

- If expired or expiring < 30 days: regenerate new certificate
- 5-year validity ensures manageable rotation cycle

### Check 2: Private Key Accessibility

- If private key not accessible: regenerate
- Required for decryption with `Unprotect-CmsMessage`

### Check 3: Document Encryption EKU (1.3.6.1.4.1.311.80.1)

- CMS requires Extended Key Usage: Document Encryption
- Old certificates from earlier releases may lack this
- If missing: regenerate with `-Type DocumentEncryptionCert`

### Check 4: KeyEncipherment Key Usage

- CMS requires both DataEncipherment AND KeyEncipherment
- Old certificates may only have DataEncipherment
- If missing: regenerate with both usages

### Why Validation Matters

Old certificates generated without proper CMS requirements will cause `Protect-CmsMessage`
to fail at runtime with: "The certificate is not valid for encryption." The validation
detects this silently before encryption and automatically regenerates the certificate.

## Hybrid ServerName Handling

- Auto-detect from `$env:MEDOC_SERVER_NAME` if set, else fall back to `$env:COMPUTERNAME`
- Allow explicit override in config: `$serverName = "MY_SERVER_NAME"`
- Never hardcode server names in code

## Code Security

- **No eval or dynamic code execution** without validation
- **Always use strict mode:** `Set-StrictMode -Version Latest`
- **Validate inputs:** Check file paths, server names, message content
- **Error messages:** Don't expose full paths or sensitive info in error logs
- **Dependencies:** Only use built-in PowerShell modules (no external NuGet packages)

## Testing Security

- Test Event Log writing but mock credentials
- Test Telegram sending but use mock bot tokens
- Test file operations with test data, not real logs
- GitHub Actions runs in isolated Windows environment

## Pre-Commit Security Checklist

Before submitting code or documentation:

- [ ] No real Telegram bot tokens anywhere
- [ ] No real chat IDs or user identifiers
- [ ] No real server/hostname names (use MEDOC-SRV* style)
- [ ] No real IP addresses or domain names
- [ ] No plain text credentials in code
- [ ] No PII (personal information) in examples
- [ ] Config examples use placeholders (`YOUR_VALUE_HERE`)
- [ ] Credentials handled via `Setup-Credentials.ps1`
- [ ] No hardcoded paths (use `$env:` variables)
- [ ] Test data uses mock credentials only

---

**For more information:**

- See [AGENTS-CODE-STANDARDS.md](AGENTS-CODE-STANDARDS.md) for code standards
- See [AGENTS-TESTING.md](AGENTS-TESTING.md) for testing practices
