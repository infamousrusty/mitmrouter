# mitmrouter

> Authorised network interception and traffic analysis toolkit for IoT, mobile, and embedded device security assessments.

[![CI](https://github.com/infamousrusty/mitmrouter/actions/workflows/ci.yml/badge.svg)](https://github.com/infamousrusty/mitmrouter/actions/workflows/ci.yml)
[![Security](https://github.com/infamousrusty/mitmrouter/actions/workflows/security.yml/badge.svg)](https://github.com/infamousrusty/mitmrouter/actions/workflows/security.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

mitmrouter turns a Linux host into a transparent interception router. It bridges upstream internet access to a downstream device-under-test (via Wi-Fi AP or a second Ethernet interface), routes all HTTP/HTTPS traffic through [mitmproxy](https://mitmproxy.org/), and feeds that traffic through a modular Python addon ecosystem for automated analysis, inventory, and reporting.

Originally based on [nmatt/mitmrouter](https://github.com/nmatt/mitmrouter). This fork has been substantially modernised — see the [architecture overview](docs/architecture/overview.md) for a full comparison.

---

## ⚠️ Authorisation Required

This tool is designed for **authorised security assessments only**. You must have explicit written permission to intercept and analyse traffic on any network or device. Unauthorised interception is illegal in most jurisdictions.

---

## Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Profiles](#profiles)
- [Addons](#addons)
- [Development](#development)
- [Security](#security)
- [Contributing](#contributing)
- [Licence](#licence)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      mitmrouter host                    │
│                                                         │
│  eth0 / WAN ──► bridge (br0) ──► mitmproxy :8080        │
│                                      │                  │
│          Wi-Fi AP (hostapd/dnsmasq)   │                  │
│          or eth1 / LAN  ◄────────────┘                  │
│                                                         │
│  Python Addon Ecosystem                                 │
│  ┌─────────────────────────────────────────────────┐   │
│  │ mitmproxy_native │ external_tools │ reporting    │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
         │                              │
   Internet / upstream           Device under test
```

See [docs/architecture/overview.md](docs/architecture/overview.md) for the full design.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux host | Tested on Ubuntu 22.04 / 24.04 |
| Python 3.10+ | 3.12 recommended |
| `hostapd` | Wi-Fi AP mode only |
| `dnsmasq` | DHCP + DNS |
| `bridge-utils` (`brctl`) | Network bridge |
| `net-tools` (`ifconfig`) | Interface management |
| `iproute2` (`ip`) | Routing |
| `iptables` | Packet forwarding rules |
| `mitmproxy` ≥ 10.3 | Installed via pip (see below) |
| `tshark` | Optional — wireshark_dissector addon |
| `zeek` | Optional — zeek_network_monitor addon |
| `suricata` | Optional — suricata_ids addon |

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/infamousrusty/mitmrouter.git
cd mitmrouter
```

### 2. Set up the Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Configure your environment

```bash
cp .env.example .env
$EDITOR .env          # set MITMROUTER_WIFI_PASSWORD at minimum
source .env
```

### 4. Install system dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
  hostapd dnsmasq bridge-utils net-tools iproute2 iptables \
  tcpdump sqlite3 jq openssl
```

### 5. Make the script executable

```bash
chmod +x mitmrouter.sh
```

---

## Configuration

Configuration is managed via YAML profile files in `config/profiles/`.

Sensitive values (passwords, SSIDs) must **never** be hard-coded. Supply them via environment variables referenced in the profile:

```yaml
# config/profiles/default.yml
wifi:
  password: "${MITMROUTER_WIFI_PASSWORD}"
```

Set the variable before running:

```bash
export MITMROUTER_WIFI_PASSWORD="your-secure-password"
```

Or use a `.env` file (see `.env.example`).

---

## Usage

```
Usage: ./mitmrouter.sh <command> [options]

Commands:
  up           Start the router, bridge, and mitmproxy
  down         Tear down all components cleanly
  restart      down + up
  status       Show current component status
  logs         Tail the mitmrouter log
  health       Run addon health checks
  export       Export captured evidence
  classify     Run traffic classification on captured data

Options:
  --profile <name>   Profile to load (default: default)
                     Available: default, pentest, forensic, pinning, ethernet
  --help             Show this help text
```

### Quick start — Wi-Fi AP mode

```bash
source .env
sudo ./mitmrouter.sh up --profile default
```

### Ethernet-only mode

```bash
source .env
sudo ./mitmrouter.sh up --profile ethernet
```

### Pentest mode with full logging

```bash
source .env
sudo ./mitmrouter.sh up --profile pentest
```

---

## Profiles

| Profile | Mode | Use case | Addons enabled |
|---------|------|----------|----------------|
| `default` | Wi-Fi AP | General-purpose lab use | inventory, json_logger, cert_logger, api_spec |
| `pentest` | Wi-Fi AP | Authorised penetration testing | All native + TShark |
| `forensic` | Wi-Fi AP | High-fidelity forensic capture | All native + Zeek + Suricata |
| `pinning` | Wi-Fi AP | SSL pinning bypass analysis | cert_logger prominent, ssl_insecure |
| `ethernet` | Ethernet | Wired lab bench interception | All native + TShark |

See `config/profiles/` for full configuration details.

---

## Addons

mitmrouter uses a three-tier addon architecture:

### `mitmproxy_native` — no external tools required

| Addon | Description |
|-------|-------------|
| `inventory_tracker` | Tracks all HTTP/HTTPS endpoints, domains, and methods observed |
| `json_traffic_logger` | Writes every flow to a structured JSONL file (ELK/Splunk compatible) |
| `certificate_logger` | Extracts and catalogues TLS certificates, issuers, validity, and fingerprints |
| `api_spec_extractor` | Auto-generates an OpenAPI 3.0 spec from observed traffic |

### `external_tools` — require system tools

| Addon | Tool required | Description |
|-------|---------------|-------------|
| `wireshark_dissector` | `tshark` | Full protocol dissection with optional Lua scripts |
| `zeek_network_monitor` | `zeek` | High-level traffic analysis and anomaly detection |
| `suricata_ids` | `suricata` | Signature-based threat detection on captured PCAP |

### `reporting` — post-session (Phase 2)

| Addon | Description |
|-------|-------------|
| `session_report` | HTML/Markdown post-session summary (Phase 2 stub) |

---

## Development

### Set up the development environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
```

### Run tests

```bash
# Fast unit tests (no external tools needed)
pytest tests/ -m "light or medium" -v

# All tests including heavy (requires tshark, zeek, suricata)
pytest tests/ -v
```

### Lint and format

```bash
ruff check addons/ tests/
ruff format addons/ tests/
```

### Repository layout

```
mitmrouter/
├── mitmrouter.sh          # Main entrypoint
├── lib/                   # Bash library modules
├── addons/                # Python mitmproxy addons
│   ├── core/              # Base class + registry
│   ├── mitmproxy_native/  # Pure-Python addons
│   ├── external_tools/    # Addons wrapping system tools
│   └── reporting/         # Post-session report addons
├── config/
│   └── profiles/          # YAML configuration profiles
├── tests/
│   ├── unit/
│   └── integration/
├── docs/
│   ├── architecture/
│   ├── runbooks/
│   └── phase-roadmaps/
├── .github/
│   └── workflows/         # CI, release, security pipelines
├── .env.example           # Environment variable template
├── requirements.txt
└── requirements-dev.txt
```

---

## Security

- All Wi-Fi passwords and sensitive configuration values must be supplied via environment variables. See `.env.example`.
- Traffic captured by this tool may contain credentials, tokens, and personal data. Handle all evidence files with appropriate care.
- See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy.
- Dependencies are scanned weekly via [pip-audit and Trivy](https://github.com/infamousrusty/mitmrouter/actions/workflows/security.yml).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Licence

[MIT](LICENSE) — © infamousrusty
