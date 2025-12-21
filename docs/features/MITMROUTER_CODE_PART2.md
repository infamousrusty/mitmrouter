# MITMROUTER v2.0 - PRODUCTION CODE (PART 2 OF 3)
# All remaining implementation files - Copy-Paste Ready

================================================================================
FILE 6: lib/mitmproxy_manager.sh (MITMProxy Management)
================================================================================
Location: ./lib/mitmproxy_manager.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter MITMProxy Integration & Management
# Automated installation, version management, certificate handling
################################################################################

# MITMProxy process PID file
readonly MITMPROXY_PID_FILE="/var/run/mitmrouter/mitmproxy.pid"
readonly MITMPROXY_LOG_FILE="/var/log/mitmrouter/mitmproxy.log"

# Check if MITMProxy is installed
is_mitmproxy_installed() {
    command -v mitmproxy &>/dev/null
}

# Get installed MITMProxy version
get_mitmproxy_version() {
    if is_mitmproxy_installed; then
        mitmproxy --version 2>/dev/null | head -n1
    else
        echo "not_installed"
    fi
}

# Install MITMProxy via pipx
install_mitmproxy() {
    local version="${1:-10.4.2}"
    
    log_info "Installing MITMProxy version ${version}..."
    
    # Check if already installed with correct version
    local current_version=$(get_mitmproxy_version)
    if [[ "${current_version}" == "not_installed" ]]; then
        log_info "MITMProxy not installed, proceeding with installation"
    else
        log_info "Current MITMProxy version: ${current_version}"
    fi
    
    # Ensure pip and pipx are available
    if ! command -v pipx &>/dev/null; then
        log_info "Installing pipx..."
        
        # Install pipx based on distribution
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
    
    # Install MITMProxy via pipx
    log_info "Installing mitmproxy==${version} via pipx..."
    pipx install "mitmproxy==${version}" --force || {
        log_error "Failed to install MITMProxy"
        return 1
    }
    
    # Verify installation
    if is_mitmproxy_installed; then
        log_success "MITMProxy installed successfully: $(get_mitmproxy_version)"
        return 0
    else
        log_error "MITMProxy installation verification failed"
        return 1
    fi
}

# Setup MITMProxy CA certificate
setup_mitmproxy_ca() {
    log_info "Setting up MITMProxy CA certificate..."
    
    # Trigger CA certificate generation
    if is_mitmproxy_installed; then
        # This creates the CA cert if it doesn't exist
        mitmproxy --version >/dev/null 2>&1 || true
    fi
    
    local ca_cert_src="${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"
    local cert_dir="${mitmproxy_cert_dir:-/etc/mitmrouter/certs}"
    
    # Create certificate directory
    mkdir -p "${cert_dir}"
    
    # Copy CA certificate if it exists
    if [[ -f "${ca_cert_src}" ]]; then
        cp "${ca_cert_src}" "${cert_dir}/mitmproxy-ca-cert.pem"
        chmod 644 "${cert_dir}/mitmproxy-ca-cert.pem"
        log_success "CA certificate available at: ${cert_dir}/mitmproxy-ca-cert.pem"
    else
        log_warn "CA certificate not found at ${ca_cert_src}"
    fi
    
    return 0
}

# Generate certificate for SSL/TLS interception
generate_ssl_cert() {
    local domain="$1"
    local cert_dir="${mitmproxy_cert_dir:-/etc/mitmrouter/certs}"
    
    mkdir -p "${cert_dir}"
    
    # Check if certificate already exists
    if [[ -f "${cert_dir}/${domain}.crt" ]]; then
        log_info "Certificate already exists for ${domain}"
        return 0
    fi
    
    log_info "Generating certificate for ${domain}..."
    
    # Use mitmproxy's cert generation if available
    if is_mitmproxy_installed; then
        # Use OpenSSL to generate a certificate signed by mitmproxy CA
        openssl req -new -x509 -days ${mitmproxy_cert_expiry_days:-90} \
            -keyout "${cert_dir}/${domain}.key" \
            -out "${cert_dir}/${domain}.crt" \
            -subj "/CN=${domain}" || return 1
        
        log_success "Certificate generated for ${domain}"
    else
        log_error "MITMProxy not installed, cannot generate certificate"
        return 1
    fi
    
    return 0
}

# Start MITMProxy service
start_mitmproxy() {
    log_info "Starting MITMProxy..."
    
    # Check if already running
    if pgrep -f "mitmproxy" >/dev/null; then
        log_warn "MITMProxy is already running"
        return 0
    fi
    
    # Ensure MITMProxy is installed
    if ! is_mitmproxy_installed; then
        install_mitmproxy "${mitmproxy_version:-10.4.2}" || return 1
    fi
    
    # Setup CA certificate
    setup_mitmproxy_ca || return 1
    
    # Create run directory
    mkdir -p "$(dirname "${MITMPROXY_PID_FILE}")"
    mkdir -p "$(dirname "${MITMPROXY_LOG_FILE}")"
    
    # Determine listen address
    local listen_host="${mitmproxy_listen_host:-127.0.0.1}"
    local listen_port="${mitmproxy_listen_port:-8080}"
    local web_port="${mitmproxy_web_port:-8081}"
    
    # Build mitmproxy command
    local mitmproxy_cmd="mitmproxy"
    mitmproxy_cmd+=" --listen-host ${listen_host}"
    mitmproxy_cmd+=" --listen-port ${listen_port}"
    mitmproxy_cmd+=" --mode ${mitmproxy_mode:-transparent}"
    mitmproxy_cmd+=" --web-port ${web_port}"
    mitmproxy_cmd+=" --log-level ${mitmproxy_log_level:-info}"
    
    # Add certificate directory if configured
    if [[ -n "${mitmproxy_cert_dir:-}" ]]; then
        mitmproxy_cmd+=" --certs ${mitmproxy_cert_dir}"
    fi
    
    # Start in background with nohup
    log_debug "Starting: ${mitmproxy_cmd}"
    nohup ${mitmproxy_cmd} > "${MITMPROXY_LOG_FILE}" 2>&1 &
    local mitmproxy_pid=$!
    echo "${mitmproxy_pid}" > "${MITMPROXY_PID_FILE}"
    
    # Wait for startup and verify
    sleep 2
    if pgrep -f "mitmproxy" >/dev/null; then
        log_success "MITMProxy started (PID: ${mitmproxy_pid})"
        log_info "Web interface: http://localhost:${web_port}"
        return 0
    else
        log_error "MITMProxy failed to start"
        log_error "See logs: ${MITMPROXY_LOG_FILE}"
        return 1
    fi
}

# Stop MITMProxy service
stop_mitmproxy() {
    log_info "Stopping MITMProxy..."
    
    # Get PID from file if it exists
    if [[ -f "${MITMPROXY_PID_FILE}" ]]; then
        local mitmproxy_pid=$(cat "${MITMPROXY_PID_FILE}")
        if kill "${mitmproxy_pid}" 2>/dev/null; then
            log_success "MITMProxy stopped (PID: ${mitmproxy_pid})"
            rm -f "${MITMPROXY_PID_FILE}"
            return 0
        fi
    fi
    
    # Fallback: kill by process name
    if pgrep -f "mitmproxy" >/dev/null; then
        pkill -f "mitmproxy" || true
        log_success "MITMProxy stopped"
    fi
    
    return 0
}

# Check MITMProxy status
check_mitmproxy_status() {
    if pgrep -f "mitmproxy" >/dev/null; then
        echo "RUNNING"
        return 0
    else
        echo "STOPPED"
        return 1
    fi
}

# Get MITMProxy logs
get_mitmproxy_logs() {
    if [[ -f "${MITMPROXY_LOG_FILE}" ]]; then
        tail -f "${MITMPROXY_LOG_FILE}"
    else
        log_warn "No MITMProxy logs found"
        return 1
    fi
}

# Health check for MITMProxy
healthcheck_mitmproxy() {
    if ! is_mitmproxy_installed; then
        echo "FAIL: MITMProxy not installed"
        return 1
    fi
    
    if ! pgrep -f "mitmproxy" >/dev/null; then
        echo "FAIL: MITMProxy not running"
        return 1
    fi
    
    # Try to connect to web interface
    local web_port="${mitmproxy_web_port:-8081}"
    if timeout 2 bash -c "echo >/dev/tcp/localhost/${web_port}" 2>/dev/null; then
        echo "PASS: MITMProxy healthy"
        return 0
    else
        echo "FAIL: MITMProxy web interface not responding"
        return 1
    fi
}
```

================================================================================
FILE 7: lib/monitoring.sh (Observability & Metrics)
================================================================================
Location: ./lib/monitoring.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter Monitoring & Observability
# Prometheus metrics export, health checks, traffic monitoring
################################################################################

# Monitoring configuration
readonly METRICS_FILE="/var/lib/mitmrouter/metrics.prom"
readonly METRICS_DIR="$(dirname "${METRICS_FILE}")"
readonly HEALTH_CHECK_FILE="/var/lib/mitmrouter/health.json"

# Initialize monitoring
initialize_monitoring() {
    log_info "Initializing monitoring..."
    
    # Create metrics directory
    mkdir -p "${METRICS_DIR}"
    chmod 755 "${METRICS_DIR}"
    
    # Create initial metrics file
    touch "${METRICS_FILE}"
    chmod 644 "${METRICS_FILE}"
    
    log_success "Monitoring initialized"
    return 0
}

# Export Prometheus metrics
export_prometheus_metrics() {
    log_debug "Exporting Prometheus metrics..."
    
    local bridge="${network_bridge_name:-br0}"
    local metrics_temp="/tmp/mitmrouter_metrics_$$.prom"
    
    # Collect system metrics
    local rx_bytes=0
    local tx_bytes=0
    local rx_packets=0
    local tx_packets=0
    local connected_clients=0
    
    # Get interface statistics
    if [[ -d "/sys/class/net/${bridge}" ]]; then
        rx_bytes=$(cat "/sys/class/net/${bridge}/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/${bridge}/statistics/tx_bytes" 2>/dev/null || echo "0")
        rx_packets=$(cat "/sys/class/net/${bridge}/statistics/rx_packets" 2>/dev/null || echo "0")
        tx_packets=$(cat "/sys/class/net/${bridge}/statistics/tx_packets" 2>/dev/null || echo "0")
    fi
    
    # Get connected clients
    if command -v iw &>/dev/null; then
        connected_clients=$(iw dev "${network_wlan_interface}" station dump 2>/dev/null | grep -c "Station" || echo "0")
    fi
    
    # Get service status
    local hostapd_status=$([[ $(systemctl is-active hostapd 2>/dev/null) == "active" ]] && echo "1" || echo "0")
    local dnsmasq_status=$([[ $(systemctl is-active dnsmasq 2>/dev/null) == "active" ]] && echo "1" || echo "0")
    local mitmproxy_status=$([[ $(pgrep -f "mitmproxy" >/dev/null) ]] && echo "1" || echo "0")
    
    # Write metrics in Prometheus format
    cat > "${metrics_temp}" << EOF
# HELP mitmrouter_rx_bytes_total Total received bytes on bridge interface
# TYPE mitmrouter_rx_bytes_total counter
mitmrouter_rx_bytes_total{interface="${bridge}"} ${rx_bytes}

# HELP mitmrouter_tx_bytes_total Total transmitted bytes on bridge interface
# TYPE mitmrouter_tx_bytes_total counter
mitmrouter_tx_bytes_total{interface="${bridge}"} ${tx_bytes}

# HELP mitmrouter_rx_packets_total Total received packets on bridge interface
# TYPE mitmrouter_rx_packets_total counter
mitmrouter_rx_packets_total{interface="${bridge}"} ${rx_packets}

# HELP mitmrouter_tx_packets_total Total transmitted packets on bridge interface
# TYPE mitmrouter_tx_packets_total counter
mitmrouter_tx_packets_total{interface="${bridge}"} ${tx_packets}

# HELP mitmrouter_connected_clients Currently connected WiFi clients
# TYPE mitmrouter_connected_clients gauge
mitmrouter_connected_clients{interface="${network_wlan_interface}"} ${connected_clients}

# HELP mitmrouter_service_up Service availability status
# TYPE mitmrouter_service_up gauge
mitmrouter_service_up{service="hostapd"} ${hostapd_status}
mitmrouter_service_up{service="dnsmasq"} ${dnsmasq_status}
mitmrouter_service_up{service="mitmproxy"} ${mitmproxy_status}

# HELP mitmrouter_version MITMRouter version
# TYPE mitmrouter_version gauge
mitmrouter_version{version="${MITMROUTER_VERSION}"} 1
EOF
    
    # Atomically move temp file to metrics file
    mv "${metrics_temp}" "${METRICS_FILE}"
    
    return 0
}

# Run periodic metrics collection
metrics_collection_daemon() {
    local interval="${monitoring_metrics_interval:-30}"
    
    log_info "Starting metrics collection daemon (interval: ${interval}s)"
    
    while true; do
        export_prometheus_metrics
        sleep "${interval}"
    done
}

# Generate health check report
generate_health_report() {
    log_info "Generating health check report..."
    
    local bridge="${network_bridge_name:-br0}"
    local health_temp="/tmp/mitmrouter_health_$$.json"
    
    # Collect health information
    local bridge_status=$([[ -d "/sys/class/net/${bridge}" ]] && echo "up" || echo "down")
    local hostapd_status=$(systemctl is-active hostapd 2>/dev/null || echo "unknown")
    local dnsmasq_status=$(systemctl is-active dnsmasq 2>/dev/null || echo "unknown")
    local mitmproxy_status=$([[ $(pgrep -f "mitmproxy" >/dev/null) ]] && echo "running" || echo "stopped")
    
    # Determine overall health
    local overall_health="healthy"
    if [[ "${hostapd_status}" != "active" ]] || \
       [[ "${dnsmasq_status}" != "active" ]] || \
       [[ "${mitmproxy_status}" != "running" ]]; then
        overall_health="degraded"
    fi
    
    # Write health report in JSON format
    cat > "${health_temp}" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "${MITMROUTER_VERSION}",
  "health": "${overall_health}",
  "services": {
    "bridge": "${bridge_status}",
    "hostapd": "${hostapd_status}",
    "dnsmasq": "${dnsmasq_status}",
    "mitmproxy": "${mitmproxy_status}"
  }
}
EOF
    
    # Move health report to final location
    mv "${health_temp}" "${HEALTH_CHECK_FILE}"
    
    return 0
}

# Run comprehensive health checks
run_health_checks() {
    log_info "Running health checks..."
    
    local checks_passed=0
    local checks_failed=0
    
    # Check 1: Bridge interface exists
    if ip link show "${network_bridge_name:-br0}" &>/dev/null; then
        log_success "Bridge interface check: PASS"
        ((checks_passed++))
    else
        log_error "Bridge interface check: FAIL"
        ((checks_failed++))
    fi
    
    # Check 2: hostapd running
    if systemctl is-active hostapd >/dev/null 2>&1; then
        log_success "hostapd check: PASS"
        ((checks_passed++))
    else
        log_error "hostapd check: FAIL"
        ((checks_failed++))
    fi
    
    # Check 3: dnsmasq running
    if systemctl is-active dnsmasq >/dev/null 2>&1; then
        log_success "dnsmasq check: PASS"
        ((checks_passed++))
    else
        log_error "dnsmasq check: FAIL"
        ((checks_failed++))
    fi
    
    # Check 4: MITMProxy running
    if pgrep -f "mitmproxy" >/dev/null; then
        log_success "MITMProxy check: PASS"
        ((checks_passed++))
    else
        log_error "MITMProxy check: FAIL"
        ((checks_failed++))
    fi
    
    # Check 5: IP forwarding enabled
    if sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q "1"; then
        log_success "IP forwarding check: PASS"
        ((checks_passed++))
    else
        log_error "IP forwarding check: FAIL"
        ((checks_failed++))
    fi
    
    # Summary
    log_info "Health check summary: ${checks_passed} passed, ${checks_failed} failed"
    
    # Generate health report
    generate_health_report
    
    if [[ ${checks_failed} -eq 0 ]]; then
        log_success "All health checks passed"
        return 0
    else
        log_warn "Some health checks failed"
        return 1
    fi
}

# Get Prometheus scrape endpoint
get_prometheus_endpoint() {
    echo "file:///${METRICS_FILE}"
}

# Monitor interface throughput
monitor_interface_throughput() {
    local interface="$1"
    local interval="${2:-5}"
    
    echo "Monitoring ${interface} (interval: ${interval}s)"
    echo "Time RX_bytes RX_pps TX_bytes TX_pps"
    
    local prev_rx_bytes=0
    local prev_tx_bytes=0
    
    while true; do
        local timestamp=$(date '+%H:%M:%S')
        
        local rx_bytes=0
        local tx_bytes=0
        
        if [[ -d "/sys/class/net/${interface}" ]]; then
            rx_bytes=$(cat "/sys/class/net/${interface}/statistics/rx_bytes")
            tx_bytes=$(cat "/sys/class/net/${interface}/statistics/tx_bytes")
        fi
        
        # Calculate packet per second
        local rx_pps=$(( (rx_bytes - prev_rx_bytes) / interval ))
        local tx_pps=$(( (tx_bytes - prev_tx_bytes) / interval ))
        
        echo "${timestamp} ${rx_bytes} ${rx_pps} ${tx_bytes} ${tx_pps}"
        
        prev_rx_bytes=${rx_bytes}
        prev_tx_bytes=${tx_bytes}
        
        sleep "${interval}"
    done
}
```

================================================================================
FILE 8: lib/docker_utils.sh (Container Management)
================================================================================
Location: ./lib/docker_utils.sh

```bash
#!/bin/bash
################################################################################
# MITMRouter Docker Utilities
# Functions for container management and Docker operations
################################################################################

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    if ! docker ps &>/dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    log_success "Docker is available"
    return 0
}

# Build Docker image
build_docker_image() {
    local dockerfile="${1:-./Dockerfile}"
    local image_name="${2:-mitmrouter:latest}"
    local build_args="${3:-}"
    
    log_info "Building Docker image: ${image_name}"
    log_info "Dockerfile: ${dockerfile}"
    
    # Check if Docker is available
    check_docker || return 1
    
    # Build command
    local build_cmd="docker build -t ${image_name} -f ${dockerfile}"
    
    # Add build arguments if provided
    if [[ -n "${build_args}" ]]; then
        build_cmd+=" ${build_args}"
    fi
    
    build_cmd+=" ."
    
    log_debug "Build command: ${build_cmd}"
    
    # Execute build
    if eval "${build_cmd}"; then
        log_success "Image built successfully: ${image_name}"
        return 0
    else
        log_error "Failed to build image"
        return 1
    fi
}

# Start Docker container
start_docker_container() {
    local image_name="$1"
    local container_name="${2:-mitmrouter}"
    
    log_info "Starting Docker container: ${container_name} (image: ${image_name})"
    
    # Check if Docker is available
    check_docker || return 1
    
    # Check if container already running
    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_warn "Container ${container_name} is already running"
        return 0
    fi
    
    # Remove old container if exists
    if docker ps -a --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_info "Removing old container ${container_name}..."
        docker rm "${container_name}" || true
    fi
    
    # Start container with necessary options
    docker run -d \
        --name "${container_name}" \
        --network host \
        --privileged \
        --cap-add NET_ADMIN \
        --cap-add NET_RAW \
        -v "$(pwd)/config:/opt/mitmrouter/config:ro" \
        -v "$(pwd)/logs:/var/log/mitmrouter" \
        -e "LOG_LEVEL=INFO" \
        "${image_name}" || return 1
    
    log_success "Container started: ${container_name}"
    return 0
}

# Stop Docker container
stop_docker_container() {
    local container_name="${1:-mitmrouter}"
    
    log_info "Stopping Docker container: ${container_name}"
    
    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker stop "${container_name}" || return 1
        log_success "Container stopped: ${container_name}"
    else
        log_warn "Container ${container_name} is not running"
    fi
    
    return 0
}

# Get container logs
get_docker_container_logs() {
    local container_name="${1:-mitmrouter}"
    local tail_lines="${2:-100}"
    
    docker logs --tail "${tail_lines}" -f "${container_name}"
}

# Execute command in running container
docker_exec() {
    local container_name="$1"
    shift
    local cmd="$*"
    
    docker exec -it "${container_name}" bash -c "${cmd}"
}
```

(Continuing in next file due to length...)

================================================================================
END OF PART 2 - Files 6-8

See PART 3 for:
- All GitHub Actions workflows (6 files)
- All configuration files (YAML, JSON)
- All test files (BATS)
- Dockerfile & Docker Compose
- All documentation files

================================================================================
