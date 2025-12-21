#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Traffic Classification Engine
# Automatic protocol and device detection with rule-based tagging
################################################################################

readonly CLASSIFIER_STATE_DIR="${STATE_DIR}/classifications"
readonly CLASSIFIER_RULES_DIR="${CONFIG_DIR}/classification_rules"
readonly CLASSIFIER_LOG="${LOG_DIR}/classifier.log"
readonly CLASSIFIER_PID_FILE="/var/run/mitmrouter/classifier.pid"

# Initialize traffic classifier
initialize_classifier() {
    log_info "Initializing traffic classifier..."
    
    # Create directories
    mkdir -p "${CLASSIFIER_STATE_DIR}" "${CLASSIFIER_RULES_DIR}"
    chmod 750 "${CLASSIFIER_STATE_DIR}"
    
    # Install default classification rules
    install_default_classification_rules
    
    log_success "Traffic classifier initialized"
    return 0
}

# Install default classification rules
install_default_classification_rules() {
    local rules_file="${CLASSIFIER_RULES_DIR}/default.rules"
    
    if [[ -f "${rules_file}" ]]; then
        log_debug "Default classification rules already exist"
        return 0
    fi
    
    cat > "${rules_file}" << 'EOF'
# MITMRouter Traffic Classification Rules v2.1.0
# Format: <pattern>|<protocol>|<device_type>|<tags>

# IoT Devices
amazon-*.amazonaws.com|HTTPS|alexa|iot,voice_assistant,amazon
*.google.com:443|HTTPS|google_home|iot,voice_assistant,google
*.nest.com|HTTPS|nest|iot,thermostat,google
*.ring.com|HTTPS|ring|iot,camera,amazon

# Smart Home
*.philips-hue.com|HTTPS|philips_hue|iot,lighting
*.lifx.com|HTTPS|lifx|iot,lighting
*.wemo.com|HTTPS|wemo|iot,switch

# Mobile Apps
*.apple.com|HTTPS|ios_device|mobile,apple
*.icloud.com|HTTPS|ios_device|mobile,apple,cloud
android.clients.google.com|HTTPS|android_device|mobile,google
play.googleapis.com|HTTPS|android_device|mobile,google,app_store

# Suspicious Patterns
*:1337|TCP|unknown|suspicious,non_standard_port
*:31337|TCP|unknown|suspicious,backdoor_port
*.onion|TOR|unknown|suspicious,tor,anonymity

# Common Protocols
*:80|HTTP|unknown|web,http,unencrypted
*:443|HTTPS|unknown|web,https,encrypted
*:8080|HTTP|unknown|web,http_alt,proxy
*:3000|HTTP|unknown|web,dev_server
*:22|SSH|unknown|remote_access,ssh
*:3389|RDP|unknown|remote_access,rdp,windows
*:5900|VNC|unknown|remote_access,vnc

# Streaming Services
*.netflix.com|HTTPS|streaming|media,netflix
*.youtube.com|HTTPS|streaming|media,youtube,google
*.spotify.com|HTTPS|streaming|media,spotify,music
*.twitch.tv|HTTPS|streaming|media,twitch,gaming

# Cloud Services
*.dropbox.com|HTTPS|cloud_storage|cloud,storage,dropbox
*.box.com|HTTPS|cloud_storage|cloud,storage,box
s3.amazonaws.com|HTTPS|cloud_storage|cloud,storage,amazon,s3

# DNS Queries
*:53|DNS|dns_server|dns,udp
*:853|DOT|dns_server|dns,tls,encrypted
EOF
    
    chmod 644 "${rules_file}"
    log_success "Default classification rules installed: ${rules_file}"
}

# Start traffic classifier daemon
start_traffic_classifier() {
    log_info "Starting traffic classifier..."
    
    # Check if already running
    if pgrep -F "${CLASSIFIER_PID_FILE}" >/dev/null 2>&1; then
        log_warn "Traffic classifier already running"
        return 0
    fi
    
    # Start classifier in background
    nohup bash -c "
        while true; do
            classify_active_flows
            sleep ${traffic_classification_interval:-10}
        done
    " >> "${CLASSIFIER_LOG}" 2>&1 &
    
    local classifier_pid=$!
    echo "${classifier_pid}" > "${CLASSIFIER_PID_FILE}"
    
    log_success "Traffic classifier started (PID: ${classifier_pid})"
    return 0
}

# Stop traffic classifier
stop_traffic_classifier() {
    log_info "Stopping traffic classifier..."
    
    if [[ -f "${CLASSIFIER_PID_FILE}" ]]; then
        local classifier_pid=$(cat "${CLASSIFIER_PID_FILE}")
        if kill "${classifier_pid}" 2>/dev/null; then
            log_success "Traffic classifier stopped (PID: ${classifier_pid})"
            rm -f "${CLASSIFIER_PID_FILE}"
            return 0
        fi
    fi
    
    # Fallback
    pkill -f "classify_active_flows" 2>/dev/null || true
    log_success "Traffic classifier stopped"
    return 0
}

# Classify active network flows
classify_active_flows() {
    local bridge="${network_bridge_name:-br0}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Capture current connections (simplified - production would use tcpdump/tshark)
    netstat -tn 2>/dev/null | awk '/ESTABLISHED/ {print $5}' | while read -r remote_addr; do
        local host=$(echo "${remote_addr}" | cut -d: -f1)
        local port=$(echo "${remote_addr}" | cut -d: -f2)
        
        # Apply classification rules
        local classification=$(match_classification_rule "${host}" "${port}")
        
        if [[ -n "${classification}" ]]; then
            # Store classification
            echo "${timestamp}|${remote_addr}|${classification}" >> "${CLASSIFIER_STATE_DIR}/flows.log"
        fi
    done
}

# Match host:port against classification rules
match_classification_rule() {
    local host="$1"
    local port="$2"
    local rules_file="${CLASSIFIER_RULES_DIR}/default.rules"
    
    if [[ ! -f "${rules_file}" ]]; then
        return 1
    fi
    
    # Match against patterns (simplified pattern matching)
    while IFS='|' read -r pattern protocol device tags; do
        # Skip comments and empty lines
        [[ "${pattern}" =~ ^#.*$ || -z "${pattern}" ]] && continue
        
        # Convert wildcard pattern to regex
        local regex_pattern="${pattern//\*/.*}"
        
        # Match host:port
        if [[ "${host}:${port}" =~ ${regex_pattern} ]] || [[ "${host}" =~ ${regex_pattern} ]]; then
            echo "${protocol}|${device}|${tags}"
            return 0
        fi
    done < "${rules_file}"
    
    return 1
}

# Get classification statistics
get_classification_count() {
    if [[ -f "${CLASSIFIER_STATE_DIR}/flows.log" ]]; then
        wc -l < "${CLASSIFIER_STATE_DIR}/flows.log"
    else
        echo "0"
    fi
}

# List classification rules
list_classification_rules() {
    local rules_file="${CLASSIFIER_RULES_DIR}/default.rules"
    
    if [[ ! -f "${rules_file}" ]]; then
        log_warn "No classification rules found"
        return 1
    fi
    
    echo "Available Classification Rules:"
    grep -v '^#' "${rules_file}" | grep -v '^$' | while IFS='|' read -r pattern protocol device tags; do
        echo "  - Pattern: ${pattern} → Device: ${device} (${protocol})"
    done
}

# Apply specific classification rule manually
apply_classification_rule() {
    local rule_name="$1"
    log_info "Applying rule: ${rule_name}"
    
    # Implementation would trigger re-classification with specific rule
    classify_active_flows
    
    return 0
}

# Export classification data
export_classifications() {
    local format="${1:-json}"
    local output_file="${EVIDENCE_DIR}/classifications_$(date +%Y%m%d_%H%M%S).${format}"
    
    case "${format}" in
        json)
            echo "[" > "${output_file}"
            local first=true
            while IFS='|' read -r timestamp remote_addr classification; do
                [[ "${first}" == "true" ]] && first=false || echo "," >> "${output_file}"
                cat >> "${output_file}" << EOF
  {
    "timestamp": "${timestamp}",
    "remote_addr": "${remote_addr}",
    "classification": "${classification}"
  }
EOF
            done < "${CLASSIFIER_STATE_DIR}/flows.log"
            echo "]" >> "${output_file}"
            ;;
        csv)
            echo "timestamp,remote_addr,classification" > "${output_file}"
            cat "${CLASSIFIER_STATE_DIR}/flows.log" | tr '|' ',' >> "${output_file}"
            ;;
    esac
    
    log_success "Classifications exported: ${output_file}"
}
