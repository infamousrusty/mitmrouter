#!/bin/bash
################################################################################
# MITMRouter Configuration Parser
# Parses YAML/JSON configuration files with validation
################################################################################

# Configuration cache
declare -gA CONFIG_CACHE

_check_config_tools() {
    if ! command -v yq &>/dev/null; then
        log_warn "yq not found, attempting to install..."
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
    _check_config_tools || return 1

    while IFS='=' read -r key value; do
        local var_name="${key//./_}"
        value="${value%\"}"
        value="${value#\"}"
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
    local var_name="${key//./_}"

    if [[ -n "${CONFIG_CACHE[${var_name}]:-}" ]]; then
        echo "${CONFIG_CACHE[${var_name}]}"
        return 0
    fi
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
        return 0
    fi
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
    envsubst < "${config_file}" > "${temp_file}"
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
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0

# WiFi Settings
wifi:
  ssid: "MITMRouter-Lab"
  channel: 6
  bandwidth: 20
  password: "${WIFI_PASSWORD:-changeme}"
  hidden: false
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
  lease_time: 3600

# MITMProxy Configuration
mitmproxy:
  version: "10.4.2"
  listen_port: 8080
  web_port: 8081
  mode: "transparent"
  cert_dir: /etc/mitmrouter/certs
  cert_expiry_days: 90
  log_level: info
  modify_body: false
  modify_headers: false

# Logging Configuration
logging:
  level: INFO
  output: /var/log/mitmrouter/mitmrouter.log
  max_size_mb: 100
  retention_days: 30

# Monitoring
monitoring:
  enabled: true
  prometheus_port: 9090
  metrics_interval: 30
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
            local profile_name
            profile_name=$(basename "${profile_file}" .yml)
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
    yq eval-all '. as $item ireduce ({}; . * $item)' \
        "${base_config}" "${override_config}" > "${output_config}"
    log_success "Configurations merged: ${output_config}"
}
