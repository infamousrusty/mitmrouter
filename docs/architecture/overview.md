# Architecture Overview

## Purpose

mitmrouter is a transparent network interception toolkit for authorised security assessments. It bridges an upstream internet connection to a device under test (DUT), routes all HTTP/HTTPS traffic through mitmproxy, and passes that traffic through a structured Python addon ecosystem for automated analysis and reporting.

## Design Lineage

This project is a substantial modernisation of [nmatt/mitmrouter](https://github.com/nmatt/mitmrouter). The original design — Ethernet and Wi-Fi bridging, hostapd/dnsmasq management, and mitmproxy transparent proxy — is fully preserved. The modernisation adds:

- A modular Python addon architecture replacing the original Bash shims
- Environment-variable-driven configuration replacing hard-coded values
- Structured logging and evidence export
- A reproducible, signed release process
- Comprehensive CI/CD with security scanning

## Network Model

```
                    ┌──────────────────────────────────────────┐
 Internet / upstream │              mitmrouter host             │
 ────────────────►  │                                          │
        eth0/WAN    │   bridge (br0)                           │
                    │       │                                  │
                    │       ▼                                  │
                    │  iptables REDIRECT → mitmproxy :8080     │
                    │       │                                  │
                    │       ▼                                  │
                    │  Python Addon Pipeline                   │
                    │       │                                  │
                    │  ┌────▼────┐   ┌───────────┐            │
                    │  │Wi-Fi AP │   │  eth1/LAN │            │
                    │  │hostapd  │   │ (ethernet │            │
                    │  │dnsmasq  │   │  profile) │            │
                    │  └────┬────┘   └─────┬─────┘            │
                    └───────┼─────────────┼────────────────────┘
                            │             │
                      Device under test (DUT)
```

### Wi-Fi AP Mode (`default`, `pentest`, `forensic`, `pinning` profiles)

1. `hostapd` creates a wireless access point on `wlan0`
2. `dnsmasq` provides DHCP and DNS to connecting devices
3. `br0` bridges `wlan0` to `eth0` (WAN)
4. `iptables` redirects TCP port 80 and 443 to mitmproxy at `:8080`
5. mitmproxy performs transparent SSL interception
6. Python addons process each intercepted flow

### Ethernet Mode (`ethernet` profile)

1. Two physical interfaces: `eth0` (WAN) and `eth1` (LAN)
2. `br0` bridges both
3. `iptables` REDIRECT as above
4. No Wi-Fi AP created

## Component Map

| Component | Location | Role |
|-----------|----------|------|
| Main entrypoint | `mitmrouter.sh` | CLI dispatch, subcommand routing |
| Network bridge | `lib/network.sh` | Bridge and interface setup |
| Wi-Fi AP | `lib/hostapd.sh` | hostapd lifecycle |
| DHCP/DNS | `lib/dnsmasq.sh` | dnsmasq lifecycle |
| mitmproxy | `lib/mitmproxy.sh` | Proxy start/stop, addon wiring |
| Config loading | `lib/config.sh` | YAML profile parsing + env var substitution |
| Evidence export | `lib/evidence.sh` | JSON, PCAP, SQLite, HTML export |
| Addon base | `addons/core/addon_base.py` | Abstract base class for all Python addons |
| Addon registry | `addons/core/addon_registry.py` | Discovery, loading, validation |
| Native addons | `addons/mitmproxy_native/` | Pure-Python flow analysis |
| External addons | `addons/external_tools/` | Wrappers for TShark, Zeek, Suricata |
| Reporting addons | `addons/reporting/` | Post-session report generation (Phase 2) |

## Configuration Model

Configuration is managed via YAML profiles in `config/profiles/`. Sensitive values use `${VAR}` substitution resolved at runtime from the process environment.

Profile selection: `./mitmrouter.sh up --profile <name>`

## Addon Architecture

All addons inherit from `AbstractAddon` (`addons/core/addon_base.py`) and declare an `__addon_manifest__` dict at module level. The `AddonRegistry` discovers addons by scanning the three sub-packages and validating manifests and Python dependencies.

### Addon categories

| Category | Directory | Dependency requirement |
|----------|-----------|------------------------|
| `mitmproxy_native` | `addons/mitmproxy_native/` | Python only |
| `external_tools` | `addons/external_tools/` | System tool (tshark, zeek, suricata) |
| `reporting` | `addons/reporting/` | Python only |

### Addon lifecycle

```
load() → configure() → running() → [request/response/error hooks] → shutdown()
```

## Security Posture

- No hard-coded secrets or passwords
- Gitleaks secret scanning on every push
- pip-audit and Trivy dependency scanning weekly
- Sigstore keyless signing for release artefacts
- Evidence files excluded from version control via `.gitignore`
- Least-privilege guidance: mitmproxy itself runs as a non-root user where possible; only the bridge/iptables setup requires root

## Decision Records

See `docs/adr/` for Architecture Decision Records covering major design choices.
*(ADR directory to be populated in Phase 2.)*
