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
# Usage: ./mitmrouter.sh {up|down|status|restart|logs|export|classify|health} [OPTIONS]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/error_handling.sh"
source "${SCRIPT_DIR}/lib/config_parser.sh"
source "${SCRIPT_DIR}/lib/network_setup.sh"
source "${SCRIPT_DIR}/lib/mitmproxy_manager.sh"
source "${SCRIPT_DIR}/lib/monitoring.sh"
source "${SCRIPT_DIR}/lib/traffic_classifier.sh"
source "${SCRIPT_DIR}/lib/addon_manager.sh"
source "${SCRIPT_DIR}/lib/evidence_export.sh"
source "${SCRIPT_DIR}/lib/cert_toolkit.sh"
source "${SCRIPT_DIR}/lib/profile_orchestrator.sh"

readonly MITMROUTER_VERSION="2.1.0"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly STATE_DIR="/var/lib/mitmrouter"
readonly LOG_DIR="/var/log/mitmrouter"
readonly EVIDENCE_DIR="${STATE_DIR}/evidence"

COMMAND="${1:-up}"
PROFILE="${2:-default}"
CUSTOM_CONFIG=""
EXPORT_FORMAT=""
CLASSIFICATION_RULE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) PROFILE="$2"; shift 2 ;;
        --config)  CUSTOM_CONFIG="$2"; shift 2 ;;
        --format)  EXPORT_FORMAT="$2"; shift 2 ;;
        --rule)    CLASSIFICATION_RULE="$2"; shift 2 ;;
        --help|-h) show_help; exit 0 ;;
        *) shift ;;
    esac
done

initialize_system() {
    log_info "Initializing MITMRouter v${MITMROUTER_VERSION}"
    mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${CONFIG_DIR}/certs" "${EVIDENCE_DIR}"
    mkdir -p "${STATE_DIR}/classifications" "${STATE_DIR}/addons" "${STATE_DIR}/profiles"
    chmod 750 "${STATE_DIR}" "${LOG_DIR}" "${EVIDENCE_DIR}"
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    log_success "System initialization complete"
}

load_configuration() {
    local config_file="${CUSTOM_CONFIG:-${CONFIG_DIR}/profiles/${PROFILE}.yml}"
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        log_info "Available profiles: $(list_available_profiles)"
        return 1
    fi
    log_info "Loading configuration from: ${config_file}"
    parse_yaml "${config_file}"
    validate_config || return 1
    initialize_classifier  || log_warn "Classifier initialization failed"
    initialize_addon_manager || log_warn "Addon manager initialization failed"
    log_success "Configuration loaded successfully"
}

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

start_services() {
    log_info "Starting MITMRouter v${MITMROUTER_VERSION} services..."
    verify_dependencies || return 1
    install_mitmproxy "${mitmproxy_version:-10.4.2}" || return 1
    setup_bridge   || return 1
    setup_hostapd  || return 1
    setup_dnsmasq  || return 1
    enable_ip_forwarding || return 1
    if [[ "${cert_pinning_enabled:-false}" == "true" ]]; then
        deploy_pinning_certs || log_warn "Certificate pinning setup incomplete"
    fi
    if [[ -n "${mitmproxy_addons:-}" ]]; then
        load_addons "${mitmproxy_addons}" || log_warn "Some addons failed to load"
    fi
    start_mitmproxy || return 1
    if [[ "${traffic_classification_enabled:-true}" == "true" ]]; then
        start_traffic_classifier || log_warn "Traffic classifier failed to start"
    fi
    initialize_monitoring || return 1
    log_success "All services started successfully"
    echo "${PROFILE}" > "${STATE_DIR}/active_profile"
    date -u +%Y-%m-%dT%H:%M:%SZ > "${STATE_DIR}/startup_time"
}

stop_services() {
    log_info "Stopping MITMRouter services..."
    stop_traffic_classifier 2>/dev/null || true
    stop_mitmproxy 2>/dev/null || true
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    teardown_bridge || true
    sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
    log_success "All services stopped"
}

show_status() {
    log_info "MITMRouter v${MITMROUTER_VERSION} Status Report"
    echo "=============================================="

    if [[ -f "${STATE_DIR}/active_profile" ]]; then
        local active_profile
        active_profile=$(cat "${STATE_DIR}/active_profile")
        local startup_time
        startup_time=$(cat "${STATE_DIR}/startup_time" 2>/dev/null || echo "unknown")
        echo "Status:  RUNNING"
        echo "Profile: ${active_profile}"
        echo "Started: ${startup_time}"
    else
        echo "Status: STOPPED"
        return 0
    fi

    echo ""
    echo "Core Services:"
    systemctl is-active hostapd >/dev/null 2>&1 && echo "  hostapd: ✓ RUNNING" || echo "  hostapd: ✗ STOPPED"
    systemctl is-active dnsmasq >/dev/null 2>&1 && echo "  dnsmasq: ✓ RUNNING" || echo "  dnsmasq: ✗ STOPPED"

    echo ""
    echo "Network Interfaces:"
    # shellcheck disable=SC2154
    ip link show "${network_bridge_name}" 2>/dev/null && echo "  ${network_bridge_name}: ✓ UP" || echo "  bridge: ✗ DOWN"

    echo ""
    echo "MITMProxy:"
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then
        echo "  Status: ✓ RUNNING"
        echo "  Listen Port: ${mitmproxy_listen_port:-8080}"
        echo "  Web Interface: http://localhost:${mitmproxy_web_port:-8081}"
        local loaded_addons
        loaded_addons=$(list_loaded_addons 2>/dev/null || echo "none")
        echo "  Addons: ${loaded_addons}"
    else
        echo "  Status: ✗ STOPPED"
    fi

    echo ""
    echo "Traffic Classifier:"
    if pgrep -f "traffic_classifier" >/dev/null 2>&1; then
        echo "  Status: ✓ RUNNING"
        local classified_count
        classified_count=$(get_classification_count 2>/dev/null || echo "0")
        echo "  Classified Flows: ${classified_count}"
    else
        echo "  Status: ✗ STOPPED"
    fi

    if command -v iw &>/dev/null; then
        # shellcheck disable=SC2154
        local connected
        connected=$(iw dev "${network_wlan_interface}" station dump 2>/dev/null | grep -c "Station" || echo "0")
        echo ""
        echo "Connected Devices: ${connected}"
    fi

    echo ""
    echo "Evidence Collection:"
    local evidence_files
    evidence_files=$(find "${EVIDENCE_DIR}" -type f 2>/dev/null | wc -l)
    echo "  Captured Files: ${evidence_files}"
    if [[ -f "${STATE_DIR}/chain_of_custody.log" ]]; then
        echo "  Chain-of-Custody: ✓ ENABLED"
    fi
}

export_evidence() {
    local format="${EXPORT_FORMAT:-json}"
    log_info "Exporting evidence in ${format} format..."
    case "${format}" in
        json)   export_evidence_json   || return 1 ;;
        pcap)   export_evidence_pcap   || return 1 ;;
        sqlite) export_evidence_sqlite || return 1 ;;
        html)   export_evidence_html   || return 1 ;;
        *)
            log_error "Unsupported export format: ${format}"
            log_info "Supported formats: json, pcap, sqlite, html"
            return 1
            ;;
    esac
    log_success "Evidence exported successfully"
}

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

show_help() {
    cat << EOF
MITMRouter v${MITMROUTER_VERSION} - Linux Router for IoT Traffic Analysis

USAGE:
    ./mitmrouter.sh {up|down|status|restart|logs|export|classify|health} [OPTIONS]

COMMANDS:
    up          Start MITMRouter services with specified profile
    down        Stop all MITMRouter services
    status      Display current service status
    restart     Restart all services
    logs        Display service logs
    health      Run health checks
    export      Export captured evidence
    classify    Apply traffic classification rules

OPTIONS:
    --profile PROFILE      Configuration profile to use
                           Available: default, pentest, forensic, pinning, ethernet
                           (default: default)
    --config FILE          Custom configuration file path
    --format FORMAT        Export format: json, pcap, sqlite, html (for export command)
    --rule RULE            Classification rule to apply (for classify command)
    --help, -h             Display this help message

EXAMPLES:
    sudo ./mitmrouter.sh up
    sudo ./mitmrouter.sh up --profile forensic
    sudo ./mitmrouter.sh export --format json
    sudo ./mitmrouter.sh classify --rule iot_device
    ./mitmrouter.sh status

SYSTEM REQUIREMENTS:
    Linux (Ubuntu 22.04+ / 24.04 recommended)
    Root/sudo privileges
    WiFi interface capable of AP mode (for wifi_ap/hybrid profiles)
    Two Ethernet interfaces (for ethernet profile)
    Python 3.10+ (for MITMProxy and addons)

See docs/ for full documentation.
EOF
}

main() {
    initialize_system
    case "${COMMAND}" in
        up)
            load_configuration || exit 1
            start_services     || exit 1
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
            stop_services      || exit 1
            sleep 2
            start_services     || exit 1
            ;;
        logs)
            tail -f "${LOG_DIR}/mitmrouter.log"
            ;;
        health)
            load_configuration || exit 1
            run_health_checks  || exit 1
            ;;
        export)
            load_configuration || exit 1
            export_evidence    || exit 1
            ;;
        classify)
            load_configuration || exit 1
            classify_traffic   || exit 1
            ;;
        *)
            log_error "Unknown command: ${COMMAND}"
            show_help
            exit 1
            ;;
    esac
}

main "$@" || {
    log_error "MITMRouter operation failed (exit code: $?)"
    exit 1
}
