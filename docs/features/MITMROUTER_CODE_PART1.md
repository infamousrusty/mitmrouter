# MITMROUTER v2.0 - ALL PRODUCTION CODE FILES
# Complete Implementation - Copy-Paste Ready

================================================================================
FILE 1: mitmrouter.sh (Main Entry Point)
================================================================================
Location: ./mitmrouter.sh
Permissions: chmod +x mitmrouter.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter v2.0 - Linux Router for IoT Traffic Analysis & SSL MITM
# Modernized with configuration management, error handling, and monitoring
# 
# Usage: ./mitmrouter.sh {up|down|status|restart|logs} [OPTIONS]
# Options:
#   --profile     Config profile (default, pentest, production)
#   --config      Custom config file path
#   --help        Show this help message
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

# Global configuration
readonly MITMROUTER_VERSION="2.0.0"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly STATE_DIR="/var/lib/mitmrouter"
readonly LOG_DIR="/var/log/mitmrouter"

# Parse command line arguments
COMMAND="${1:-up}"
PROFILE="${2:-default}"
CUSTOM_CONFIG=""

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
    mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${CONFIG_DIR}/certs"
    chmod 750 "${STATE_DIR}" "${LOG_DIR}"
    
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
        log_info "Available profiles: $(ls -1 ${CONFIG_DIR}/profiles/*.yml 2>/dev/null | xargs -n1 basename | sed 's/.yml//')"
        return 1
    fi
    
    log_info "Loading configuration from: ${config_file}"
    parse_yaml "${config_file}"
    
    # Validate required configuration keys
    validate_config || return 1
    
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
    log_info "Starting MITMRouter services..."
    
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
    
    # Start MITMProxy
    start_mitmproxy || return 1
    
    # Initialize monitoring
    initialize_monitoring || return 1
    
    log_success "All services started successfully"
    
    # Save state
    echo "${PROFILE}" > "${STATE_DIR}/active_profile"
}

# Stop all services
stop_services() {
    log_info "Stopping MITMRouter services..."
    
    # Stop MITMProxy
    stop_mitmproxy
    
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
    log_info "MITMRouter Status Report"
    echo "=========================="
    
    # Check if active
    if [[ -f "${STATE_DIR}/active_profile" ]]; then
        local active_profile=$(cat "${STATE_DIR}/active_profile")
        echo "Status: RUNNING (Profile: ${active_profile})"
    else
        echo "Status: STOPPED"
        return 0
    fi
    
    # Check services
    echo ""
    echo "Service Status:"
    systemctl is-active hostapd >/dev/null 2>&1 && echo "  hostapd: RUNNING" || echo "  hostapd: STOPPED"
    systemctl is-active dnsmasq >/dev/null 2>&1 && echo "  dnsmasq: RUNNING" || echo "  dnsmasq: STOPPED"
    
    # Check network interfaces
    echo ""
    echo "Network Interfaces:"
    ip link show "${network_bridge_name}" 2>/dev/null && echo "  ${network_bridge_name}: UP" || echo "  ${network_bridge_name}: DOWN"
    
    # Check MITMProxy
    echo ""
    echo "MITMProxy:"
    if pgrep -f "mitmproxy" >/dev/null; then
        echo "  Status: RUNNING"
        echo "  Listen Port: ${mitmproxy_listen_port:-8080}"
        echo "  Web Interface: http://localhost:${mitmproxy_web_port:-8081}"
    else
        echo "  Status: STOPPED"
    fi
    
    # Connected clients
    if command -v iw &>/dev/null; then
        local connected=$(iw dev "${network_wlan_interface}" station dump 2>/dev/null | grep -c "Station" || echo "0")
        echo ""
        echo "Connected Devices: ${connected}"
    fi
}

# Display help information
show_help() {
    cat << EOF
MITMRouter v${MITMROUTER_VERSION} - Linux Router for IoT Traffic Analysis

USAGE:
    ./mitmrouter.sh {up|down|status|restart|logs} [OPTIONS]

COMMANDS:
    up          Start MITMRouter services with specified profile
    down        Stop all MITMRouter services
    status      Display current service status
    restart     Restart all services
    logs        Display service logs
    health      Run health checks

OPTIONS:
    --profile PROFILE    Configuration profile to use
                        Available: default, pentest, production
                        (default: default)
    
    --config FILE       Custom configuration file path
    --help, -h         Display this help message

EXAMPLES:
    # Start with default profile
    sudo ./mitmrouter.sh up
    
    # Start with pentest profile
    sudo ./mitmrouter.sh up --profile pentest
    
    # Stop services
    sudo ./mitmrouter.sh down
    
    # Check status
    ./mitmrouter.sh status
    
    # View logs
    ./mitmrouter.sh logs

SYSTEM REQUIREMENTS:
    - Linux (Ubuntu 20.04+, Debian 11+, Fedora 36+)
    - Root/sudo privileges
    - WiFi interface capable of AP mode
    - Ethernet interface for WAN

DEPENDENCIES:
    - hostapd          WiFi access point daemon
    - dnsmasq          DHCP and DNS server
    - iptables         Network packet filter
    - bridge-utils     Network bridging
    - mitmproxy        Traffic interception proxy
    - Python 3.9+

DOCUMENTATION:
    See docs/INSTALLATION.md for detailed setup instructions
    See docs/CONFIGURATION.md for all configuration options
    See docs/TROUBLESHOOTING.md for common issues

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
```

================================================================================
FILE 2: lib/logging.sh (Structured Logging)
================================================================================
Location: ./lib/logging.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter Logging System
# Provides structured logging with timestamps and severity levels
################################################################################

# Logging configuration
readonly LOG_DIR="${LOG_DIR:-/var/log/mitmrouter}"
readonly LOG_FILE="${LOG_DIR}/mitmrouter.log"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Color codes for terminal output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "${LOG_DIR}" 2>/dev/null || true

# Log level hierarchy
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [CRITICAL]=4
)

# Get current log level numeric value
get_log_level() {
    echo "${LOG_LEVELS[${LOG_LEVEL}]:-1}"
}

# Check if message should be logged
should_log() {
    local message_level="${LOG_LEVELS[$1]:-1}"
    local current_level=$(get_log_level)
    [[ ${message_level} -ge ${current_level} ]]
}

# Core logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if message should be logged
    if ! should_log "${level}"; then
        return 0
    fi
    
    # Format log message
    local formatted_msg="[${timestamp}] [${level}] ${message}"
    
    # Write to log file
    echo "${formatted_msg}" >> "${LOG_FILE}" 2>/dev/null || true
    
    # Write to stderr with colors (for interactive use)
    if [[ -t 2 ]]; then
        case "${level}" in
            DEBUG)
                echo -e "${COLOR_BLUE}${formatted_msg}${COLOR_NC}" >&2
                ;;
            INFO)
                echo -e "${COLOR_GREEN}${formatted_msg}${COLOR_NC}" >&2
                ;;
            WARN)
                echo -e "${COLOR_YELLOW}${formatted_msg}${COLOR_NC}" >&2
                ;;
            ERROR|CRITICAL)
                echo -e "${COLOR_RED}${formatted_msg}${COLOR_NC}" >&2
                ;;
        esac
    else
        echo "${formatted_msg}" >&2
    fi
}

# Convenience logging functions
log_debug() {
    log DEBUG "$@"
}

log_info() {
    log INFO "$@"
}

log_warn() {
    log WARN "$@"
}

log_error() {
    log ERROR "$@"
}

log_critical() {
    log CRITICAL "$@"
}

# Log success (green INFO message)
log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[${timestamp}] [SUCCESS] $*"
    
    echo "${message}" >> "${LOG_FILE}" 2>/dev/null || true
    
    if [[ -t 2 ]]; then
        echo -e "${COLOR_GREEN}${message}${COLOR_NC}" >&2
    else
        echo "${message}" >&2
    fi
}

# Log command execution for debugging
log_command() {
    local cmd="$*"
    log_debug "Executing: ${cmd}"
    eval "${cmd}"
}

# Rotate log files
rotate_logs() {
    local max_size=$((100 * 1024)) # 100MB
    
    if [[ -f "${LOG_FILE}" ]]; then
        local size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}")
        
        if [[ ${size} -gt ${max_size} ]]; then
            local timestamp=$(date +%Y%m%d_%H%M%S)
            mv "${LOG_FILE}" "${LOG_FILE}.${timestamp}"
            gzip "${LOG_FILE}.${timestamp}" &>/dev/null || true
        fi
    fi
}

# Initialize logging on script start
initialize_logging() {
    # Ensure log directory exists with proper permissions
    mkdir -p "${LOG_DIR}"
    chmod 755 "${LOG_DIR}"
    
    # Create initial log file
    touch "${LOG_FILE}"
    chmod 644 "${LOG_FILE}"
    
    # Log script startup
    log_info "========================================="
    log_info "MITMRouter started at $(date)"
    log_info "Log level: ${LOG_LEVEL}"
    log_info "Log file: ${LOG_FILE}"
    log_info "========================================="
}

# Call on script load
initialize_logging
```

================================================================================
FILE 3: lib/error_handling.sh (Error Management)
================================================================================
Location: ./lib/error_handling.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter Error Handling System
# Provides centralized error handling, trapping, and recovery
################################################################################

# Enable strict error handling
set -o pipefail

# Global error state
declare -g LAST_ERROR=""
declare -g ERROR_COUNT=0
declare -g SCRIPT_FAILED=0

# Error trap handler
trap_error() {
    local line_number=$1
    local exit_code=$2
    
    # Log the error
    log_error "Error on line ${line_number} (exit code: ${exit_code})"
    
    # Increment error counter
    ((ERROR_COUNT++))
    
    # Try to provide context
    if [[ -n "${BASH_SOURCE[1]}" ]]; then
        log_error "Location: ${BASH_SOURCE[1]}:${line_number}"
    fi
    
    # Store error for later reference
    LAST_ERROR="Error at line ${line_number} with exit code ${exit_code}"
    
    # Don't exit immediately - let the script decide
    return 0
}

# Exit trap handler for cleanup
trap_exit() {
    local exit_code=$?
    
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script exiting with code: ${exit_code}"
    else
        log_info "Script completed successfully"
    fi
    
    # Run cleanup functions
    cleanup_on_exit
}

# Cleanup function - override in your script as needed
cleanup_on_exit() {
    # Default: do nothing
    # Override in main script to add custom cleanup
    return 0
}

# Register traps
set -E
trap 'trap_error ${LINENO} $?' ERR
trap trap_exit EXIT

# Execute command with error handling
try_run() {
    local cmd="$*"
    log_debug "Running: ${cmd}"
    
    if eval "${cmd}"; then
        log_debug "Command succeeded: ${cmd}"
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit code: ${exit_code}): ${cmd}"
        return ${exit_code}
    fi
}

# Execute command with retry logic
try_run_with_retry() {
    local max_attempts="${1:-3}"
    local delay="${2:-2}"
    shift 2
    local cmd="$*"
    
    local attempt=1
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_info "Attempt ${attempt}/${max_attempts}: ${cmd}"
        
        if eval "${cmd}"; then
            log_success "Command succeeded on attempt ${attempt}"
            return 0
        fi
        
        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_warn "Attempt ${attempt} failed, retrying in ${delay}s..."
            sleep "${delay}"
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after ${max_attempts} attempts: ${cmd}"
    return 1
}

# Check command exists
require_command() {
    local cmd="$1"
    
    if ! command -v "${cmd}" &>/dev/null; then
        log_error "Required command not found: ${cmd}"
        return 1
    fi
    
    return 0
}

# Check file exists and is readable
require_file() {
    local file="$1"
    
    if [[ ! -r "${file}" ]]; then
        log_error "Required file not found or not readable: ${file}"
        return 1
    fi
    
    return 0
}

# Check directory exists and is writable
require_directory() {
    local dir="$1"
    
    if [[ ! -w "${dir}" ]]; then
        log_error "Required directory not found or not writable: ${dir}"
        return 1
    fi
    
    return 0
}

# Verify command output
verify_output() {
    local cmd="$1"
    local expected_pattern="$2"
    
    local output
    output=$(eval "${cmd}" 2>&1) || return 1
    
    if [[ ${output} =~ ${expected_pattern} ]]; then
        return 0
    else
        log_error "Output verification failed. Expected pattern: ${expected_pattern}"
        log_error "Actual output: ${output}"
        return 1
    fi
}

# Assert condition is true
assert() {
    local condition="$1"
    local message="${2:-Assertion failed: ${condition}}"
    
    if ! eval "[[ ${condition} ]]" 2>/dev/null; then
        log_error "${message}"
        return 1
    fi
    
    return 0
}

# Handle error and optionally exit
handle_error() {
    local message="$1"
    local should_exit="${2:-true}"
    
    log_error "${message}"
    ((ERROR_COUNT++))
    
    if [[ "${should_exit}" == "true" ]]; then
        exit 1
    fi
    
    return 1
}

# Get error count
get_error_count() {
    echo "${ERROR_COUNT}"
}

# Reset error counter
reset_error_count() {
    ERROR_COUNT=0
}

# Check if any errors occurred
had_errors() {
    [[ ${ERROR_COUNT} -gt 0 ]]
}
```

================================================================================
FILE 4: lib/config_parser.sh (Configuration Management)
================================================================================
Location: ./lib/config_parser.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter Configuration Parser
# Parses YAML/JSON configuration files with validation
################################################################################

# Configuration cache
declare -gA CONFIG_CACHE

# Check if required tools are available
_check_config_tools() {
    if ! command -v yq &>/dev/null; then
        log_warn "yq not found, attempting to install..."
        # Install yq if not present
        if command -v apt &>/dev/null; then
            apt-get update && apt-get install -y yq
        elif command -v dnf &>/dev/null; then
            dnf install -y yq
        elif command -v pacman &>/dev/null; then
            pacman -S --noconfirm yq
        else
            log_error "Cannot install yq - please install manually"
            return 1
        fi
    fi
    return 0
}

# Parse YAML configuration file
parse_yaml() {
    local config_file="$1"
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi
    
    log_info "Parsing configuration: ${config_file}"
    
    # Check for yq
    _check_config_tools || return 1
    
    # Extract all key-value pairs from YAML
    # Uses yq to convert YAML to shell-compatible format
    while IFS='=' read -r key value; do
        # Convert dots to underscores for variable names
        # e.g., network.wan_interface -> network_wan_interface
        local var_name="${key//./_}"
        
        # Remove quotes if present
        value="${value%\"}"
        value="${value#\"}"
        
        # Store in cache and set as environment variable
        CONFIG_CACHE["${var_name}"]="${value}"
        export "${var_name}=${value}"
        
        log_debug "Config: ${var_name}=${value}"
    done < <(yq eval -o=json "${config_file}" | python3 -c "
import json, sys
def flatten(d, parent_key='', sep='.'):
    items = []
    for k, v in d.items():
        new_key = f'{parent_key}{sep}{k}' if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten(v, new_key, sep=sep).items())
        else:
            items.append((new_key, str(v)))
    return dict(items)

data = json.load(sys.stdin)
for k, v in flatten(data).items():
    print(f'{k}=\"{v}\"')
")
    
    log_success "Configuration parsed successfully"
    return 0
}

# Get configuration value
config_get() {
    local key="$1"
    local default="${2:-}"
    
    # Convert key format: network.wan -> network_wan
    local var_name="${key//./_}"
    
    # Check cache first
    if [[ -n "${CONFIG_CACHE[${var_name}]:-}" ]]; then
        echo "${CONFIG_CACHE[${var_name}]}"
        return 0
    fi
    
    # Check environment variable
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
        return 0
    fi
    
    # Return default if set, otherwise error
    if [[ -n "${default}" ]]; then
        echo "${default}"
        return 0
    fi
    
    log_warn "Configuration key not found: ${key}"
    return 1
}

# Validate configuration schema
validate_config_schema() {
    local config_file="$1"
    local schema_file="${2:-${SCRIPT_DIR}/config/schema.json}"
    
    if [[ ! -f "${schema_file}" ]]; then
        log_warn "Schema file not found, skipping validation: ${schema_file}"
        return 0
    fi
    
    log_info "Validating configuration against schema..."
    
    # Use Python for JSON schema validation
    python3 << 'PYTHON_SCRIPT'
import json
import jsonschema
import sys

try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    with open(sys.argv[2]) as f:
        schema = json.load(f)
    
    jsonschema.validate(config, schema)
    print("Configuration is valid")
    sys.exit(0)
except jsonschema.ValidationError as e:
    print(f"Validation error: {e.message}")
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYTHON_SCRIPT
    
    return $?
}

# Expand environment variables in configuration
expand_env_vars() {
    local config_file="$1"
    local temp_file="/tmp/mitmrouter_config_expanded.yml"
    
    # Use envsubst to expand variables
    envsubst < "${config_file}" > "${temp_file}"
    
    # Return temp file path
    echo "${temp_file}"
}

# Generate default configuration
generate_default_config() {
    local output_file="$1"
    
    cat > "${output_file}" << 'EOF'
# MITMRouter v2.0 Configuration
# Default Profile

# Network Configuration
network:
  wan_interface: eth0        # Internet-facing interface
  wlan_interface: wlan0      # WiFi interface (AP mode)
  bridge_name: br0           # Bridge interface name

# WiFi Settings
wifi:
  ssid: "MITMRouter-Lab"
  channel: 6
  bandwidth: 20              # MHz (20 or 40)
  password: "${WIFI_PASSWORD:-changeme}"  # Use env var or default
  hidden: false
  # 802.11 standard
  # a = 5GHz
  # b/g = 2.4GHz
  # n = 2.4GHz or 5GHz
  # ac = 5GHz
  standard: g

# DHCP Configuration
dhcp:
  start_ip: 192.168.100.100
  end_ip: 192.168.100.150
  subnet_mask: 255.255.255.0
  gateway: 192.168.100.1
  dns_servers:
    - 8.8.8.8
    - 8.8.4.4
  lease_time: 3600          # seconds

# MITMProxy Configuration
mitmproxy:
  version: "10.4.2"
  listen_port: 8080
  web_port: 8081            # Web interface port
  mode: "transparent"       # or "regular" or "socks5"
  cert_dir: /etc/mitmrouter/certs
  cert_expiry_days: 90
  log_level: info
  # Advanced options
  modify_body: false
  modify_headers: false

# Logging Configuration
logging:
  level: INFO                # DEBUG, INFO, WARN, ERROR
  output: /var/log/mitmrouter/mitmrouter.log
  max_size_mb: 100
  retention_days: 30

# Network Settings
network_settings:
  # Enable IP forwarding
  ip_forwarding: true
  # Enable NAT
  nat_enabled: true
  # Firewall rules
  firewall_rules: []

# Monitoring
monitoring:
  enabled: true
  prometheus_port: 9090
  metrics_interval: 30      # seconds
  export_file: /var/lib/mitmrouter/metrics.prom
EOF
    
    log_success "Default configuration generated: ${output_file}"
}

# Load all configurations from directory
load_config_profiles() {
    local profile_dir="${1:-${SCRIPT_DIR}/config/profiles}"
    
    if [[ ! -d "${profile_dir}" ]]; then
        log_error "Profile directory not found: ${profile_dir}"
        return 1
    fi
    
    log_info "Available configuration profiles:"
    for profile_file in "${profile_dir}"/*.yml; do
        if [[ -f "${profile_file}" ]]; then
            local profile_name=$(basename "${profile_file}" .yml)
            echo "  - ${profile_name}"
        fi
    done
    
    return 0
}

# Merge configurations (base + overrides)
merge_configs() {
    local base_config="$1"
    local override_config="$2"
    local output_config="$3"
    
    log_info "Merging configuration files..."
    
    # Use yq to merge YAML files (override takes precedence)
    yq eval-all '. as $item ireduce ({}; . * $item)' \
        "${base_config}" "${override_config}" > "${output_config}"
    
    log_success "Configurations merged: ${output_config}"
}
```

(Continuing with remaining files...)
```

================================================================================
FILE 5: lib/network_setup.sh (Network Configuration)
================================================================================
Location: ./lib/network_setup.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter Network Setup
# Configures bridge, hostapd, dnsmasq, and NAT/forwarding
################################################################################

# Dependency verification
verify_dependencies() {
    log_info "Verifying dependencies..."
    
    local required_cmds=(
        "hostapd"
        "dnsmasq"
        "brctl"
        "ip"
        "iptables"
        "iw"
        "systemctl"
    )
    
    local missing_cmds=()
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "${cmd}" &>/dev/null; then
            missing_cmds+=("${cmd}")
        fi
    done
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Install them using your package manager (apt, dnf, pacman)"
        return 1
    fi
    
    log_success "All dependencies verified"
    return 0
}

# Set up network bridge
setup_bridge() {
    local wan_if="${network_wan_interface}"
    local wlan_if="${network_wlan_interface}"
    local bridge="${network_bridge_name:-br0}"
    
    log_info "Setting up bridge: ${bridge}"
    
    # Check if bridge already exists
    if ip link show "${bridge}" &>/dev/null; then
        log_info "Bridge ${bridge} already exists, removing..."
        ip link set "${bridge}" down 2>/dev/null || true
        brctl delbr "${bridge}" 2>/dev/null || true
    fi
    
    # Create bridge
    brctl addbr "${bridge}" || return 1
    
    # Add interfaces to bridge
    brctl addif "${bridge}" "${wlan_if}" || {
        log_error "Failed to add ${wlan_if} to bridge"
        return 1
    }
    
    # Configure bridge IP
    ip addr add "${dhcp_gateway}/24" dev "${bridge}" || return 1
    ip link set "${bridge}" up || return 1
    
    log_success "Bridge configured: ${bridge}"
    return 0
}

# Tear down network bridge
teardown_bridge() {
    local bridge="${network_bridge_name:-br0}"
    
    log_info "Tearing down bridge: ${bridge}"
    
    if ip link show "${bridge}" &>/dev/null; then
        ip link set "${bridge}" down 2>/dev/null || true
        brctl delbr "${bridge}" 2>/dev/null || true
    fi
    
    log_success "Bridge removed"
    return 0
}

# Configure hostapd (WiFi AP)
setup_hostapd() {
    log_info "Configuring hostapd..."
    
    local hostapd_conf="/etc/hostapd/mitmrouter.conf"
    local wlan_if="${network_wlan_interface}"
    local bridge="${network_bridge_name:-br0}"
    
    # Generate hostapd configuration
    cat > "${hostapd_conf}" << EOF
# MITMRouter hostapd Configuration
interface=${wlan_if}
bridge=${bridge}
driver=nl80211

# WiFi Settings
ssid=${wifi_ssid}
channel=${wifi_channel:-6}
hw_mode=${wifi_standard:-g}
wmm_enabled=1
macaddr_acl=0
auth_algs=1

# Security
wpa=2
wpa_passphrase=${wifi_password}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP TKIP
wpa_group_rekey=86400

# Logging
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2

# Additional settings
ignore_broadcast_ssid=${wifi_hidden:-0}
beacon_int=100
dtim_period=2
rts_threshold=2347
frag_threshold=2346
ap_isolate=0
EOF
    
    # Start hostapd
    log_info "Starting hostapd..."
    systemctl start hostapd || return 1
    systemctl enable hostapd 2>/dev/null || true
    
    log_success "hostapd configured and running"
    return 0
}

# Configure dnsmasq (DHCP and DNS)
setup_dnsmasq() {
    log_info "Configuring dnsmasq..."
    
    local dnsmasq_conf="/etc/dnsmasq.d/mitmrouter.conf"
    local bridge="${network_bridge_name:-br0}"
    
    # Generate dnsmasq configuration
    cat > "${dnsmasq_conf}" << EOF
# MITMRouter dnsmasq Configuration

# Interface to bind to
interface=${bridge}
listen-address=${dhcp_gateway}

# DHCP Configuration
dhcp-range=${dhcp_start_ip},${dhcp_end_ip},${dhcp_subnet_mask},${dhcp_lease_time}

# DNS Servers
server=${dhcp_dns_servers[0]:-8.8.8.8}
server=${dhcp_dns_servers[1]:-8.8.4.4}

# DNS Options
dhcp-option=option:dns-server,${dhcp_gateway}
dhcp-option=option:router,${dhcp_gateway}

# Logging
log-facility=/var/log/mitmrouter/dnsmasq.log
log-dhcp
log-queries

# Performance tuning
cache-size=10000
EOF
    
    # Start dnsmasq
    log_info "Starting dnsmasq..."
    systemctl restart dnsmasq || return 1
    systemctl enable dnsmasq 2>/dev/null || true
    
    log_success "dnsmasq configured and running"
    return 0
}

# Enable IP forwarding and NAT
enable_ip_forwarding() {
    log_info "Enabling IP forwarding and NAT..."
    
    local wan_if="${network_wan_interface}"
    local bridge="${network_bridge_name:-br0}"
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1 || return 1
    
    # Make persistent
    echo "net.ipv4.ip_forward=1" | tee -a /etc/sysctl.conf >/dev/null
    
    # Setup NAT rules
    iptables -t nat -A POSTROUTING -o "${wan_if}" -j MASQUERADE || return 1
    iptables -A FORWARD -i "${bridge}" -o "${wan_if}" -j ACCEPT || return 1
    iptables -A FORWARD -i "${wan_if}" -o "${bridge}" -m state --state RELATED,ESTABLISHED -j ACCEPT || return 1
    
    # Setup transparent proxy rules for MITM
    iptables -t nat -A PREROUTING -i "${bridge}" -p tcp --dport 80 -j REDIRECT --to-port ${mitmproxy_listen_port:-8080} || return 1
    iptables -t nat -A PREROUTING -i "${bridge}" -p tcp --dport 443 -j REDIRECT --to-port ${mitmproxy_listen_port:-8080} || return 1
    
    log_success "IP forwarding and NAT enabled"
    return 0
}

# Clean up iptables rules
cleanup_iptables() {
    log_info "Cleaning up iptables rules..."
    
    local wan_if="${network_wan_interface}"
    local bridge="${network_bridge_name:-br0}"
    
    # Remove NAT rules
    iptables -t nat -D POSTROUTING -o "${wan_if}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "${bridge}" -o "${wan_if}" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "${wan_if}" -o "${bridge}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    # Remove transparent proxy rules
    iptables -t nat -D PREROUTING -i "${bridge}" -p tcp --dport 80 -j REDIRECT --to-port ${mitmproxy_listen_port:-8080} 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${bridge}" -p tcp --dport 443 -j REDIRECT --to-port ${mitmproxy_listen_port:-8080} 2>/dev/null || true
    
    log_success "iptables rules cleaned"
    return 0
}

# Get connected clients
get_connected_clients() {
    local wlan_if="${network_wlan_interface}"
    
    if command -v iw &>/dev/null; then
        iw dev "${wlan_if}" station dump | grep -E "^Station|signal" | sed 'N;s/\\n/ /'
    else
        log_warn "iw command not available"
        return 1
    fi
}

# Show network statistics
show_network_stats() {
    local bridge="${network_bridge_name:-br0}"
    
    log_info "Network Statistics for ${bridge}:"
    
    if [[ -d "/sys/class/net/${bridge}" ]]; then
        local rx_bytes=$(cat "/sys/class/net/${bridge}/statistics/rx_bytes" 2>/dev/null || echo "0")
        local tx_bytes=$(cat "/sys/class/net/${bridge}/statistics/tx_bytes" 2>/dev/null || echo "0")
        local rx_packets=$(cat "/sys/class/net/${bridge}/statistics/rx_packets" 2>/dev/null || echo "0")
        local tx_packets=$(cat "/sys/class/net/${bridge}/statistics/tx_packets" 2>/dev/null || echo "0")
        
        echo "RX: ${rx_packets} packets, ${rx_bytes} bytes"
        echo "TX: ${tx_packets} packets, ${tx_bytes} bytes"
    fi
}
```

(Due to length limits, I'll create a continuation file with the remaining scripts...)
```

================================================================================

END OF PART 1 - Core Files 1-5

See next file for:
- FILE 6: lib/mitmproxy_manager.sh
- FILE 7: lib/monitoring.sh  
- FILE 8: lib/docker_utils.sh
- FILE 9: All GitHub Actions workflows
- FILE 10: All configuration files (YAML, JSON)
- FILE 11: All test files (BATS)
- FILE 12: All documentation files

================================================================================
