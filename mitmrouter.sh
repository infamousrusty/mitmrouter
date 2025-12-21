#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Linux Router for IoT Traffic Analysis & SSL MITM
# NEW in v2.1.0:
#   - Traffic classification and tagging
#   - MITMProxy addon manager
#   - Evidence export engine with chain-of-custody
#   - Certificate pinning toolkit
#   - Profile orchestration
#
# Usage: ./mitmrouter.sh {up|down|status|restart|logs|export|classify} [OPTIONS]
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Library imports
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/error_handling.sh"
source "${SCRIPT_DIR}/lib/config_parser.sh"
source "${SCRIPT_DIR}/lib/network_setup.sh"
source "${SCRIPT_DIR}/lib/mitmproxy_manager.sh"
source "${SCRIPT_DIR}/lib/monitoring.sh"

# NEW v2.1.0 libraries
source "${SCRIPT_DIR}/lib/traffic_classifier.sh"
source "${SCRIPT_DIR}/lib/addon_manager.sh"
source "${SCRIPT_DIR}/lib/evidence_export.sh"
source "${SCRIPT_DIR}/lib/cert_toolkit.sh"
source "${SCRIPT_DIR}/lib/profile_orchestrator.sh"

# Global configuration
readonly MITMROUTER_VERSION="2.1.0"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly STATE_DIR="/var/lib/mitmrouter"
readonly LOG_DIR="/var/log/mitmrouter"
readonly EVIDENCE_DIR="${STATE_DIR}/evidence"

# Parse command line arguments
COMMAND="${1:-up}"
PROFILE="${2:-default}"
CUSTOM_CONFIG=""
EXPORT_FORMAT=""
CLASSIFICATION_RULE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        --format)
            EXPORT_FORMAT="$2"
            shift 2
            ;;
        --rule)
            CLASSIFICATION_RULE="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Initialize logging and state directories
initialize_system() {
    log_info "Initializing MITMRouter v${MITMROUTER_VERSION}"
    
    # Create necessary directories with proper permissions
    mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${CONFIG_DIR}/certs" "${EVIDENCE_DIR}"
    mkdir -p "${STATE_DIR}/classifications" "${STATE_DIR}/addons" "${STATE_DIR}/profiles"
    chmod 750 "${STATE_DIR}" "${LOG_DIR}" "${EVIDENCE_DIR}"
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    log_success "System initialization complete"
}

# Load configuration with validation
load_configuration() {
    local config_file="${CUSTOM_CONFIG:-${CONFIG_DIR}/profiles/${PROFILE}.yml}"
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        log_info "Available profiles: $(list_available_profiles)"
        return 1
    fi
    
    log_info "Loading configuration from: ${config_file}"
    parse_yaml "${config_file}"
    
    # Validate required configuration keys
    validate_config || return 1
    
    # Initialize v2.1 features
    initialize_classifier || log_warn "Classifier initialization failed"
    initialize_addon_manager || log_warn "Addon manager initialization failed"
    
    log_success "Configuration loaded successfully"
}

# Validate configuration has required keys
validate_config() {
    local required_keys=("network_wan_interface" "network_wlan_interface" "wifi_ssid" "wifi_password")
    
    for key in "${required_keys[@]}"; do
        if [[ -z "${!key:-}" ]]; then
            log_error "Missing required configuration: ${key}"
            return 1
        fi
    done
    
    return 0
}

# Start MITMRouter services
start_services() {
    log_info "Starting MITMRouter v${MITMROUTER_VERSION} services..."
    
    # Verify dependencies
    verify_dependencies || return 1
    
    # Install/update MITMProxy
    install_mitmproxy "${mitmproxy_version:-10.4.2}" || return 1
    
    # Setup network interfaces
    setup_bridge || return 1
    setup_hostapd || return 1
    setup_dnsmasq || return 1
    
    # Enable IP forwarding and NAT
    enable_ip_forwarding || return 1
    
    # NEW v2.1: Deploy certificate pinning toolkit if enabled
    if [[ "${cert_pinning_enabled:-false}" == "true" ]]; then
        deploy_pinning_certs || log_warn "Certificate pinning setup incomplete"
    fi
    
    # NEW v2.1: Load MITMProxy addons if configured
    if [[ -n "${mitmproxy_addons:-}" ]]; then
        load_addons "${mitmproxy_addons}" || log_warn "Some addons failed to load"
    fi
    
    # Start MITMProxy with v2.1 enhancements
    start_mitmproxy || return 1
    
    # NEW v2.1: Start traffic classification
    if [[ "${traffic_classification_enabled:-true}" == "true" ]]; then
        start_traffic_classifier || log_warn "Traffic classifier failed to start"
    fi
    
    # Initialize monitoring
    initialize_monitoring || return 1
    
    log_success "All services started successfully"
    
    # Save state
    echo "${PROFILE}" > "${STATE_DIR}/active_profile"
    date -u +%Y-%m-%dT%H:%M:%SZ > "${STATE_DIR}/startup_time"
}

# Stop all services
stop_services() {
    log_info "Stopping MITMRouter services..."
    
    # NEW v2.1: Stop traffic classifier
    stop_traffic_classifier 2>/dev/null || true
    
    # Stop MITMProxy
    stop_mitmproxy 2>/dev/null || true
    
    # Stop hostapd and dnsmasq
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    
    # Tear down bridge
    teardown_bridge || true
    
    # Disable IP forwarding
    sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
    
    log_success "All services stopped"
}

# Display service status
show_status() {
    log_info "MITMRouter v${MITMROUTER_VERSION} Status Report"
    echo "=============================================="
    
    # Check if active
    if [[ -f "${STATE_DIR}/active_profile" ]]; then
        local active_profile=$(cat "${STATE_DIR}/active_profile")
        local startup_time=$(cat "${STATE_DIR}/startup_time" 2>/dev/null || echo "unknown")
        echo "Status: RUNNING"
        echo "Profile: ${active_profile}"
        echo "Started: ${startup_time}"
    else
        echo "Status: STOPPED"
        return 0
    fi
    
    # Check services
    echo ""
    echo "Core Services:"
    systemctl is-active hostapd >/dev/null 2>&1 && echo "  hostapd: ✓ RUNNING" || echo "  hostapd: ✗ STOPPED"
    systemctl is-active dnsmasq >/dev/null 2>&1 && echo "  dnsmasq: ✓ RUNNING" || echo "  dnsmasq: ✗ STOPPED"
    
    # Check network interfaces
    echo ""
    echo "Network Interfaces:"
    ip link show "${network_bridge_name}" 2>/dev/null && echo "  ${network_bridge_name}: ✓ UP" || echo "  ${network_bridge_name}: ✗ DOWN"
    
    # Check MITMProxy
    echo ""
    echo "MITMProxy:"
    if pgrep -f "mitmproxy" >/dev/null; then
        echo "  Status: ✓ RUNNING"
        echo "  Listen Port: ${mitmproxy_listen_port:-8080}"
        echo "  Web Interface: http://localhost:${mitmproxy_web_port:-8081}"
        
        # NEW v2.1: Show loaded addons
        local loaded_addons=$(list_loaded_addons 2>/dev/null || echo "none")
        echo "  Addons: ${loaded_addons}"
    else
        echo "  Status: ✗ STOPPED"
    fi
    
    # NEW v2.1: Traffic Classifier Status
    echo ""
    echo "Traffic Classifier:"
    if pgrep -f "traffic_classifier" >/dev/null; then
        echo "  Status: ✓ RUNNING"
        local classified_count=$(get_classification_count 2>/dev/null || echo "0")
        echo "  Classified Flows: ${classified_count}"
    else
        echo "  Status: ✗ STOPPED"
    fi
    
    # Connected clients
    if command -v iw &>/dev/null; then
        local connected=$(iw dev "${network_wlan_interface}" station dump 2>/dev/null | grep -c "Station" || echo "0")
        echo ""
        echo "Connected Devices: ${connected}"
    fi
    
    # NEW v2.1: Evidence collection status
    echo ""
    echo "Evidence Collection:"
    local evidence_files=$(find "${EVIDENCE_DIR}" -type f 2>/dev/null | wc -l)
    echo "  Captured Files: ${evidence_files}"
    if [[ -f "${STATE_DIR}/chain_of_custody.log" ]]; then
        echo "  Chain-of-Custody: ✓ ENABLED"
    fi
}

# NEW v2.1: Export evidence in specified format
export_evidence() {
    local format="${EXPORT_FORMAT:-json}"
    log_info "Exporting evidence in ${format} format..."
    
    case "${format}" in
        json)
            export_evidence_json || return 1
            ;;
        pcap)
            export_evidence_pcap || return 1
            ;;
        sqlite)
            export_evidence_sqlite || return 1
            ;;
        html)
            export_evidence_html || return 1
            ;;
        *)
            log_error "Unsupported export format: ${format}"
            log_info "Supported formats: json, pcap, sqlite, html"
            return 1
            ;;
    esac
    
    log_success "Evidence exported successfully"
}

# NEW v2.1: Manual traffic classification
classify_traffic() {
    local rule="${CLASSIFICATION_RULE:-}"
    
    if [[ -z "${rule}" ]]; then
        log_info "Available classification rules:"
        list_classification_rules
        return 0
    fi
    
    log_info "Applying classification rule: ${rule}"
    apply_classification_rule "${rule}" || return 1
    log_success "Classification applied successfully"
}

# Display help information
show_help() {
    cat << EOF
MITMRouter v${MITMROUTER_VERSION} - Linux Router for IoT Traffic Analysis

USAGE:
    ./mitmrouter.sh {up|down|status|restart|logs|export|classify} [OPTIONS]

COMMANDS:
    up          Start MITMRouter services with specified profile
    down        Stop all MITMRouter services
    status      Display current service status (NEW: includes v2.1 features)
    restart     Restart all services
    logs        Display service logs
    health      Run health checks
    export      Export captured evidence (NEW in v2.1)
    classify    Apply traffic classification rules (NEW in v2.1)

OPTIONS:
    --profile PROFILE      Configuration profile to use
                          Available: default, pentest, forensic, pinning
                          (default: default)
    
    --config FILE         Custom configuration file path
    --format FORMAT       Export format: json, pcap, sqlite, html (for export command)
    --rule RULE          Classification rule to apply (for classify command)
    --help, -h           Display this help message

EXAMPLES:
    # Start with default profile
    sudo ./mitmrouter.sh up
    
    # Start with forensic evidence collection
    sudo ./mitmrouter.sh up --profile forensic
    
    # Export evidence as JSON
    sudo ./mitmrouter.sh export --format json
    
    # Apply custom classification rule
    sudo ./mitmrouter.sh classify --rule "iot_device"
    
    # Check v2.1 status
    ./mitmrouter.sh status

NEW IN v2.1.0:
    - Traffic Classification: Automatic protocol and device detection
    - MITMProxy Addons: Dynamic payload injection and modification
    - Evidence Export: Chain-of-custody compliant export (JSON, PCAP, SQLite, HTML)
    - Certificate Pinning: Automated certificate generation and deployment
    - Profile Orchestration: Multi-profile management

SYSTEM REQUIREMENTS:
    - Linux (Ubuntu 20.04+, Debian 11+, Fedora 36+)
    - Root/sudo privileges
    - WiFi interface capable of AP mode
    - Ethernet interface for WAN
    - Python 3.9+ (for MITMProxy and addons)

DEPENDENCIES:
    - hostapd, dnsmasq, iptables, bridge-utils
    - mitmproxy 10.4.2+
    - tcpdump (for PCAP export)
    - sqlite3 (for SQLite export)
    - jq (for JSON processing)

DOCUMENTATION:
    See docs/v2.1/ for detailed feature documentation
EOF
}

# Main execution
main() {
    # Initialize system
    initialize_system
    
    # Handle commands
    case "${COMMAND}" in
        up)
            load_configuration || exit 1
            start_services || exit 1
            ;;
        down)
            stop_services || exit 1
            ;;
        status)
            [[ -f "${STATE_DIR}/active_profile" ]] && load_configuration
            show_status
            ;;
        restart)
            load_configuration || exit 1
            stop_services || exit 1
            sleep 2
            start_services || exit 1
            ;;
        logs)
            tail -f "${LOG_DIR}/mitmrouter.log"
            ;;
        health)
            load_configuration || exit 1
            run_health_checks || exit 1
            ;;
        export)
            load_configuration || exit 1
            export_evidence || exit 1
            ;;
        classify)
            load_configuration || exit 1
            classify_traffic || exit 1
            ;;
        *)
            log_error "Unknown command: ${COMMAND}"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function with error handling
main "$@" || {
    log_error "MITMRouter operation failed (exit code: $?)"
    exit 1
}
