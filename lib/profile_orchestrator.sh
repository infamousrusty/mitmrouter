#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Profile Orchestrator
# Multi-profile management and coordinated service orchestration
################################################################################

readonly PROFILES_DIR="${CONFIG_DIR}/profiles"
readonly ORCHESTRATOR_STATE="${STATE_DIR}/orchestrator"

initialize_orchestrator() {
    log_info "Initialising profile orchestrator..."
    mkdir -p "${ORCHESTRATOR_STATE}"
    chmod 750 "${ORCHESTRATOR_STATE}"
    create_default_profiles
    log_success "Profile orchestrator initialised"
    return 0
}

create_default_profiles() {
    local forensic_profile="${PROFILES_DIR}/forensic.yml"
    if [[ ! -f "${forensic_profile}" ]]; then
        cat > "${forensic_profile}" << 'YAML_EOF'
# MITMRouter v2.1.0 Forensic Analysis Profile
network:
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0
wifi:
  ssid: "Forensic-Lab-Capture"
  channel: 11
  standard: g
  password: "${WIFI_PASSWORD_FORENSIC:-changeme}"
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
traffic_classification:
  enabled: true
  interval: 5
evidence_export:
  enabled: true
  formats: ["json", "sqlite", "html"]
  chain_of_custody: true
cert_pinning:
  enabled: true
  auto_serve: true
  server_port: 8000
logging:
  level: DEBUG
YAML_EOF
        chmod 644 "${forensic_profile}"
        log_success "Forensic profile created: ${forensic_profile}"
    fi

    local pentest_profile="${PROFILES_DIR}/pentest.yml"
    if [[ ! -f "${pentest_profile}" ]]; then
        cat > "${pentest_profile}" << 'YAML_EOF'
# MITMRouter v2.1.0 Penetration Testing Profile
network:
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0
wifi:
  ssid: "PentestAP"
  channel: 6
  standard: n
  password: "${WIFI_PASSWORD_PENTEST:-changeme}"
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
traffic_classification:
  enabled: true
  interval: 10
evidence_export:
  enabled: false
cert_pinning:
  enabled: true
  auto_serve: true
  server_port: 8000
logging:
  level: INFO
YAML_EOF
        chmod 644 "${pentest_profile}"
        log_success "Pentest profile created: ${pentest_profile}"
    fi

    local iot_profile="${PROFILES_DIR}/iot_research.yml"
    if [[ ! -f "${iot_profile}" ]]; then
        cat > "${iot_profile}" << 'YAML_EOF'
# MITMRouter v2.1.0 IoT Research Profile
network:
  wan_interface: eth0
  wlan_interface: wlan0
  bridge_name: br0
wifi:
  ssid: "IoT-Research-Lab"
  channel: 6
  standard: g
  password: "${WIFI_PASSWORD_IOT:-changeme}"
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
traffic_classification:
  enabled: true
  interval: 5
evidence_export:
  enabled: true
  formats: ["json", "pcap"]
cert_pinning:
  enabled: true
  auto_serve: true
  server_port: 8000
logging:
  level: INFO
YAML_EOF
        chmod 644 "${iot_profile}"
        log_success "IoT research profile created: ${iot_profile}"
    fi
}

list_available_profiles() {
    if [[ ! -d "${PROFILES_DIR}" ]]; then
        echo "none"; return 1
    fi
    find "${PROFILES_DIR}" -name "*.yml" -exec basename {} .yml \; | tr '\n' ', ' | sed 's/,$//'
}

switch_profile() {
    local target_profile="$1"
    local profile_file="${PROFILES_DIR}/${target_profile}.yml"
    if [[ ! -f "${profile_file}" ]]; then
        log_error "Profile not found: ${target_profile}"
        log_info "Available profiles: $(list_available_profiles)"
        return 1
    fi
    log_info "Switching to profile: ${target_profile}"
    stop_services
    # Export PROFILE so the caller (mitmrouter.sh) picks up the new value
    export PROFILE="${target_profile}"
    load_configuration || return 1
    start_services || return 1
    log_success "Switched to profile: ${target_profile}"
    return 0
}

compare_profiles() {
    local profile1="$1"
    local profile2="$2"
    local file1="${PROFILES_DIR}/${profile1}.yml"
    local file2="${PROFILES_DIR}/${profile2}.yml"
    if [[ ! -f "${file1}" ]] || [[ ! -f "${file2}" ]]; then
        log_error "One or both profiles not found"; return 1
    fi
    log_info "Comparing profiles: ${profile1} vs ${profile2}"
    if command -v diff &>/dev/null; then
        diff -u "${file1}" "${file2}" || true
    else
        log_warn "diff command not available"; return 1
    fi
}

clone_profile() {
    local source_profile="$1"
    local target_profile="$2"
    local source_file="${PROFILES_DIR}/${source_profile}.yml"
    local target_file="${PROFILES_DIR}/${target_profile}.yml"
    if [[ ! -f "${source_file}" ]]; then
        log_error "Source profile not found: ${source_profile}"; return 1
    fi
    if [[ -f "${target_file}" ]]; then
        log_error "Target profile already exists: ${target_profile}"; return 1
    fi
    cp "${source_file}" "${target_file}"
    log_success "Profile cloned: ${source_profile} → ${target_profile}"
    log_info "Edit ${target_file} to customise"
    return 0
}

validate_profile() {
    local profile_name="$1"
    local profile_file="${PROFILES_DIR}/${profile_name}.yml"
    if [[ ! -f "${profile_file}" ]]; then
        log_error "Profile not found: ${profile_name}"; return 1
    fi
    log_info "Validating profile: ${profile_name}"
    if command -v python3 &>/dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('${profile_file}'))" 2>/dev/null || {
            log_error "Invalid YAML syntax in profile"; return 1
        }
    fi
    local required_keys=("network" "wifi" "dhcp" "mitmproxy")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^${key}:" "${profile_file}"; then
            log_error "Missing required section: ${key}"; return 1
        fi
    done
    log_success "Profile validation passed: ${profile_name}"
    return 0
}

get_active_profile() {
    if [[ -f "${STATE_DIR}/active_profile" ]]; then
        cat "${STATE_DIR}/active_profile"
    else
        echo "none"
    fi
}

export_profile_template() {
    local profile_name="$1"
    local output_file="${2:-${profile_name}_template.yml}"
    local source_file="${PROFILES_DIR}/${profile_name}.yml"
    if [[ ! -f "${source_file}" ]]; then
        log_error "Profile not found: ${profile_name}"; return 1
    fi
    sed 's/password: .*/password: "CHANGEME"/g' "${source_file}" > "${output_file}"
    log_success "Profile template exported: ${output_file}"
    return 0
}
