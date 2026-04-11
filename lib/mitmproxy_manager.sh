#!/bin/bash
################################################################################
# MITMRouter MITMProxy Integration & Management
# Automated installation, version management, certificate handling
################################################################################

readonly MITMPROXY_PID_FILE="/var/run/mitmrouter/mitmproxy.pid"
readonly MITMPROXY_LOG_FILE="/var/log/mitmrouter/mitmproxy.log"

is_mitmproxy_installed() {
    command -v mitmproxy &>/dev/null
}

get_mitmproxy_version() {
    if is_mitmproxy_installed; then
        mitmproxy --version 2>/dev/null | head -n1
    else
        echo "not_installed"
    fi
}

install_mitmproxy() {
    local version="${1:-10.4.2}"
    log_info "Installing MITMProxy version ${version}..."

    local current_version
    current_version=$(get_mitmproxy_version)
    if [[ "${current_version}" == "not_installed" ]]; then
        log_info "MITMProxy not installed, proceeding with installation"
    else
        log_info "Current MITMProxy version: ${current_version}"
    fi

    if ! command -v pipx &>/dev/null; then
        log_info "Installing pipx..."
        if command -v apt &>/dev/null; then
            apt-get update && apt-get install -y pipx python3-venv
        elif command -v dnf &>/dev/null; then
            dnf install -y pipx
        elif command -v pacman &>/dev/null; then
            pacman -S --noconfirm python-pipx
        else
            log_error "Cannot determine package manager for pipx installation"
            return 1
        fi
    fi

    log_info "Installing mitmproxy==${version} via pipx..."
    pipx install "mitmproxy==${version}" --force || {
        log_error "Failed to install MITMProxy"
        return 1
    }

    if is_mitmproxy_installed; then
        log_success "MITMProxy installed successfully: $(get_mitmproxy_version)"
        return 0
    else
        log_error "MITMProxy installation verification failed"
        return 1
    fi
}

setup_mitmproxy_ca() {
    log_info "Setting up MITMProxy CA certificate..."
    if is_mitmproxy_installed; then
        mitmproxy --version >/dev/null 2>&1 || true
    fi
    local ca_cert_src="${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"
    local cert_dir="${mitmproxy_cert_dir:-/etc/mitmrouter/certs}"
    mkdir -p "${cert_dir}"
    if [[ -f "${ca_cert_src}" ]]; then
        cp "${ca_cert_src}" "${cert_dir}/mitmproxy-ca-cert.pem"
        chmod 644 "${cert_dir}/mitmproxy-ca-cert.pem"
        log_success "CA certificate available at: ${cert_dir}/mitmproxy-ca-cert.pem"
    else
        log_warn "CA certificate not found at ${ca_cert_src}"
    fi
    return 0
}

generate_ssl_cert() {
    local domain="$1"
    local cert_dir="${mitmproxy_cert_dir:-/etc/mitmrouter/certs}"
    mkdir -p "${cert_dir}"
    if [[ -f "${cert_dir}/${domain}.crt" ]]; then
        log_info "Certificate already exists for ${domain}"
        return 0
    fi
    log_info "Generating certificate for ${domain}..."
    if is_mitmproxy_installed; then
        openssl req -new -x509 -days "${mitmproxy_cert_expiry_days:-90}" \
            -keyout "${cert_dir}/${domain}.key" \
            -out    "${cert_dir}/${domain}.crt" \
            -subj "/CN=${domain}" || return 1
        log_success "Certificate generated for ${domain}"
    else
        log_error "MITMProxy not installed, cannot generate certificate"
        return 1
    fi
    return 0
}

start_mitmproxy() {
    log_info "Starting MITMProxy..."
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then
        log_warn "MITMProxy is already running"
        return 0
    fi
    if ! is_mitmproxy_installed; then
        install_mitmproxy "${mitmproxy_version:-10.4.2}" || return 1
    fi
    setup_mitmproxy_ca || return 1
    mkdir -p "$(dirname "${MITMPROXY_PID_FILE}")"
    mkdir -p "$(dirname "${MITMPROXY_LOG_FILE}")"

    local listen_host="${mitmproxy_listen_host:-127.0.0.1}"
    local listen_port="${mitmproxy_listen_port:-8080}"
    local web_port="${mitmproxy_web_port:-8081}"

    local mitmproxy_cmd="mitmproxy"
    mitmproxy_cmd+=" --listen-host ${listen_host}"
    mitmproxy_cmd+=" --listen-port ${listen_port}"
    mitmproxy_cmd+=" --mode ${mitmproxy_mode:-transparent}"
    mitmproxy_cmd+=" --web-port ${web_port}"
    mitmproxy_cmd+=" --log-level ${mitmproxy_log_level:-info}"
    if [[ -n "${mitmproxy_cert_dir:-}" ]]; then
        mitmproxy_cmd+=" --certs ${mitmproxy_cert_dir}"
    fi

    log_debug "Starting: ${mitmproxy_cmd}"
    # shellcheck disable=SC2086
    nohup ${mitmproxy_cmd} > "${MITMPROXY_LOG_FILE}" 2>&1 &
    local mitmproxy_pid=$!
    echo "${mitmproxy_pid}" > "${MITMPROXY_PID_FILE}"

    sleep 2
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then
        log_success "MITMProxy started (PID: ${mitmproxy_pid})"
        log_info "Web interface: http://localhost:${web_port}"
        return 0
    else
        log_error "MITMProxy failed to start"
        log_error "See logs: ${MITMPROXY_LOG_FILE}"
        return 1
    fi
}

stop_mitmproxy() {
    log_info "Stopping MITMProxy..."
    if [[ -f "${MITMPROXY_PID_FILE}" ]]; then
        local mitmproxy_pid
        mitmproxy_pid=$(cat "${MITMPROXY_PID_FILE}")
        if kill "${mitmproxy_pid}" 2>/dev/null; then
            log_success "MITMProxy stopped (PID: ${mitmproxy_pid})"
            rm -f "${MITMPROXY_PID_FILE}"
            return 0
        fi
    fi
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then
        pkill -f "mitmproxy" || true
        log_success "MITMProxy stopped"
    fi
    return 0
}

check_mitmproxy_status() {
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then
        echo "RUNNING"; return 0
    else
        echo "STOPPED"; return 1
    fi
}

get_mitmproxy_logs() {
    if [[ -f "${MITMPROXY_LOG_FILE}" ]]; then
        tail -f "${MITMPROXY_LOG_FILE}"
    else
        log_warn "No MITMProxy logs found"
        return 1
    fi
}

healthcheck_mitmproxy() {
    if ! is_mitmproxy_installed; then
        echo "FAIL: MITMProxy not installed"; return 1
    fi
    if ! pgrep -f "mitmproxy" >/dev/null 2>&1; then
        echo "FAIL: MITMProxy not running"; return 1
    fi
    local web_port="${mitmproxy_web_port:-8081}"
    if timeout 2 bash -c "echo >/dev/tcp/localhost/${web_port}" 2>/dev/null; then
        echo "PASS: MITMProxy healthy"; return 0
    else
        echo "FAIL: MITMProxy web interface not responding"; return 1
    fi
}
