# ADR-005: Environment Variable Profile Secrets

## Status

Accepted (2024-06)

## Context

Configuration profiles (e.g., `pentest`, `forensic`, `pinning`) may
require credentials: API keys for threat‑intelligence feeds, database
connection strings for log storage, or authentication tokens for
upstream proxies.  Hard‑coding these in profile YAML files would be
a security risk and make the profiles non‑portable.

## Decision

We use **environment variables** for all secret material, referenced
from profiles via a `${VAR}` or `$VAR` placeholder convention.

Profile files contain **only non‑secret** configuration.  Secrets are
resolved at load time from the process environment.  If a referenced
variable is not set, the addon logs a warning and either uses a safe
default or skips the feature.

Example profile fragment:

```yaml
# profiles/pentest.yaml
addons:
  suricata_ids:
    enabled: true
    eve_log_path: "${MITMROUTER_SURICATA_EVE_LOG:-/var/log/suricata/eve.json}"
    api_key: "${SURICATA_API_KEY}"
The .env.example file documents all known variables, and the CI
pipeline runs a linter to ensure no real secrets are committed.

We explicitly rejected:

Profile‑embedded secrets – unacceptable security risk.
A separate secrets vault (HashiCorp Vault, etc.) – excessive
operational complexity for a tool that runs on a single host.
Command‑line flags for secrets – visible in ps output.
Consequences
Positive: Secrets never enter the git history. The same profile
can be used across environments by setting different env vars.
Standard practice for twelve‑factor apps.
Negative: Users must manage environment variables, which can be
cumbersome in development. Debugging a missing variable can be
confusing if warnings are missed.
Mitigation: The --validate-profile CLI flag checks that all
referenced variables are set (or have defaults) before starting.
The .env.example file serves as documentation.


---

## File 14: `docs/architecture/overview.md` — Updated with ADR Cross-References (M2.1-C)

```markdown
# MitmRouter Architecture Overview

> Last updated: 2024-06 — Phase 2

## High‑Level Architecture
┌─────────────────────────────────────────────┐
│ mitmproxy │
│ ┌─────────┐ ┌──────────┐ ┌──────────────┐ │
│ │ Request │ │ Response │ │ TLS Handshake │ │
│ └────┬─────┘ └────┬─────┘ └──────┬───────┘ │
│ │ │ │ │
│ ┌────▼─────────────▼──────────────▼───────┐ │
│ │ Addon Registry (runtime) │ │
│ │ ┌──────────┐ ┌──────────┐ ┌────────┐ │ │
│ │ │ Native │ │ External │ │Report │ │ │
│ │ │ Addons │ │ Tools │ │Addons │ │ │
│ │ └────┬─────┘ └────┬─────┘ └───┬────┘ │ │
│ └───────┼─────────────┼───────────┼───────┘ │
└──────────┼─────────────┼───────────┼─────────┘
│ │ │
┌────▼────┐ ┌────▼────┐ ┌──▼──────────┐
│ Output │ │External│ │ report.html │
│ Dir │ │ Tools │ │ report.md │
│ (JSON/ │ │(Zeek, │ └──────────────┘
│ YAML) │ │Suricata│
└─────────┘ └────────┘



## Component Details

### 1. Addon Ecosystem ([ADR-001](adr/ADR-001-python-addons-over-bash-shims.md))

All addons extend `AbstractAddon` and are discovered by the
`AddonRegistry`.  See [ADR-001](adr/ADR-001-python-addons-over-bash-shims.md)
for the rationale behind choosing a Python‑native ecosystem over bash shims.

### 2. Addon Categories ([ADR-004](adr/ADR-004-three-tier-addon-categories.md))

Three categories exist — `mitmproxy_native`, `external_tools`, and
`reporting`.  Details in [ADR-004](adr/ADR-004-three-tier-addon-categories.md).

### 3. Manifest Schema ([ADR-003](adr/ADR-003-addon-manifest-schema.md))

Every addon exposes a structured manifest.  See
[ADR-003](adr/ADR-003-addon-manifest-schema.md) for the full schema.

### 4. Configuration & Secrets ([ADR-005](adr/ADR-005-env-var-profile-secrets.md))

Profiles reference environment variables for all secret material.
Rationale in [ADR-005](adr/ADR-005-env-var-profile-secrets.md).

### 5. Release Signing ([ADR-002](adr/ADR-002-sigstore-over-gpg.md))

Release artifacts are signed with Sigstore.  See
[ADR-002](adr/ADR-002-sigstore-over-gpg.md) for the decision to
adopt Sigstore over GPG.

### 6. Session Reporting

At shutdown, the `session_report` addon scans the output directory for
artefacts produced by other addons and renders HTML and Markdown
reports.  This uses only Python stdlib (`string.Template`).

## Directory Layout
.
├── addons/
│ ├── base.py # AbstractAddon, AddonRegistry
│ ├── mitmproxy_native/ # Category: mitmproxy_native
│ │ ├── inventory_tracker.py
│ │ ├── json_traffic_logger.py
│ │ ├── certificate_logger.py
│ │ └── api_spec_extractor.py
│ ├── external_tools/ # Category: external_tools
│ │ ├── wireshark_dissector.py
│ │ ├── zeek_network_monitor.py
│ │ └── suricata_ids.py
│ └── reporting/ # Category: reporting
│ └── session_report.py
├── docs/
│ ├── adr/ # Architecture Decision Records
│ │ ├── ADR-001-.md
│ │ ├── ADR-002-.md
│ │ ├── ADR-003-.md
│ │ ├── ADR-004-.md
│ │ └── ADR-005-*.md
│ ├── architecture/overview.md
│ ├── runbooks/
│ └── phase-roadmaps/
├── profiles/
│ ├── default.yaml
│ ├── pentest.yaml
│ ├── forensic.yaml
│ ├── pinning.yaml
│ └── ethernet.yaml
├── tests/
│ └── fixtures/
├── pyproject.toml
├── .editorconfig
├── requirements.in / requirements.txt
├── requirements-dev.in / requirements-dev.txt
└── .github/
├── workflows/
└── ISSUE_TEMPLATE/



## Design Decisions (ADRs)

| ADR   | Title                                     | Status   |
|-------|-------------------------------------------|----------|
| 001   | Python Addons over Bash Shims             | Accepted |
| 002   | Sigstore over GPG                         | Accepted |
| 003   | Addon Manifest Schema                     | Accepted |
| 004   | Three‑Tier Addon Categories               | Accepted |
| 005   | Env‑Var Profile Secrets                   | Accepted |
