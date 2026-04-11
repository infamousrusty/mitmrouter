#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Certificate Pinning Toolkit
# Automated certificate generation, deployment, and pinning bypass helpers
################################################################################

readonly CERT_DIR="${CONFIG_DIR}/certs"
readonly CA_CERT="${CERT_DIR}/mitmrouter-ca.pem"
readonly CA_KEY="${CERT_DIR}/mitmrouter-ca-key.pem"
readonly MOBILE_CERT_DIR="${CERT_DIR}/mobile"

initialize_cert_toolkit() {
    log_info "Initializing certificate toolkit..."
    mkdir -p "${CERT_DIR}" "${MOBILE_CERT_DIR}"
    chmod 700 "${CERT_DIR}"
    if [[ ! -f "${CA_CERT}" ]]; then
        generate_root_ca || return 1
    fi
    log_success "Certificate toolkit initialized"
    return 0
}

generate_root_ca() {
    log_info "Generating root CA certificate..."
    if ! command -v openssl &>/dev/null; then
        log_error "openssl not found - install with: apt-get install openssl"
        return 1
    fi
    openssl genrsa -out "${CA_KEY}" 4096 2>/dev/null || return 1
    chmod 600 "${CA_KEY}"
    openssl req -new -x509 -days 3650 -key "${CA_KEY}" -out "${CA_CERT}" \
        -subj "/C=US/ST=Security/L=Lab/O=MITMRouter/OU=Research/CN=MITMRouter Root CA v2.1" \
        2>/dev/null || return 1
    chmod 644 "${CA_CERT}"
    log_success "Root CA generated: ${CA_CERT}"
    log_info "Install this CA on target devices to enable HTTPS interception"
    return 0
}

deploy_pinning_certs() {
    log_info "Deploying certificates for pinning bypass..."
    local mitmproxy_ca="${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"
    if [[ -f "${mitmproxy_ca}" ]]; then
        cp "${mitmproxy_ca}" "${CERT_DIR}/mitmproxy-ca.pem"
        log_success "MITMProxy CA copied to: ${CERT_DIR}/mitmproxy-ca.pem"
    else
        log_warn "MITMProxy CA not found - will be generated on first run"
    fi
    generate_mobile_certs
    return 0
}

generate_mobile_certs() {
    log_info "Generating mobile certificate formats..."
    local source_cert="${CA_CERT}"
    generate_ios_profile "${source_cert}"
    if [[ -f "${source_cert}" ]]; then
        openssl x509 -in "${source_cert}" -outform DER \
            -out "${MOBILE_CERT_DIR}/mitmrouter-ca.der" 2>/dev/null
        log_success "Android DER certificate: ${MOBILE_CERT_DIR}/mitmrouter-ca.der"
    fi
    if command -v qrencode &>/dev/null; then
        local cert_url="http://$(hostname -I | awk '{print $1}'):8000/certs/mitmrouter-ca.pem"
        qrencode -t PNG -o "${MOBILE_CERT_DIR}/install_qr.png" "${cert_url}" 2>/dev/null && \
            log_success "QR code generated: ${MOBILE_CERT_DIR}/install_qr.png"
    fi
    return 0
}

generate_ios_profile() {
    local cert_file="$1"
    local profile_file="${MOBILE_CERT_DIR}/mitmrouter-ca.mobileconfig"

    local cert_base64
    cert_base64=$(base64 -w0 "${cert_file}" 2>/dev/null || base64 "${cert_file}")
    local profile_uuid
    profile_uuid=$(uuidgen 2>/dev/null || echo "MITMROUTER-$(date +%s)")

    cat > "${profile_file}" << PROFILE_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadCertificateFileName</key>
            <string>mitmrouter-ca.pem</string>
            <key>PayloadContent</key>
            <data>${cert_base64}</data>
            <key>PayloadDescription</key>
            <string>MITMRouter Root CA Certificate</string>
            <key>PayloadDisplayName</key>
            <string>MITMRouter CA</string>
            <key>PayloadIdentifier</key>
            <string>com.mitmrouter.ca.${profile_uuid}</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>${profile_uuid}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>Install MITMRouter CA for HTTPS interception</string>
    <key>PayloadDisplayName</key>
    <string>MITMRouter Root CA</string>
    <key>PayloadIdentifier</key>
    <string>com.mitmrouter.profile.${profile_uuid}</string>
    <key>PayloadOrganization</key>
    <string>MITMRouter</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${profile_uuid}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
PROFILE_EOF

    chmod 644 "${profile_file}"
    log_success "iOS profile generated: ${profile_file}"
}

start_cert_server() {
    local port="${1:-8000}"
    log_info "Starting certificate distribution server on port ${port}..."
    if pgrep -f "python.*SimpleHTTPServer.*${port}" >/dev/null 2>&1 || \
       pgrep -f "python.*http.server.*${port}"      >/dev/null 2>&1; then
        log_warn "Certificate server already running on port ${port}"
        return 0
    fi
    cd "${CERT_DIR}" || return 1
    if python3 -m http.server "${port}" &>/dev/null &; then
        local server_pid=$!
        echo "${server_pid}" > "${STATE_DIR}/cert_server.pid"
        local ip_addr
        ip_addr=$(hostname -I | awk '{print $1}')
        log_success "Certificate server started (PID: ${server_pid})"
        log_info "Access certificates at: http://${ip_addr}:${port}/"
        log_info "iOS profile:  http://${ip_addr}:${port}/mobile/mitmrouter-ca.mobileconfig"
        log_info "Android DER:  http://${ip_addr}:${port}/mobile/mitmrouter-ca.der"
        return 0
    else
        log_error "Failed to start certificate server"
        return 1
    fi
}

stop_cert_server() {
    if [[ -f "${STATE_DIR}/cert_server.pid" ]]; then
        local server_pid
        server_pid=$(cat "${STATE_DIR}/cert_server.pid")
        kill "${server_pid}" 2>/dev/null && log_success "Certificate server stopped"
        rm -f "${STATE_DIR}/cert_server.pid"
    fi
}

generate_pinning_instructions() {
    local instructions_file="${CERT_DIR}/PINNING_BYPASS_GUIDE.txt"
    cat > "${instructions_file}" << 'INSTRUCTIONS_EOF'
MITMRouter v2.1.0 - SSL/TLS Pinning Bypass Guide
================================================
(see full guide in docs/runbooks/pinning-bypass.md)
INSTRUCTIONS_EOF
    log_success "Pinning bypass instructions: ${instructions_file}"
    cat "${instructions_file}"
}

check_ca_installation() {
    log_info "Checking for CA installation on connected devices..."
    if [[ -f "${EVIDENCE_DIR}/tls_connections.jsonl" ]]; then
        local tls_count
        tls_count=$(wc -l < "${EVIDENCE_DIR}/tls_connections.jsonl")
        if [[ ${tls_count} -gt 0 ]]; then
            log_success "✓ TLS interception active (${tls_count} connections)"
            log_info "CA appears to be installed on at least one device"
            return 0
        fi
    fi
    log_warn "No TLS connections intercepted yet"
    log_info "Devices may not have CA installed or are not using HTTPS"
    return 1
}
