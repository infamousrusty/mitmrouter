# Runbook: Ethernet Interception

**Applies to profile:** `ethernet`

## Prerequisites

- [ ] Written authorisation to intercept traffic on the target device
- [ ] mitmrouter host with **two** Ethernet interfaces (`eth0` for WAN, `eth1` for LAN)
- [ ] Python 3.10+ with `.venv` set up (see README)
- [ ] System dependencies installed: `bridge-utils`, `iproute2`, `iptables`, `dnsmasq`
- [ ] `MITMROUTER_WIFI_PASSWORD` not required for ethernet profile (but `.env` must still be sourced)

## Physical Setup

```
[Internet Router] ──── eth0 (WAN) ──── [mitmrouter host] ──── eth1 (LAN) ──── [Device Under Test]
```

Connect:
1. `eth0` to your upstream internet source (router, switch, or WAN)
2. `eth1` to the device under test (direct cable, or via a small unmanaged switch if multiple DUTs)

## Step 1 — Load environment

```bash
cd /path/to/mitmrouter
source .env
```

## Step 2 — Verify interface names

```bash
ip link show
```

Confirm `eth0` and `eth1` map to your actual interfaces. If your interfaces have different names (e.g. `enp3s0`, `enp4s0`), update `config/profiles/ethernet.yml` accordingly:

```yaml
network:
  wan_interface: enp3s0
  lan_interface: enp4s0
```

## Step 3 — Start the router

```bash
sudo ./mitmrouter.sh up --profile ethernet
```

## Step 4 — Connect the device under test

1. Plug the DUT into the `eth1` / LAN interface
2. Verify it receives a DHCP lease: `sudo cat /var/lib/misc/dnsmasq.leases`
3. Verify internet access from the DUT

## Step 5 — Install the mitmproxy CA certificate

Same as the Wi-Fi runbook Step 5. Serve the cert:

```bash
python3 -m http.server 8888 --directory ~/.mitmproxy/
```

On the DUT, install `http://<mitmrouter-ip>:8888/mitmproxy-ca-cert.pem` as a trusted CA.

## Step 6 — Verify interception

```bash
sudo ./mitmrouter.sh status
sudo ./mitmrouter.sh health
open http://localhost:8081   # mitmproxy web UI
```

## Step 7 — Export evidence

```bash
sudo ./mitmrouter.sh export
```

Evidence is written to `/var/log/mitmrouter/evidence/ethernet/`.

## Step 8 — Tear down

```bash
sudo ./mitmrouter.sh down
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| DUT does not receive IP | `eth1` not brought up or dnsmasq not bound to bridge | Check `ip link show eth1`; check `dnsmasq` logs |
| DUT has no internet | `ip_forward` not enabled or NAT rule missing | `sysctl net.ipv4.ip_forward`; check iptables MASQUERADE rule |
| No traffic in mitmproxy | REDIRECT rule on wrong interface | `sudo iptables -t nat -L PREROUTING -n -v` — confirm rule is on `br0` or `eth1` |
| SSL errors | CA cert not installed on DUT | Repeat Step 5 |
