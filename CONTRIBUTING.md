# Contributing to mitmrouter

Thank you for your interest in contributing. This project is for authorised security research only. Please read and follow these guidelines before opening issues or submitting pull requests.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold these standards.

## Authorisation Requirement

All contributions must be oriented toward **authorised, defensive, and legitimate security work**. Contributions that add stealth, persistence, evasion, exfiltration, or destructive capabilities will be rejected.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/<you>/mitmrouter.git`
3. Create a branch: `git checkout -b feat/my-feature`
4. Set up your environment:
   ```bash
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt -r requirements-dev.txt
   cp .env.example .env && $EDITOR .env
   ```
5. Make your changes
6. Run tests and lint:
   ```bash
   pytest tests/ -m "light or medium"
   ruff check addons/ tests/
   ruff format addons/ tests/
   ```
7. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add new addon for X
   fix: correct iptables rule for Y
   docs: update runbook for ethernet profile
   ```
8. Push and open a pull request against `master`

## Pull Request Requirements

- All CI checks must pass (lint, tests, security scan)
- New addons must:
  - Inherit from `AbstractAddon`
  - Declare `__addon_manifest__`
  - Include unit tests in `tests/unit/`
  - Be marked with the appropriate `test_footprint` (`light`, `medium`, or `heavy`)
- New profiles must use environment variable substitution for all sensitive values
- No secrets, tokens, passwords, or real IP addresses in committed files
- Update `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/) format

## Reporting Security Issues

Do **not** open a public issue for security vulnerabilities. See [SECURITY.md](SECURITY.md).

## Style Guide

- Python: formatted and linted with [Ruff](https://docs.astral.sh/ruff/) (`ruff==0.4.4`)
- Bash: checked with [ShellCheck](https://www.shellcheck.net/)
- Markdown: UK English, consistent heading hierarchy
- All prose in UK English
