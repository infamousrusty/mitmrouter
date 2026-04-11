# Security Policy

## Supported Versions

| Version | Supported |
|---------|----------|
| `master` / latest | ✅ |
| Older tags | ❌ — please upgrade |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report vulnerabilities via GitHub's private [Security Advisory](https://github.com/infamousrusty/mitmrouter/security/advisories/new) feature.

Include:
- A description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact
- Any suggested mitigations

We aim to acknowledge reports within **72 hours** and provide an initial assessment within **7 days**.

## Responsible Use

This tool is designed exclusively for **authorised security assessments**. Operators are responsible for:

- Obtaining explicit written authorisation before use
- Handling captured traffic data in accordance with applicable law and data protection obligations
- Securely disposing of evidence files after an assessment
- Ensuring Wi-Fi passwords are strong, unique, and not reused

## Sensitive Data Handling

- All captured traffic (PCAP, JSONL, HAR, SQLite) may contain credentials, tokens, personal data, and other sensitive information
- Evidence directories must be protected with appropriate filesystem permissions (mode `0700`)
- Do not commit evidence files, `.env` files, or captured data to version control
- The `.gitignore` in this repository excludes common evidence file types; verify before `git add .`

## Dependency Scanning

Dependencies are scanned automatically:

- On every push to `master` via `pip-audit` and `Trivy`
- Weekly on Mondays at 03:00 UTC via the [Security workflow](https://github.com/infamousrusty/mitmrouter/actions/workflows/security.yml)
- Secret scanning via Gitleaks on every push

## Supply Chain

Release artefacts are signed with [Sigstore](https://www.sigstore.dev/) (keyless, SLSA-compatible). Verify a release:

```bash
cosign verify-blob \
  --certificate mitmrouter-v<VERSION>.tar.gz.sigstore \
  --signature mitmrouter-v<VERSION>.tar.gz.sig \
  mitmrouter-v<VERSION>.tar.gz
```
