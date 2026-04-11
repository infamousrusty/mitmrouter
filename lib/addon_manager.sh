#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - MITMProxy Addon Manager
# Dynamic loading of Python addons for analysis and traffic inspection
################################################################################

readonly ADDON_DIR="${STATE_DIR}/addons"
readonly ADDON_CACHE_DIR="${ADDON_DIR}/cache"
# ADDON_LOG is consumed by external log-shipping; export so sub-processes see it
export ADDON_LOG="${LOG_DIR}/addons.log"

# Initialize addon manager
initialize_addon_manager() {
    log_info "Initializing addon manager..."
    mkdir -p "${ADDON_DIR}" "${ADDON_CACHE_DIR}"
    chmod 750 "${ADDON_DIR}"
    install_default_addons
    log_success "Addon manager initialized"
    return 0
}

# Install default MITMProxy addons
install_default_addons() {
    cat > "${ADDON_DIR}/header_injector.py" << 'PYTHON_EOF'
"""
MITMRouter - HTTP Header Injection Addon
Injects custom headers into HTTP requests and responses
"""
from mitmproxy import http
import logging

class HeaderInjector:
    def __init__(self):
        self.inject_headers = {
            "X-MITMRouter-Version": "2.1.0",
            "X-Classification": "monitored"
        }
        logging.info("Header Injector addon loaded")

    def request(self, flow: http.HTTPFlow) -> None:
        for key, value in self.inject_headers.items():
            flow.request.headers[key] = value

    def response(self, flow: http.HTTPFlow) -> None:
        flow.response.headers["X-MITMRouter-Processed"] = "true"

addons = [HeaderInjector()]
PYTHON_EOF

    cat > "${ADDON_DIR}/request_logger.py" << 'PYTHON_EOF'
"""
MITMRouter - Request Logging Addon
Logs all HTTP/HTTPS requests for forensic analysis
"""
from mitmproxy import http
import json
import logging
from datetime import datetime

class RequestLogger:
    def __init__(self):
        self.log_file = "/var/lib/mitmrouter/evidence/requests.jsonl"
        logging.info(f"Request Logger addon loaded (output: {self.log_file})")

    def request(self, flow: http.HTTPFlow) -> None:
        request_data = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "host": flow.request.host,
            "port": flow.request.port,
            "path": flow.request.path,
            "headers": dict(flow.request.headers),
            "content_length": len(flow.request.content) if flow.request.content else 0
        }
        try:
            with open(self.log_file, "a") as f:
                f.write(json.dumps(request_data) + "\n")
        except Exception as e:
            logging.error(f"Failed to log request: {e}")

addons = [RequestLogger()]
PYTHON_EOF

    cat > "${ADDON_DIR}/payload_injector.py" << 'PYTHON_EOF'
"""
MITMRouter - Payload Injection Addon
Injects custom payloads into HTTP responses (for testing purposes)
"""
from mitmproxy import http
import logging

class PayloadInjector:
    def __init__(self):
        self.injection_enabled = True
        self.payload = "<!-- MITMRouter Monitoring Active -->"
        logging.info("Payload Injector addon loaded")

    def response(self, flow: http.HTTPFlow) -> None:
        if not self.injection_enabled:
            return
        if flow.response and flow.response.headers.get("content-type", "").startswith("text/html"):
            content = flow.response.text
            if content and "</body>" in content:
                flow.response.text = content.replace("</body>", f"{self.payload}</body>")
                logging.info(f"Payload injected into {flow.request.pretty_url}")

addons = [PayloadInjector()]
PYTHON_EOF

    cat > "${ADDON_DIR}/tls_inspector.py" << 'PYTHON_EOF'
"""
MITMRouter - TLS Inspector Addon
Logs SSL/TLS certificate details and cipher suites
"""
from mitmproxy import tls
import json
import logging
from datetime import datetime

class TLSInspector:
    def __init__(self):
        self.log_file = "/var/lib/mitmrouter/evidence/tls_connections.jsonl"
        logging.info(f"TLS Inspector addon loaded (output: {self.log_file})")

    def tls_established_client(self, data: tls.TlsData):
        tls_data = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "sni": data.context.client.sni if hasattr(data.context.client, 'sni') else None,
            "cipher": data.context.client.cipher if hasattr(data.context.client, 'cipher') else None,
            "tls_version": data.context.client.tls_version if hasattr(data.context.client, 'tls_version') else None
        }
        try:
            with open(self.log_file, "a") as f:
                f.write(json.dumps(tls_data) + "\n")
        except Exception as e:
            logging.error(f"Failed to log TLS connection: {e}")

addons = [TLSInspector()]
PYTHON_EOF

    chmod 644 "${ADDON_DIR}"/*.py
    log_success "Default addons installed in ${ADDON_DIR}"
}

# Load addons into MITMProxy
load_addons() {
    local addon_list="$1"
    log_info "Loading addons: ${addon_list}"

    # SC2206 fix: use read -ra for robust word splitting
    local addons_array
    IFS=',' read -ra addons_array <<< "${addon_list}"

    for addon_name in "${addons_array[@]}"; do
        local addon_file="${ADDON_DIR}/${addon_name}.py"
        if [[ ! -f "${addon_file}" ]]; then
            log_warn "Addon not found: ${addon_name}"
            continue
        fi
        log_success "Addon registered: ${addon_name}"
    done
    return 0
}

# List loaded addons
list_loaded_addons() {
    if [[ -z "${mitmproxy_addons:-}" ]]; then
        echo "none"
        return 0
    fi
    echo "${mitmproxy_addons}"
}

# Get addon configuration for MITMProxy startup
get_addon_args() {
    local addon_list="${mitmproxy_addons:-}"
    if [[ -z "${addon_list}" ]]; then
        echo ""
        return 0
    fi

    local addon_args=""
    local addons_array
    # SC2206 fix: use read -ra
    IFS=',' read -ra addons_array <<< "${addon_list}"

    for addon_name in "${addons_array[@]}"; do
        local addon_file="${ADDON_DIR}/${addon_name}.py"
        if [[ -f "${addon_file}" ]]; then
            addon_args="${addon_args} -s ${addon_file}"
        fi
    done
    echo "${addon_args}"
}

# Validate addon Python syntax
validate_addon() {
    local addon_file="$1"
    if [[ ! -f "${addon_file}" ]]; then
        log_error "Addon file not found: ${addon_file}"
        return 1
    fi
    python3 -m py_compile "${addon_file}" 2>/dev/null || {
        log_error "Addon has syntax errors: ${addon_file}"
        return 1
    }
    log_success "Addon validation passed: ${addon_file}"
    return 0
}

# Create custom addon from template
create_addon() {
    local addon_name="$1"
    local addon_file="${ADDON_DIR}/${addon_name}.py"
    if [[ -f "${addon_file}" ]]; then
        log_warn "Addon already exists: ${addon_name}"
        return 1
    fi

    cat > "${addon_file}" << 'PYTHON_EOF'
"""
MITMRouter - Custom Addon Template
Modify this template to create custom traffic analysis logic
"""
from mitmproxy import http
import logging

class CustomAddon:
    def __init__(self):
        logging.info("Custom addon loaded")

    def request(self, flow: http.HTTPFlow) -> None:
        pass

    def response(self, flow: http.HTTPFlow) -> None:
        pass

addons = [CustomAddon()]
PYTHON_EOF

    chmod 644 "${addon_file}"
    log_success "Custom addon created: ${addon_file}"
    log_info "Edit ${addon_file} to customise behaviour"
}
