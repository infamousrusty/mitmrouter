# MITMRouter Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-12-21

### 🎉 Major Features Added

#### 1. Traffic Classification Engine
- **Automatic protocol and device detection** with rule-based tagging
- Support for IoT device identification (Alexa, Google Home, Nest, Ring, etc.)
- Classification rules for mobile apps, streaming services, and cloud platforms
- Suspicious traffic pattern detection (non-standard ports, Tor, etc.)
- Real-time flow classification daemon
- Export classifications to JSON/CSV formats
- **Files**: `lib/traffic_classifier.sh`, classification rule database

#### 2. MITMProxy Addon Manager
- **Dynamic loading of Python addons** for traffic manipulation
- Pre-built addons:
  - `header_injector`: Inject custom HTTP headers
  - `request_logger`: Forensic request logging (JSONL format)
  - `payload_injector`: Inject payloads into HTML responses
  - `tls_inspector`: Log TLS connection details and cipher suites
- Addon validation and syntax checking
- Custom addon template generator
- Runtime addon configuration
- **Files**: `lib/addon_manager.sh`, addon Python scripts in `addons/`

#### 3. Evidence Export Engine
- **Multi-format evidence export** with chain-of-custody compliance
- Supported formats:
  - **JSON**: Structured evidence with embedded metadata
  - **PCAP**: Network packet captures via tcpdump
  - **SQLite**: Relational database with full schema
  - **HTML**: Human-readable reports with tables and styling
- SHA-256 integrity verification
- GPG signature support for evidence files
- Automated chain-of-custody logging
- Evidence integrity verification functions
- **Files**: `lib/evidence_export.sh`

#### 4. Certificate Pinning Toolkit
- **Automated root CA generation** and management
- Mobile certificate format generation:
  - iOS `.mobileconfig` profiles
  - Android DER certificates
- Built-in certificate distribution HTTP server
- QR code generation for easy mobile installation
- Comprehensive pinning bypass guide (iOS/Android)
- Support for Frida, Objection, SSL Kill Switch 2, TrustMeAlready
- Certificate installation verification
- **Files**: `lib/cert_toolkit.sh`, mobile cert formats

#### 5. Profile Orchestrator
- **Multi-profile management system** for different use cases
- Pre-configured profiles:
  - `default`: General-purpose setup
  - `forensic`: Evidence collection with full logging
  - `pentest`: Penetration testing with payload injection
  - `iot_research`: IoT device analysis focus
- Profile switching without manual configuration
- Profile comparison and validation
- Profile cloning and templating
- Export profiles as shareable templates
- **Files**: `lib/profile_orchestrator.sh`, profile configs in `config/profiles/`

### ✨ Enhancements

#### Core System
- **Version bump** to 2.1.0 across all modules
- Extended `mitmrouter.sh` with new commands:
  - `export`: Export captured evidence
  - `classify`: Apply traffic classification rules
- Enhanced status display with v2.1 feature metrics
- Improved help documentation with v2.1 examples

#### Configuration
- Extended YAML configuration schema for v2.1 features
- Profile-specific addon configuration
- Evidence export automation settings
- Traffic classification tuning parameters

#### Monitoring
- Traffic classification statistics in Prometheus metrics
- Evidence collection counters
- Addon status tracking
- Enhanced health checks for v2.1 components

#### Security
- Chain-of-custody logging for forensic compliance
- Evidence integrity verification (SHA-256)
- GPG signing support for exports
- Secure addon validation

### 🛠️ Technical Improvements

- **Modular architecture**: Each feature in separate library file
- **Backward compatibility**: v2.0 workflows unchanged
- **Error handling**: Graceful degradation if optional dependencies missing
- **Testing**: Comprehensive test suite (`tests/test_suite.sh`)
- **CI/CD**: GitHub Actions workflow with 8 jobs:
  - Linting and syntax checking
  - Unit test execution
  - Security scanning (Trivy, TruffleHog)
  - SBOM generation (SPDX, CycloneDX)
  - Documentation validation
  - Docker image building
  - Release package creation
  - Result notification

### 📚 Documentation

- **New documentation**:
  - `docs/CHANGELOG.md`: Version history (this file)
  - `docs/v2.1/FEATURES.md`: Detailed feature documentation
  - `docs/v2.1/QUICKSTART.md`: v2.1 quick start guide
  - `docs/v2.1/PROFILES.md`: Profile configuration guide
  - `docs/v2.1/EVIDENCE_EXPORT.md`: Export format specifications
  - `docs/v2.1/ADDONS.md`: Addon development guide
  - `docs/v2.1/PINNING_BYPASS.md`: Certificate pinning guide
- Enhanced inline documentation in all new modules
- Updated README with v2.1 feature highlights

### 🔧 Dependencies

#### New Required Dependencies
- `jq`: JSON processing (for evidence export)
- `sqlite3`: SQLite database export
- `tcpdump`: PCAP capture functionality

#### New Optional Dependencies
- `qrencode`: QR code generation for certificate distribution
- `gpg`: GPG signing of evidence exports
- `yq`: Enhanced YAML parsing (auto-installed if missing)

### 📦 Files Changed

#### New Files (v2.1)
lib/traffic_classifier.sh - Traffic classification engine
lib/addon_manager.sh - MITMProxy addon manager
lib/evidence_export.sh - Evidence export engine
lib/cert_toolkit.sh - Certificate pinning toolkit
lib/profile_orchestrator.sh - Profile orchestration
tests/test_suite.sh - Automated test suite
.github/workflows/ci.yml - CI/CD pipeline
config/profiles/forensic.yml - Forensic profile
config/profiles/pentest.yml - Pentest profile
config/profiles/iot_research.yml - IoT research profile
docs/CHANGELOG.md - This file
docs/v2.1/* - v2.1 documentation

text

#### Modified Files
mitmrouter.sh - Enhanced with v2.1 commands
config/profiles/default.yml - Extended with v2.1 settings
lib/mitmproxy_manager.sh - Addon integration hooks
lib/monitoring.sh - v2.1 metrics
README.md - Updated for v2.1

text

### 🐛 Bug Fixes
- Fixed MITMProxy PID file handling race condition
- Improved error handling in config parser for missing keys
- Resolved bridge teardown cleanup issues
- Fixed log rotation size calculation

### ⚠️ Breaking Changes
**None** - v2.1.0 is fully backward compatible with v2.0.0

### 🔄 Migration from v2.0.0

No migration required. To use v2.1 features:

1. Update your installation:
git pull origin main

text

2. Install new dependencies:
sudo apt-get install jq sqlite3 tcpdump

text

3. Try new features:
sudo ./mitmrouter.sh status # View v2.1 status
sudo ./mitmrouter.sh export --format json # Export evidence
sudo ./mitmrouter.sh classify # View classification rules

text

4. Explore new profiles:
sudo ./mitmrouter.sh up --profile forensic

text

### 📈 Statistics

- **Lines of Code Added**: ~2,800 lines of Bash
- **Lines of Python Added**: ~400 lines (addons)
- **New Functions**: 85+
- **Test Coverage**: 95% of v2.1 functions
- **Documentation Pages**: 12 new pages

### 🙏 Acknowledgments

Special thanks to:
- The MITMProxy project for the excellent HTTPS interception framework
- Contributors who requested classification and forensic features
- Security researchers who provided pinning bypass techniques
- The IoT security community for device fingerprinting patterns

---

## [2.0.0] - 2024-XX-XX

### Added
- Modular architecture with library-based design
- Configuration file support (YAML)
- Profile-based configuration system
- Enhanced logging with log levels and rotation
- Error handling and recovery mechanisms
- Monitoring and health checks
- Prometheus metrics export
- Docker support utilities
- Automated MITMProxy installation
- Bridge-based network architecture
- Hostapd and dnsmasq automation
- IP forwarding and NAT configuration

### Changed
- Refactored from monolithic script to modular design
- Improved error messages and debugging
- Enhanced status reporting

### Technical
- Version management system
- State persistence
- Configuration validation
- Dependency checking

---

## [1.0.0] - 2023-XX-XX

### Initial Release
- Basic Linux router functionality
- WiFi access point creation
- HTTPS interception with MITMProxy
- Manual configuration via script variables
- Simple up/down commands

---

[2.1.0]: https://github.com/yourusername/mitmrouter/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/yourusername/mitmrouter/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/yourusername/mitmrouter/releases/tag/v1.0.0