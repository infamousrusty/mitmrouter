# MITMRouter v2.1.0 Quick Start Guide

Get up and running with MITMRouter v2.1 in under 10 minutes.

## Prerequisites

### Hardware
- Linux machine (laptop or Raspberry Pi)
- WiFi adapter supporting AP mode
- Ethernet connection to internet

### Software
- Ubuntu 20.04+, Debian 11+, or Fedora 36+
- Root/sudo access
- Git

## Step 1: Installation (2 minutes)

Clone the repository
git clone https://github.com/yourusername/mitmrouter.git
cd mitmrouter

Make executable
chmod +x mitmrouter.sh

Install dependencies
sudo apt-get update
sudo apt-get install -y
hostapd
dnsmasq
bridge-utils
net-tools
iptables
python3
python3-pip
jq
sqlite3
tcpdump
openssl

Install MITMProxy (automatically handled by script, but can pre-install)
sudo python3 -m pip install mitmproxy==10.4.2

text

## Step 2: Configuration (3 minutes)

### Edit the default profile

Open default configuration
nano config/profiles/default.yml

text

**Update these values:**

network:
wan_interface: eth0 # Your internet interface
wlan_interface: wlan0 # Your WiFi interface
bridge_name: br0

wifi:
ssid: "MyMITMRouter" # Your AP name
password: "SecurePass123" # Your AP password (min 8 chars)

text

### Verify your interfaces

List network interfaces
ip link show

Find your WiFi interface (usually wlan0)
Find your internet interface (usually eth0 or eno1)
text

## Step 3: First Start (2 minutes)

Start MITMRouter with default profile
sudo ./mitmrouter.sh up

You should see:
✓ System initialization complete
✓ Configuration loaded successfully
✓ All dependencies verified
✓ Bridge configured: br0
✓ hostapd configured and running
✓ dnsmasq configured and running
✓ IP forwarding and NAT enabled
✓ MITMProxy started (PID: XXXX)
✓ Traffic classifier started (PID: YYYY)
✓ Monitoring initialized
✓ All services started successfully
text

## Step 4: Connect a Device (1 minute)

1. **On your mobile device or laptop:**
   - Look for WiFi network: **MyMITMRouter**
   - Password: **SecurePass123**
   - Connect

2. **Test internet connectivity:**
   - Open browser → `http://example.com`
   - Should work normally

3. **View captured traffic:**
   - Open browser → `http://<your-linux-ip>:8081`
   - MITMProxy web interface shows all HTTP/HTTPS traffic

## Step 5: Explore v2.1 Features (2 minutes)

### Check Status

./mitmrouter.sh status

text

**You'll see:**
MITMRouter v2.1.0 Status Report
Status: RUNNING
Profile: default
Started: 2025-12-21T14:30:00Z

Core Services:
hostapd: ✓ RUNNING
dnsmasq: ✓ RUNNING

MITMProxy:
Status: ✓ RUNNING
Listen Port: 8080
Web Interface: http://localhost:8081
Addons: request_logger

Traffic Classifier:
Status: ✓ RUNNING
Classified Flows: 42

Connected Devices: 1

Evidence Collection:
Captured Files: 3
Chain-of-Custody: ✓ ENABLED

text

### Export Evidence

Export as JSON
sudo ./mitmrouter.sh export --format json

Output: /var/lib/mitmrouter/evidence/exports/evidence_20251221_143500.json
text

### View Traffic Classifications

List available classification rules
sudo ./mitmrouter.sh classify

Output shows detected devices:
- IoT devices (Alexa, Google Home, etc.)
- Mobile apps (iOS, Android)
- Streaming services (Netflix, YouTube)
- Suspicious connections
text

## Common Use Cases

### Use Case 1: IoT Security Research

Use the IoT research profile
sudo ./mitmrouter.sh down
sudo ./mitmrouter.sh up --profile iot_research

Connect your IoT device
Traffic automatically classified and logged
text

### Use Case 2: Mobile App Penetration Testing

Use the pentest profile (includes payload injection)
sudo ./mitmrouter.sh down
sudo ./mitmrouter.sh up --profile pentest

Install certificate on mobile device:
1. Start cert server
sudo ./mitmrouter.sh cert-server start

2. On iOS device:
- Browse to http://<your-ip>:8000/mobile/mitmrouter-ca.mobileconfig
- Install profile
- Settings → General → About → Certificate Trust Settings
- Enable full trust
3. On Android device:
- Browse to http://<your-ip>:8000/mobile/mitmrouter-ca.der
- Install certificate
text

### Use Case 3: Forensic Evidence Collection

Use forensic profile (full logging + chain-of-custody)
sudo ./mitmrouter.sh down
sudo ./mitmrouter.sh up --profile forensic

Evidence automatically collected with timestamps and hashes
Export after session:
sudo ./mitmrouter.sh export --format sqlite
sudo ./mitmrouter.sh export --format html

View chain-of-custody:
cat /var/lib/mitmrouter/chain_of_custody.log

text

## Stopping MITMRouter

Stop all services
sudo ./mitmrouter.sh down

Output:
✓ MITMProxy stopped
✓ Traffic classifier stopped
✓ All services stopped
text

## Troubleshooting

### "Interface not found"
Check interface names
ip link show

Update config/profiles/default.yml with correct names
text

### "MITMProxy failed to start"
Check logs
sudo ./mitmrouter.sh logs

Or check MITMProxy-specific logs
tail -f /var/log/mitmrouter/mitmproxy.log

text

### "No HTTPS traffic visible"
- **Install MITMRouter CA certificate on your device** (see Use Case 2)
- Without CA cert, you'll only see HTTP traffic

### "Permission denied"
Always run with sudo
sudo ./mitmrouter.sh up

text

## Next Steps

- **Read full documentation**: `docs/v2.1/FEATURES.md`
- **Customize profiles**: `docs/v2.1/PROFILES.md`
- **Write custom addons**: `docs/v2.1/ADDONS.md`
- **Set up pinning bypass**: `docs/v2.1/PINNING_BYPASS.md`

## Quick Reference

| Command | Description |
|---------|-------------|
| `sudo ./mitmrouter.sh up` | Start with default profile |
| `sudo ./mitmrouter.sh up --profile forensic` | Start with forensic profile |
| `./mitmrouter.sh status` | View status and metrics |
| `sudo ./mitmrouter.sh down` | Stop all services |
| `sudo ./mitmrouter.sh export --format json` | Export evidence as JSON |
| `sudo ./mitmrouter.sh classify` | View classification rules |
| `sudo ./mitmrouter.sh restart` | Restart all services |
| `./mitmrouter.sh logs` | View logs |
| `sudo ./mitmrouter.sh health` | Run health checks |

---

**Success!** 🎉 You're now running MITMRouter v2.1.0 with traffic classification, evidence export, and certificate management.

For questions or issues, please check the troubleshooting guide or open an issue on GitHub.