# Phase 2 Roadmap — mitmrouter

**Status:** Planned  
**Target:** v3.1.0 – v3.3.0  
**Depends on:** Phase 1 (feat/addon-ecosystem-v3) merged and stable

---

## Goals

Phase 2 builds on the Phase 1 addon ecosystem to deliver:

1. A fully implemented `session_report` addon (HTML + Markdown)
2. Architecture Decision Records (ADRs) for all major design choices
3. `requirements.in` + `pip-compile` lockfile for fully reproducible installs
4. Hardened `certificate_logger` using the `cryptography` API correctly
5. A `SBOM/` directory committed at each release
6. Issue and PR templates in `.github/`
7. `docs/troubleshooting/` section
8. An `.editorconfig` and `pyproject.toml` for unified tooling configuration
9. A `packaging/` directory with Debian package spec and/or install script
10. Expanded test coverage: medium-footprint tests for all external-tool addons (mocked subprocess)

---

## Milestones

### Milestone 2.1 — Reporting and Hardening (v3.1.0)

#### M2.1-A: Implement `session_report` addon

| Field | Value |
|-------|-------|
| **Objective** | Replace the Phase 2 stub with a fully functional post-session report |
| **Scope** | `addons/reporting/session_report.py` — reads JSONL, cert JSON, inventory JSON, OpenAPI spec; renders HTML and Markdown using Jinja2 or plain string templates |
| **Dependencies** | Phase 1 merged; all native addon output files exist |
| **Testing** | `light` unit tests with synthetic fixture files; `medium` test with a real multi-addon session fixture |
| **Definition of done** | Running `mitmrouter export` produces `report.html` and `report.md` in the evidence directory; CI `light` tests pass |
| **Rollback** | The stub remains functional; simply revert the addon file |

#### M2.1-B: Fix `certificate_logger` cryptography API

| Field | Value |
|-------|-------|
| **Objective** | Replace pyOpenSSL-style `cert.get_subject().CN` calls with `cryptography` API (`cert.x509.subject`) |
| **Scope** | `addons/mitmproxy_native/certificate_logger.py` |
| **Dependencies** | mitmproxy ≥ 10.3 (already required) |
| **Testing** | Add `light` unit test using a real self-signed cert fixture generated with `cryptography` |
| **Definition of done** | `certificate_logger` correctly extracts CN, issuer, SANs, and validity from a mitmproxy 10.x cert object; all `light` tests pass |
| **Rollback** | Revert to previous extraction logic |

#### M2.1-C: ADR suite

| Field | Value |
|-------|-------|
| **Objective** | Document all major design decisions made in Phase 1 |
| **Scope** | `docs/adr/ADR-001` through `ADR-005` (see below) |
| **Dependencies** | None |
| **Testing** | CI markdown link check |
| **Definition of done** | Five ADR files committed, cross-referenced from `docs/architecture/overview.md` |
| **Rollback** | N/A (documentation only) |

ADRs to write:

| ADR | Title |
|-----|-------|
| ADR-001 | Python addons over Bash shims for mitmproxy integration |
| ADR-002 | Sigstore keyless signing over GPG for release provenance |
| ADR-003 | Addon manifest schema design |
| ADR-004 | Three-tier addon category model |
| ADR-005 | Environment variable substitution for profile secrets |

---

### Milestone 2.2 — Packaging and Supply Chain (v3.2.0)

#### M2.2-A: Reproducible lockfile via pip-compile

| Field | Value |
|-------|-------|
| **Objective** | Replace `requirements.txt` with `requirements.in` + compiled `requirements.txt` with hashes |
| **Scope** | `requirements.in`, `requirements-dev.in`; update `ci.yml` to use `--require-hashes` |
| **Dependencies** | pip-tools in `requirements-dev.txt` (already present) |
| **Testing** | CI `pip install --require-hashes -r requirements.txt` step |
| **Definition of done** | `pip install --require-hashes` succeeds in CI on a clean environment |
| **Rollback** | Revert to unpinned `requirements.txt` |

#### M2.2-B: Committed SBOM

| Field | Value |
|-------|-------|
| **Objective** | Commit a CycloneDX SBOM to `SBOM/` at each release |
| **Scope** | `SBOM/` directory; update `release.yml` to copy SBOM into repo via a post-release commit or as a release asset |
| **Dependencies** | `cyclonedx-bom` (already in `release.yml`) |
| **Testing** | Verify SBOM is present in GitHub Release assets |
| **Definition of done** | Each tagged release includes `SBOM/sbom-cyclonedx.json` as a release asset and in the repo |
| **Rollback** | Remove the post-release SBOM commit step |

#### M2.2-C: Debian packaging spec

| Field | Value |
|-------|-------|
| **Objective** | Provide a `packaging/debian/` spec for installation via `dpkg` |
| **Scope** | `packaging/debian/control`, `packaging/debian/rules`, `packaging/debian/install`, `packaging/Makefile` |
| **Dependencies** | Stable file layout (Phase 1) |
| **Testing** | Build the `.deb` in CI on Ubuntu 24.04; verify `dpkg -i` succeeds |
| **Definition of done** | `make -C packaging deb` produces a valid `.deb`; CI step passes |
| **Rollback** | Remove packaging CI step; packaging directory remains as reference |

---

### Milestone 2.3 — Developer Experience and Test Coverage (v3.3.0)

#### M2.3-A: Medium-footprint tests for external-tool addons

| Field | Value |
|-------|-------|
| **Objective** | Test `wireshark_dissector`, `zeek_network_monitor`, and `suricata_ids` without requiring the actual tools installed |
| **Scope** | `tests/unit/test_wireshark_dissector.py`, `test_zeek_network_monitor.py`, `test_suricata_ids.py` — mock `subprocess.run` |
| **Dependencies** | None |
| **Testing** | Marked `medium`; run in standard CI matrix |
| **Definition of done** | Three new test files; CI `medium` tests pass; coverage above 70% for `external_tools/` |
| **Rollback** | Remove test files |

#### M2.3-B: `.github/` templates

| Field | Value |
|-------|-------|
| **Objective** | Structured issue and PR templates to guide contributors |
| **Scope** | `.github/ISSUE_TEMPLATE/bug_report.yml`, `feature_request.yml`, `addon_request.yml`; `.github/PULL_REQUEST_TEMPLATE.md` |
| **Dependencies** | None |
| **Testing** | Manual review |
| **Definition of done** | Templates appear when opening a new issue or PR on GitHub |
| **Rollback** | Delete template files |

#### M2.3-C: `pyproject.toml` and `.editorconfig`

| Field | Value |
|-------|-------|
| **Objective** | Centralise tool configuration and enforce consistent editor behaviour |
| **Scope** | `pyproject.toml` (Ruff, pytest, coverage config); `.editorconfig` (indent, charset, line endings) |
| **Dependencies** | None |
| **Testing** | `ruff check` and `pytest` continue to pass |
| **Definition of done** | `pytest.ini` and per-tool config sections consolidated into `pyproject.toml`; `.editorconfig` committed |
| **Rollback** | Revert to `pytest.ini` |

---

## Phase 3+ — Future Directions

| Phase | Theme | Key deliverables |
|-------|-------|------------------|
| **3** | Plugin architecture | Runtime addon loading from user-defined directories; addon versioning and dependency resolution |
| **3** | API / service mode | `mitmrouter serve` exposes a REST API for remote control and evidence retrieval |
| **4** | Policy-based workflows | YAML-defined interception policies (allow/deny, modify, tag) applied per addon or per host |
| **4** | Exportable reports | Structured JSON/HTML/PDF assessment reports consumable by external platforms (DefectDojo, Jira, etc.) |
| **5** | Optional TUI | Rich-based terminal UI for real-time flow inspection and addon control |
| **5** | Fleet / lab management | Multi-host orchestration; centralised evidence aggregation |
| **5** | Continuous validation | Scheduled re-assessment against known baselines; diff-based change detection |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| mitmproxy API breaking changes in v11 | Medium | High | Pin `mitmproxy<11` until compatibility tested; monitor upstream changelog |
| Jinja2 / pyyaml supply chain compromise | Low | High | pip-audit weekly scan; hash-pinned installs (M2.2-A) |
| Gitleaks false positive blocks CI | Medium | Low | Maintain `.gitleaks.toml` allowlist for test fixtures |
| Zeek/Suricata not available on CI runners | High | Medium | Heavy tests already gated behind `master`-only and external-tool install step |
| `session_report` scope creep | Medium | Medium | Constrain Phase 2 to HTML + Markdown only; defer PDF to Phase 4 |

---

## Backward Compatibility

- All Phase 1 profiles (`default`, `pentest`, `forensic`, `pinning`, `ethernet`) are preserved unchanged
- The `AbstractAddon` base class contract is stable; existing addons require no changes for Phase 2 milestones
- The `AddonRegistry` manifest schema gains optional `phase` and `status` fields (already present on `session_report`)
- The Bash CLI interface (`mitmrouter.sh <command>`) is unchanged

---

## Agent Handoff Notes

For any agent or developer picking up Phase 2:

1. Start with **M2.1-B** (certificate_logger fix) as it is a correctness bug
2. Then **M2.1-A** (session_report) — the stub is already wired into the registry
3. Then **M2.1-C** (ADRs) — documentation, no code risk
4. Then **M2.2-A** (lockfile) — supply chain hardening
5. All changes go to a new branch `feat/phase-2-reporting` branching from `master` after PR #1 is merged
6. Each milestone should be a separate PR for reviewability
7. The `session_report` addon should use only stdlib + `mitmproxy` dependencies; do not add Jinja2 unless unavoidable
