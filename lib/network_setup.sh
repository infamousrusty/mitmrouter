#!/bin/bash
################################################################################
# MITMRouter Network Setup
# Configures bridge, hostapd, dnsmasq, and NAT/forwarding
#
# NOTE: Variables such as network_wan_interface, network_wlan_interface,
# dhcp_gateway, wifi_ssid, wifi_password, dhcp_start_ip, dhcp_end_ip,
# dhcp_subnet_mask, dhcp_lease_time are all set by lib/config_parser.sh
# (parse_yaml) at runtime before any of these functions are called.
# ShellCheck cannot see cross-file assignments, so we suppress SC2154 where
# necessary rather than replacing the established runtime-config pattern.
################################################################################

# Dependency verification
verify_dependencies() {
    log_info "Verifying dependencies..."

    local required_cmds=(
        "hostapd" "dnsmasq" "brctl" "ip" "iptables" "iw" "systemctl"
    )

    local missing_cmds=()
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "${cmd}" &>/dev/null; then
            missing_cmds+=("${cmd}")
        fi
    done

    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Install them using your package manager (apt, dnf, pacman)"
        return 1
    fi

    log_success "All dependencies verified"
    return 0
}

# Set up network bridge
setup_bridge() {
    # shellcheck disable=SC2154
    local wan_if="${network_wan_interface}"
    # shellcheck disable=SC2154
    local wlan_if="${network_wlan_interface}"
    local bridge="${network_bridge_name:-br0}"

    log_info "Setting up bridge: ${bridge}"

    if ip link show "${bridge}" &>/dev/null; then
        log_info "Bridge ${bridge} already exists, removing..."
        ip link set "${bridge}" down 2>/dev/null || true
        brctl delbr "${bridge}" 2>/dev/null || true
    fi

    brctl addbr "${bridge}" || return 1

    brctl addif "${bridge}" "${wlan_if}" || {
        log_error "Failed to add ${wlan_if} to bridge"
        return 1
    }

    # shellcheck disable=SC2154
    ip addr add "${dhcp_gateway}/24" dev "${bridge}" || return 1
    ip link set "${bridge}" up || return 1

    log_success "Bridge configured: ${bridge}"
    return 0
}

# Tear down network bridge
teardown_bridge() {
    local bridge="${network_bridge_name:-br0}"
    log_info "Tearing down bridge: ${bridge}"
    if ip link show "${bridge}" &>/dev/null; then
        ip link set "${bridge}" down 2>/dev/null || true
        brctl delbr "${bridge}" 2>/dev/null || true
    fi
    log_success "Bridge removed"
    return 0
}

# Configure hostapd (WiFi AP)
setup_hostapd() {
    log_info "Configuring hostapd..."

    local hostapd_conf="/etc/hostapd/mitmrouter.conf"
    # shellcheck disable=SC2154
    local wlan_if="${network_wlan_interface}"
    local bridge="${network_bridge_name:-br0}"

    cat > "${hostapd_conf}" << EOF
# MITMRouter hostapd Configuration
interface=${wlan_if}
bridge=${bridge}
driver=nl80211

# WiFi Settings
# shellcheck disable=SC2154
ssid=${wifi_ssid}
channel=${wifi_channel:-6}
hw_mode=${wifi_standard:-g}
wmm_enabled=1
macaddr_acl=0
auth_algs=1

# Security
wpa=2
# shellcheck disable=SC2154
wpa_passphrase=${wifi_password}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP TKIP
wpa_group_rekey=86400

# Logging
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2

# Additional settings
ignore_broadcast_ssid=${wifi_hidden:-0}
beacon_int=100
dtim_period=2
rts_threshold=2347
frag_threshold=2346
ap_isolate=0
EOF

    log_info "Starting hostapd..."
    systemctl start hostapd || return 1
    systemctl enable hostapd 2>/dev/null || true

    log_success "hostapd configured and running"
    return 0
}

# Configure dnsmasq (DHCP and DNS)
setup_dnsmasq() {
    log_info "Configuring dnsmasq..."

    local dnsmasq_conf="/etc/dnsmasq.d/mitmrouter.conf"
    local bridge="${network_bridge_name:-br0}"

    cat > "${dnsmasq_conf}" << EOF
# MITMRouter dnsmasq Configuration
interface=${bridge}
# shellcheck disable=SC2154
listen-address=${dhcp_gateway}

# DHCP Configuration
# shellcheck disable=SC2154
dhcp-range=${dhcp_start_ip},${dhcp_end_ip},${dhcp_subnet_mask},${dhcp_lease_time}

# DNS Servers
server=${dhcp_dns_servers[0]:-8.8.8.8}
server=${dhcp_dns_servers[1]:-8.8.4.4}

# DNS Options
dhcp-option=option:dns-server,${dhcp_gateway}
dhcp-option=option:router,${dhcp_gateway}

# Logging
log-facility=/var/log/mitmrouter/dnsmasq.log
log-dhcp
log-queries

# Performance tuning
cache-size=10000
EOF

    log_info "Starting dnsmasq..."
    systemctl restart dnsmasq || return 1
    systemctl enable dnsmasq 2>/dev/null || true

    log_success "dnsmasq configured and running"
    return 0
}

# Enable IP forwarding and NAT
enable_ip_forwarding() {
    log_info "Enabling IP forwarding and NAT..."

    # shellcheck disable=SC2154
    local wan_if="${network_wan_interface}"
    local bridge="${network_bridge_name:-br0}"

    sysctl -w net.ipv4.ip_forward=1 || return 1
    echo "net.ipv4.ip_forward=1" | tee -a /etc/sysctl.conf >/dev/null

    iptables -t nat -A POSTROUTING -o "${wan_if}" -j MASQUERADE || return 1
    iptables -A FORWARD -i "${bridge}" -o "${wan_if}" -j ACCEPT || return 1
    iptables -A FORWARD -i "${wan_if}" -o "${bridge}" -m state --state RELATED,ESTABLISHED -j ACCEPT || return 1

    iptables -t nat -A PREROUTING -i "${bridge}" -p tcp --dport 80  -j REDIRECT --to-port "${mitmproxy_listen_port:-8080}" || return 1
    iptables -t nat -A PREROUTING -i "${bridge}" -p tcp --dport 443 -j REDIRECT --to-port "${mitmproxy_listen_port:-8080}" || return 1

    log_success "IP forwarding and NAT enabled"
    return 0
}

# Clean up iptables rules
cleanup_iptables() {
    log_info "Cleaning up iptables rules..."

    # shellcheck disable=SC2154
    local wan_if="${network_wan_interface}"
    local bridge="${network_bridge_name:-br0}"

    iptables -t nat -D POSTROUTING -o "${wan_if}" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "${bridge}" -o "${wan_if}" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "${wan_if}" -o "${bridge}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${bridge}" -p tcp --dport 80  -j REDIRECT --to-port "${mitmproxy_listen_port:-8080}" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${bridge}" -p tcp --dport 443 -j REDIRECT --to-port "${mitmproxy_listen_port:-8080}" 2>/dev/null || true

    log_success "iptables rules cleaned"
    return 0
}

# Get connected clients
get_connected_clients() {
    # shellcheck disable=SC2154
    local wlan_if="${network_wlan_interface}"

    if command -v iw &>/dev/null; then
        iw dev "${wlan_if}" station dump | grep -E "^Station|signal" | sed 'N;s/\\n/ /'
    else
        log_warn "iw command not available"
        return 1
    fi
}

# Show network statistics
show_network_stats() {
    local bridge="${network_bridge_name:-br0}"
    log_info "Network Statistics for ${bridge}:"

    if [[ -d "/sys/class/net/${bridge}" ]]; then
        local rx_bytes
        rx_bytes=$(cat "/sys/class/net/${bridge}/statistics/rx_bytes" 2>/dev/null || echo "0")
        local tx_bytes
        tx_bytes=$(cat "/sys/class/net/${bridge}/statistics/tx_bytes" 2>/dev/null || echo "0")
        local rx_packets
        rx_packets=$(cat "/sys/class/net/${bridge}/statistics/rx_packets" 2>/dev/null || echo "0")
        local tx_packets
        tx_packets=$(cat "/sys/class/net/${bridge}/statistics/tx_packets" 2>/dev/null || echo "0")

        echo "RX: ${rx_packets} packets, ${rx_bytes} bytes"
        echo "TX: ${tx_packets} packets, ${tx_bytes} bytes"
    fi
}
