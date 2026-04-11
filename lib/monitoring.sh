#!/bin/bash
################################################################################
# MITMRouter Monitoring & Observability
# Prometheus metrics export, health checks, traffic monitoring
################################################################################

# Monitoring configuration
readonly METRICS_FILE="/var/lib/mitmrouter/metrics.prom"
readonly HEALTH_CHECK_FILE="/var/lib/mitmrouter/health.json"

# Initialize monitoring
initialize_monitoring() {
    log_info "Initializing monitoring..."

    local metrics_dir
    metrics_dir="$(dirname "${METRICS_FILE}")"

    mkdir -p "${metrics_dir}"
    chmod 755 "${metrics_dir}"

    touch "${METRICS_FILE}"
    chmod 644 "${METRICS_FILE}"

    log_success "Monitoring initialized"
    return 0
}

# Export Prometheus metrics
export_prometheus_metrics() {
    log_debug "Exporting Prometheus metrics..."

    local bridge="${network_bridge_name:-br0}"
    local wlan_if="${network_wlan_interface:-wlan0}"
    local metrics_temp
    metrics_temp="/tmp/mitmrouter_metrics_$$.prom"

    local rx_bytes=0
    local tx_bytes=0
    local rx_packets=0
    local tx_packets=0
    local connected_clients=0

    if [[ -d "/sys/class/net/${bridge}" ]]; then
        rx_bytes=$(cat "/sys/class/net/${bridge}/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/${bridge}/statistics/tx_bytes" 2>/dev/null || echo "0")
        rx_packets=$(cat "/sys/class/net/${bridge}/statistics/rx_packets" 2>/dev/null || echo "0")
        tx_packets=$(cat "/sys/class/net/${bridge}/statistics/tx_packets" 2>/dev/null || echo "0")
    fi

    if command -v iw &>/dev/null; then
        connected_clients=$(iw dev "${wlan_if}" station dump 2>/dev/null | grep -c "Station" || echo "0")
    fi

    local hostapd_status=0
    local dnsmasq_status=0
    local mitmproxy_status=0

    [[ $(systemctl is-active hostapd 2>/dev/null) == "active" ]] && hostapd_status=1
    [[ $(systemctl is-active dnsmasq 2>/dev/null) == "active" ]] && dnsmasq_status=1
    # SC2327/SC2328 fix: test pgrep exit status directly, do not capture output
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then mitmproxy_status=1; fi

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
mitmrouter_connected_clients{interface="${wlan_if}"} ${connected_clients}

# HELP mitmrouter_service_up Service availability status
# TYPE mitmrouter_service_up gauge
mitmrouter_service_up{service="hostapd"} ${hostapd_status}
mitmrouter_service_up{service="dnsmasq"} ${dnsmasq_status}
mitmrouter_service_up{service="mitmproxy"} ${mitmproxy_status}

# HELP mitmrouter_version MITMRouter version
# TYPE mitmrouter_version gauge
mitmrouter_version{version="${MITMROUTER_VERSION}"} 1
EOF

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
    local health_temp
    health_temp="/tmp/mitmrouter_health_$$.json"

    local bridge_status
    bridge_status=$([[ -d "/sys/class/net/${bridge}" ]] && echo "up" || echo "down")
    local hostapd_status
    hostapd_status=$(systemctl is-active hostapd 2>/dev/null || echo "unknown")
    local dnsmasq_status
    dnsmasq_status=$(systemctl is-active dnsmasq 2>/dev/null || echo "unknown")

    # SC2327/SC2328 fix: test pgrep exit status directly
    local mitmproxy_status="stopped"
    if pgrep -f "mitmproxy" >/dev/null 2>&1; then mitmproxy_status="running"; fi

    local overall_health="healthy"
    if [[ "${hostapd_status}" != "active" ]] || \
       [[ "${dnsmasq_status}" != "active" ]] || \
       [[ "${mitmproxy_status}" != "running" ]]; then
        overall_health="degraded"
    fi

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

    mv "${health_temp}" "${HEALTH_CHECK_FILE}"
    return 0
}

# Run comprehensive health checks
run_health_checks() {
    log_info "Running health checks..."

    local checks_passed=0
    local checks_failed=0

    if ip link show "${network_bridge_name:-br0}" &>/dev/null; then
        log_success "Bridge interface check: PASS"
        (( checks_passed++ ))
    else
        log_error "Bridge interface check: FAIL"
        (( checks_failed++ ))
    fi

    if systemctl is-active hostapd >/dev/null 2>&1; then
        log_success "hostapd check: PASS"
        (( checks_passed++ ))
    else
        log_error "hostapd check: FAIL"
        (( checks_failed++ ))
    fi

    if systemctl is-active dnsmasq >/dev/null 2>&1; then
        log_success "dnsmasq check: PASS"
        (( checks_passed++ ))
    else
        log_error "dnsmasq check: FAIL"
        (( checks_failed++ ))
    fi

    if pgrep -f "mitmproxy" >/dev/null 2>&1; then
        log_success "MITMProxy check: PASS"
        (( checks_passed++ ))
    else
        log_error "MITMProxy check: FAIL"
        (( checks_failed++ ))
    fi

    if sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q "1"; then
        log_success "IP forwarding check: PASS"
        (( checks_passed++ ))
    else
        log_error "IP forwarding check: FAIL"
        (( checks_failed++ ))
    fi

    log_info "Health check summary: ${checks_passed} passed, ${checks_failed} failed"
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
        local timestamp
        timestamp=$(date '+%H:%M:%S')

        local rx_bytes=0
        local tx_bytes=0

        if [[ -d "/sys/class/net/${interface}" ]]; then
            rx_bytes=$(cat "/sys/class/net/${interface}/statistics/rx_bytes")
            tx_bytes=$(cat "/sys/class/net/${interface}/statistics/tx_bytes")
        fi

        local rx_pps=$(( (rx_bytes - prev_rx_bytes) / interval ))
        local tx_pps=$(( (tx_bytes - prev_tx_bytes) / interval ))

        echo "${timestamp} ${rx_bytes} ${rx_pps} ${tx_bytes} ${tx_pps}"

        prev_rx_bytes=${rx_bytes}
        prev_tx_bytes=${tx_bytes}

        sleep "${interval}"
    done
}
