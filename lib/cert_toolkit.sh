#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Certificate Pinning Toolkit
# Automated certificate generation, deployment, and pinning bypass helpers
################################################################################

readonly CERT_DIR="${CONFIG_DIR}/certs"
readonly CA_CERT="${CERT_DIR}/mitmrouter-ca.pem"
readonly CA_KEY="${CERT_DIR}/mitmrouter-ca-key.pem"
readonly MOBILE_CERT_DIR="${CERT_DIR}/mobile"

# Initialize certificate toolkit
initialize_cert_toolkit() {
    log_info "Initializing certificate toolkit..."
    
    mkdir -p "${CERT_DIR}" "${MOBILE_CERT_DIR}"
    chmod 700 "${CERT_DIR}"
    
    # Check if CA exists
    if [[ ! -f "${CA_CERT}" ]]; then
        generate_root_ca || return 1
    fi
    
    log_success "Certificate toolkit initialized"
    return 0
}

# Generate root CA certificate
generate_root_ca() {
    log_info "Generating root CA certificate..."
    
    if ! command -v openssl &>/dev/null; then
        log_error "openssl not found - install with: apt-get install openssl"
        return 1
    fi
    
    # Generate CA private key
    openssl genrsa -out "${CA_KEY}" 4096 2>/dev/null || return 1
    chmod 600 "${CA_KEY}"
    
    # Generate CA certificate
    openssl req -new -x509 -days 3650 -key "${CA_KEY}" -out "${CA_CERT}" \
        -subj "/C=US/ST=Security/L=Lab/O=MITMRouter/OU=Research/CN=MITMRouter Root CA v2.1" \
        2>/dev/null || return 1
    
    chmod 644 "${CA_CERT}"
    
    log_success "Root CA generated: ${CA_CERT}"
    log_info "Install this CA on target devices to enable HTTPS interception"
    
    return 0
}

# Deploy certificate for pinning bypass
deploy_pinning_certs() {
    log_info "Deploying certificates for pinning bypass..."
    
    # Ensure MITMProxy CA is available
    local mitmproxy_ca="${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"
    
    if [[ -f "${mitmproxy_ca}" ]]; then
        cp "${mitmproxy_ca}" "${CERT_DIR}/mitmproxy-ca.pem"
        log_success "MITMProxy CA copied to: ${CERT_DIR}/mitmproxy-ca.pem"
    else
        log_warn "MITMProxy CA not found - will be generated on first run"
    fi
    
    # Generate mobile-friendly formats
    generate_mobile_certs
    
    return 0
}

# Generate mobile-friendly certificate formats
generate_mobile_certs() {
    log_info "Generating mobile certificate formats..."
    
    local source_cert="${CA_CERT}"
    
    # iOS format (.mobileconfig)
    generate_ios_profile "${source_cert}"
    
    # Android format (DER)
    if [[ -f "${source_cert}" ]]; then
        openssl x509 -in "${source_cert}" -outform DER -out "${MOBILE_CERT_DIR}/mitmrouter-ca.der" 2>/dev/null
        log_success "Android DER certificate: ${MOBILE_CERT_DIR}/mitmrouter-ca.der"
    fi
    
    # Generate QR code for easy mobile installation (if qrencode available)
    if command -v qrencode &>/dev/null; then
        local cert_url="http://$(hostname -I | awk '{print $1}'):8000/certs/mitmrouter-ca.pem"
        qrencode -t PNG -o "${MOBILE_CERT_DIR}/install_qr.png" "${cert_url}" 2>/dev/null && \
            log_success "QR code generated: ${MOBILE_CERT_DIR}/install_qr.png"
    fi
    
    return 0
}

# Generate iOS configuration profile
generate_ios_profile() {
    local cert_file="$1"
    local profile_file="${MOBILE_CERT_DIR}/mitmrouter-ca.mobileconfig"
    
    # Read certificate and encode as base64
    local cert_base64=$(base64 -w0 "${cert_file}" 2>/dev/null || base64 "${cert_file}")
    local profile_uuid=$(uuidgen 2>/dev/null || echo "MITMROUTER-$(date +%s)")
    
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

# Start simple HTTP server for certificate distribution
start_cert_server() {
    local port="${1:-8000}"
    
    log_info "Starting certificate distribution server on port ${port}..."
    
    # Check if server already running
    if pgrep -f "python.*SimpleHTTPServer.*${port}" >/dev/null || \
       pgrep -f "python.*http.server.*${port}" >/dev/null; then
        log_warn "Certificate server already running on port ${port}"
        return 0
    fi
    
    # Start HTTP server in background
    cd "${CERT_DIR}" || return 1
    
    if python3 -m http.server "${port}" &>/dev/null & then
        local server_pid=$!
        echo "${server_pid}" > "${STATE_DIR}/cert_server.pid"
        
        local ip_addr=$(hostname -I | awk '{print $1}')
        log_success "Certificate server started (PID: ${server_pid})"
        log_info "Access certificates at: http://${ip_addr}:${port}/"
        log_info "iOS profile: http://${ip_addr}:${port}/mobile/mitmrouter-ca.mobileconfig"
        log_info "Android DER: http://${ip_addr}:${port}/mobile/mitmrouter-ca.der"
        
        return 0
    else
        log_error "Failed to start certificate server"
        return 1
    fi
}

# Stop certificate server
stop_cert_server() {
    if [[ -f "${STATE_DIR}/cert_server.pid" ]]; then
        local server_pid=$(cat "${STATE_DIR}/cert_server.pid")
        kill "${server_pid}" 2>/dev/null && log_success "Certificate server stopped"
        rm -f "${STATE_DIR}/cert_server.pid"
    fi
}

# Generate pinning bypass instructions
generate_pinning_instructions() {
    local instructions_file="${CERT_DIR}/PINNING_BYPASS_GUIDE.txt"
    
    cat > "${instructions_file}" << 'INSTRUCTIONS_EOF'
MITMRouter v2.1.0 - SSL/TLS Pinning Bypass Guide
================================================

OVERVIEW
--------
SSL/TLS certificate pinning prevents man-in-the-middle attacks by validating
server certificates against a hardcoded set. To analyze pinned apps, you need
to bypass this validation.

PREREQUISITES
-------------
1. Root/jailbroken device (iOS or Android)
2. MITMRouter CA certificate installed
3. Frida or Objection framework (for runtime patching)

iOS PINNING BYPASS
------------------
Method 1: Using Objection
1. Install Objection: pip3 install objection
2. Start app with patching: objection --gadget com.example.app explore
3. Disable pinning: ios sslpinning disable

Method 2: Using SSL Kill Switch 2
1. Install SSL Kill Switch 2 from Cydia
2. Enable for target application
3. Restart application

Method 3: Manual Certificate Installation
1. Download profile: http://<mitmrouter-ip>:8000/mobile/mitmrouter-ca.mobileconfig
2. Install: Settings → Profile Downloaded → Install
3. Trust: Settings → General → About → Certificate Trust Settings
4. Enable full trust for MITMRouter CA

ANDROID PINNING BYPASS
----------------------
Method 1: Using Frida
1. Install Frida: pip3 install frida-tools
2. Run universal bypass script:
   frida -U -f com.example.app -l android-ssl-pinning-bypass.js

Method 2: Using Magisk + TrustMeAlready
1. Install Magisk on rooted device
2. Install TrustMeAlready module
3. Reboot device

Method 3: Manual Certificate Installation
1. Download certificate: http://<mitmrouter-ip>:8000/mobile/mitmrouter-ca.der
2. Settings → Security → Install from storage
3. For Android 7+: Move cert to system store (requires root)
   adb push mitmrouter-ca.der /sdcard/
   su
   cp /sdcard/mitmrouter-ca.der /system/etc/security/cacerts/

VERIFICATION
------------
1. Configure device proxy: <mitmrouter-ip>:8080
2. Browse to http://mitm.it (MITMProxy cert page)
3. Verify HTTPS traffic appears in MITMProxy web UI
4. Check for SSL errors in application logs

TROUBLESHOOTING
---------------
- "Certificate not trusted" → Ensure CA is installed and trusted
- "No traffic visible" → Check proxy settings, verify app uses HTTP/HTTPS
- "SSL error despite bypass" → App may use multiple pinning techniques
- "App crashes" → Try different bypass method or Frida script

AUTOMATED BYPASS SCRIPTS
------------------------
MITMRouter includes Frida scripts in: /opt/mitmrouter/scripts/pinning/
- android_universal_bypass.js
- ios_universal_bypass.js

Usage: frida -U -f <package> -l <script.js>

SECURITY NOTE
-------------
These techniques are for authorized security testing only. Bypassing certificate
pinning on applications you don't own may violate terms of service and laws.

INSTRUCTIONS_EOF
    
    log_success "Pinning bypass instructions: ${instructions_file}"
    cat "${instructions_file}"
}

# Check if device has MITMRouter CA installed (heuristic based on connections)
check_ca_installation() {
    log_info "Checking for CA installation on connected devices..."
    
    # Check if any HTTPS connections are being intercepted successfully
    if [[ -f "${EVIDENCE_DIR}/tls_connections.jsonl" ]]; then
        local tls_count=$(wc -l < "${EVIDENCE_DIR}/tls_connections.jsonl")
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
