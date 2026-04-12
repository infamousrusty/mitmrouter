# Changelog

All notable changes to mitmrouter are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Changelog entries for releases from v3.0.0 onwards are generated automatically via [`git-cliff`](https://git-cliff.org/) from [Conventional Commits](https://www.conventionalcommits.org/).

---

## [Unreleased]

### Added
- Python addon ecosystem (`addons/`) with three-tier architecture: `mitmproxy_native`, `external_tools`, `reporting`
- `AbstractAddon` base class and `AddonRegistry` for structured addon discovery and lifecycle management
- Four production-ready `mitmproxy_native` addons: `inventory_tracker`, `json_traffic_logger`, `certificate_logger`, `api_spec_extractor`
- Three `external_tools` addons: `wireshark_dissector` (TShark), `zeek_network_monitor`, `suricata_ids`
- `session_report` Phase 2 stub in `addons/reporting/`
- Five configuration profiles: `default`, `pentest`, `forensic`, `pinning`, `ethernet`
- Environment variable substitution for all sensitive configuration values
- `.env.example` template
- `requirements.txt` and `requirements-dev.txt` with pinned versions
- Rewritten CI pipeline (`ci.yml`): Ruff lint + format, Python 3.10–3.12 matrix, coverage upload
- New `release.yml`: Sigstore keyless signing, CycloneDX SBOM, git-cliff changelog
- New `security.yml`: Trivy + pip-audit + Gitleaks on push and weekly schedule
- `pytest.ini` with `light` / `medium` / `heavy` test markers
- `tests/conftest.py` with shared mitmproxy flow fixtures
- Unit tests for `api_spec_extractor`, `certificate_logger`, `inventory_tracker`, `json_traffic_logger`
- Integration tests for addon coexistence
- `git-cliff` configuration (`.github/cliff.toml`)
- Comprehensive `README.md` overhaul
- `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md`
- `docs/architecture/overview.md`
- `docs/runbooks/ethernet-intercept.md`, `docs/runbooks/wifi-ap-intercept.md`
- `docs/phase-roadmaps/phase-2.md`

### Fixed
- Hard-coded Wi-Fi password in `config/profiles/default.yml` replaced with env var substitution

### Security
- Gitleaks secret scanning added to CI
- pip-audit dependency scanning added to release and security pipelines

---

## [2.1.0] — prior to addon ecosystem

### Added
- Modular Bash library structure (`lib/`)
- Eight subcommands: `up`, `down`, `status`, `restart`, `logs`, `health`, `export`, `classify`
- YAML profile loading
- mitmproxy lifecycle management
- Evidence export (JSON, PCAP, SQLite, HTML)
- Traffic classification
- Certificate toolkit
- Initial GitHub Actions CI
