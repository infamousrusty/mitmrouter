# Runbook: Wi-Fi AP Interception

**Applies to profiles:** `default`, `pentest`, `forensic`, `pinning`

## Prerequisites

- [ ] Written authorisation to intercept traffic on the target device
- [ ] mitmrouter host with a compatible wireless interface (monitor mode / AP mode capable)
- [ ] Python 3.10+ with `.venv` set up (see README)
- [ ] `MITMROUTER_WIFI_PASSWORD` set in environment or `.env`
- [ ] System dependencies installed: `hostapd`, `dnsmasq`, `bridge-utils`, `iproute2`, `iptables`
- [ ] NetworkManager disabled or configured to ignore the wireless interface

## Step 1 — Disable NetworkManager interference

```bash
# Option A: Stop NetworkManager entirely (lab environment)
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager

# Option B: Ignore specific interfaces (production host)
# Add to /etc/NetworkManager/conf.d/mitmrouter.conf:
# [keyfile]
# unmanaged-devices=interface-name:wlan0
sudo systemctl reload NetworkManager
```

## Step 2 — Load environment and choose a profile

```bash
cd /path/to/mitmrouter
source .env

# Check available profiles
ls config/profiles/
```

## Step 3 — Start the router

```bash
# General lab use
sudo ./mitmrouter.sh up --profile default

# Penetration testing (verbose logging, TShark enabled)
sudo ./mitmrouter.sh up --profile pentest

# SSL pinning bypass focus
sudo ./mitmrouter.sh up --profile pinning

# High-fidelity forensic capture (requires zeek + suricata)
sudo ./mitmrouter.sh up --profile forensic
```

## Step 4 — Connect the device under test

1. On the DUT, connect to the Wi-Fi SSID configured in your profile (default: `MITMRouter-Lab`)
2. Verify the DUT receives a DHCP address in the expected range (e.g. `192.168.200.100–150` for the default profile)
3. Verify internet access from the DUT: `ping 8.8.8.8`

## Step 5 — Install the mitmproxy CA certificate on the DUT

```bash
# The CA cert is generated automatically on first mitmproxy start
# Serve it for easy installation:
python3 -m http.server 8888 --directory ~/.mitmproxy/
```

On the DUT, navigate to `http://<mitmrouter-ip>:8888/mitmproxy-ca-cert.pem` and install as a trusted CA.

For Android 7+ and iOS: follow the platform-specific instructions at https://docs.mitmproxy.org/stable/concepts-certificates/.

## Step 6 — Verify interception is working

```bash
# Check mitmproxy web UI
open http://localhost:8081

# Check current status
sudo ./mitmrouter.sh status

# Run addon health checks
sudo ./mitmrouter.sh health

# Tail logs
sudo ./mitmrouter.sh logs
```

## Step 7 — Perform the assessment

Interact with the DUT application. Observe traffic in the mitmproxy web UI (`http://localhost:8081`) or via the `json_traffic_logger` JSONL output.

## Step 8 — Export evidence

```bash
sudo ./mitmrouter.sh export
```

Evidence is written to `/var/log/mitmrouter/evidence/<profile>/`.

## Step 9 — Tear down

```bash
sudo ./mitmrouter.sh down
```

This removes iptables rules, stops mitmproxy, hostapd, and dnsmasq, and removes the bridge interface.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| DUT does not receive IP | dnsmasq not running or bridge misconfigured | `sudo ./mitmrouter.sh status`; check `journalctl -u dnsmasq` |
| No traffic in mitmproxy | iptables REDIRECT rule not applied | `sudo iptables -t nat -L PREROUTING -n -v` |
| SSL errors on DUT | CA cert not installed | Repeat Step 5 |
| Pinning errors (connection refused) | App is pinned | Switch to `pinning` profile; note pinned hosts in addon output |
| hostapd fails to start | Interface in use or wrong driver | Check `sudo systemctl status hostapd`; ensure NM is not managing `wlan0` |
