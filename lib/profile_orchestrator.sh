#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Profile Orchestrator
# Multi-profile management and coordinated service orchestration
################################################################################

readonly PROFILES_DIR="${CONFIG_DIR}/profiles"
readonly ORCHESTRATOR_STATE="${STATE_DIR}/orchestrator"

# Initialize profile orchestrator
initialize_orchestrator() {
    log_info "Initializing profile orchestrator..."
    
    mkdir -p "${ORCHESTRATOR_STATE}"
    chmod 750 "${ORCHESTRATOR_STATE}"
    
    # Create default profiles if they don't exist
    create_default_profiles
    
    log_success "Profile orchestrator initialized"
    return 0
}

# Create default configuration profiles
create_default_profiles() {
    # Profile 1: Default (already exists from v2.0)
    # We'll enhance it with v2.1 settings
    
    # Profile 2: Forensic Analysis
    local forensic_profile="${PROFILES_DIR}/forensic.yml"
    if [[ ! -f "${forensic_profile}" ]]; then
        cat > "${forensic_profile}" << 'YAML_EOF'
# MITMRouter v2.1.0 Forensic Analysis Profile
# Optimized for evidence collection and chain-of-custody

network:
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0

wifi:
  ssid: "Forensic-Lab-Capture"
  channel: 11
  standard: g
  password: "ForensicSecure2024"
  hidden: false

dhcp:
  start_ip: 192.168.200.100
  end_ip: 192.168.200.150
  subnet_mask: 255.255.255.0
  gateway: 192.168.200.1
  lease_time: 7200

mitmproxy:
  version: "10.4.2"
  listen_port: 8080
  web_port: 8081
  mode: "transparent"
  log_level: debug
  addons: "request_logger,tls_inspector"

# v2.1 Features
traffic_classification:
  enabled: true
  interval: 5
  auto_tag: true

evidence_export:
  enabled: true
  formats: ["json", "sqlite", "html"]
  auto_export_interval: 3600
  gpg_signing: true
  chain_of_custody: true

cert_pinning:
  enabled: true
  auto_serve: true
  server_port: 8000

logging:
  level: DEBUG
  output: /var/log/mitmrouter/forensic.log
YAML_EOF
        chmod 644 "${forensic_profile}"
        log_success "Forensic profile created: ${forensic_profile}"
    fi
    
    # Profile 3: Penetration Testing
    local pentest_profile="${PROFILES_DIR}/pentest.yml"
    if [[ ! -f "${pentest_profile}" ]]; then
        cat > "${pentest_profile}" << 'YAML_EOF'
# MITMRouter v2.1.0 Penetration Testing Profile
# Optimized for active security testing with payload injection

network:
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0

wifi:
  ssid: "PentestAP"
  channel: 6
  standard: n
  password: "PentestSecure2024"
  hidden: true

dhcp:
  start_ip: 192.168.150.100
  end_ip: 192.168.150.200
  subnet_mask: 255.255.255.0
  gateway: 192.168.150.1
  lease_time: 600

mitmproxy:
  version: "10.4.2"
  listen_port: 8080
  web_port: 8081
  mode: "transparent"
  log_level: info
  addons: "header_injector,payload_injector,request_logger"

# v2.1 Features
traffic_classification:
  enabled: true
  interval: 10
  auto_tag: true
  suspicious_tagging: true

evidence_export:
  enabled: false

cert_pinning:
  enabled: true
  auto_serve: true
  server_port: 8000

logging:
  level: INFO
  output: /var/log/mitmrouter/pentest.log
YAML_EOF
        chmod 644 "${pentest_profile}"
        log_success "Pentest profile created: ${pentest_profile}"
    fi
    
    # Profile 4: IoT Research
    local iot_profile="${PROFILES_DIR}/iot_research.yml"
    if [[ ! -f "${iot_profile}" ]]; then
        cat > "${iot_profile}" << 'YAML_EOF'
# MITMRouter v2.1.0 IoT Research Profile
# Optimized for IoT device traffic analysis

network:
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0

wifi:
  ssid: "IoT-Research-Lab"
  channel: 6
  standard: g
  password: "IoTResearch2024"
  hidden: false

dhcp:
  start_ip: 192.168.100.100
  end_ip: 192.168.100.250
  subnet_mask: 255.255.255.0
  gateway: 192.168.100.1
  lease_time: 86400

mitmproxy:
  version: "10.4.2"
  listen_port: 8080
  web_port: 8081
  mode: "transparent"
  log_level: info
  addons: "request_logger,tls_inspector"

# v2.1 Features
traffic_classification:
  enabled: true
  interval: 5
  auto_tag: true
  iot_focus: true

evidence_export:
  enabled: true
  formats: ["json", "pcap"]
  auto_export_interval: 7200

cert_pinning:
  enabled: true
  auto_serve: true
  server_port: 8000

logging:
  level: INFO
  output: /var/log/mitmrouter/iot_research.log
YAML_EOF
        chmod 644 "${iot_profile}"
        log_success "IoT research profile created: ${iot_profile}"
    fi
}

# List available profiles
list_available_profiles() {
    if [[ ! -d "${PROFILES_DIR}" ]]; then
        echo "none"
        return 1
    fi
    
    find "${PROFILES_DIR}" -name "*.yml" -exec basename {} .yml \; | tr '\n' ', ' | sed 's/,$//'
}

# Switch to different profile
switch_profile() {
    local target_profile="$1"
    local profile_file="${PROFILES_DIR}/${target_profile}.yml"
    
    if [[ ! -f "${profile_file}" ]]; then
        log_error "Profile not found: ${target_profile}"
        log_info "Available profiles: $(list_available_profiles)"
        return 1
    fi
    
    log_info "Switching to profile: ${target_profile}"
    
    # Stop current services
    stop_services
    
    # Load new profile
    PROFILE="${target_profile}"
    load_configuration || return 1
    
    # Start services with new profile
    start_services || return 1
    
    log_success "Switched to profile: ${target_profile}"
    return 0
}

# Compare two profiles
compare_profiles() {
    local profile1="$1"
    local profile2="$2"
    
    local file1="${PROFILES_DIR}/${profile1}.yml"
    local file2="${PROFILES_DIR}/${profile2}.yml"
    
    if [[ ! -f "${file1}" ]] || [[ ! -f "${file2}" ]]; then
        log_error "One or both profiles not found"
        return 1
    fi
    
    log_info "Comparing profiles: ${profile1} vs ${profile2}"
    
    if command -v diff &>/dev/null; then
        diff -u "${file1}" "${file2}" || true
    else
        log_warn "diff command not available"
        return 1
    fi
}

# Clone existing profile
clone_profile() {
    local source_profile="$1"
    local target_profile="$2"
    
    local source_file="${PROFILES_DIR}/${source_profile}.yml"
    local target_file="${PROFILES_DIR}/${target_profile}.yml"
    
    if [[ ! -f "${source_file}" ]]; then
        log_error "Source profile not found: ${source_profile}"
        return 1
    fi
    
    if [[ -f "${target_file}" ]]; then
        log_error "Target profile already exists: ${target_profile}"
        return 1
    fi
    
    cp "${source_file}" "${target_file}"
    log_success "Profile cloned: ${source_profile} → ${target_profile}"
    log_info "Edit ${target_file} to customize"
    
    return 0
}

# Validate profile configuration
validate_profile() {
    local profile_name="$1"
    local profile_file="${PROFILES_DIR}/${profile_name}.yml"
    
    if [[ ! -f "${profile_file}" ]]; then
        log_error "Profile not found: ${profile_name}"
        return 1
    fi
    
    log_info "Validating profile: ${profile_name}"
    
    # Basic YAML syntax check
    if command -v python3 &>/dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('${profile_file}'))" 2>/dev/null || {
            log_error "Invalid YAML syntax in profile"
            return 1
        }
    fi
    
    # Check required keys (simplified)
    local required_keys=("network" "wifi" "dhcp" "mitmproxy")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^${key}:" "${profile_file}"; then
            log_error "Missing required section: ${key}"
            return 1
        fi
    done
    
    log_success "Profile validation passed: ${profile_name}"
    return 0
}

# Get active profile name
get_active_profile() {
    if [[ -f "${STATE_DIR}/active_profile" ]]; then
        cat "${STATE_DIR}/active_profile"
    else
        echo "none"
    fi
}

# Export profile as shareable template
export_profile_template() {
    local profile_name="$1"
    local output_file="${2:-${profile_name}_template.yml}"
    
    local source_file="${PROFILES_DIR}/${profile_name}.yml"
    
    if [[ ! -f "${source_file}" ]]; then
        log_error "Profile not found: ${profile_name}"
        return 1
    fi
    
    # Copy and sanitize (remove sensitive data)
    sed 's/password: .*/password: "CHANGEME"/g' "${source_file}" > "${output_file}"
    
    log_success "Profile template exported: ${output_file}"
    return 0
}
