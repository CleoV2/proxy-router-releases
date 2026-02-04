#!/bin/bash
# Proxy Router Setup Script v1.0.2
# Includes: hostapd, dnsmasq, dnscrypt-proxy, sing-box, router-software

set -e
echo "========================================"
echo "  Proxy Router Setup v1.0.2"
echo "========================================"

if [ "$EUID" -ne 0 ]; then
    echo "Run with: sudo bash setup-router.sh"
    exit 1
fi

echo "[1/10] Installing packages..."
apt update
apt install -y hostapd dnsmasq dnscrypt-proxy iptables-persistent curl

echo "[2/10] Setting WiFi country..."
raspi-config nonint do_wifi_country GB
rfkill unblock wlan

echo "[3/10] Configuring hostapd (WiFi AP)..."
cat > /etc/hostapd/hostapd.conf << 'EOF'
interface=wlan0
driver=nl80211
ssid=ProxyRouter
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=proxy12345
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=GB
ieee80211n=1
EOF

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

echo "[4/10] Configuring static IP for wlan0..."
cat >> /etc/dhcpcd.conf << 'EOF'

interface wlan0
    static ip_address=10.0.0.1/24
    nohook wpa_supplicant
EOF

echo "[5/10] Configuring dnsmasq (DHCP + DNS)..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null || true
cat > /etc/dnsmasq.conf << 'EOF'
interface=wlan0
bind-interfaces
dhcp-range=10.0.0.10,10.0.0.250,255.255.255.0,24h
address=/proxy.lan/10.0.0.1
no-resolv
server=127.0.0.1#5053
EOF

echo "[6/10] Configuring dnscrypt-proxy (DNS over HTTPS via SOCKS5)..."
systemctl stop dnscrypt-proxy.socket 2>/dev/null || true
systemctl disable dnscrypt-proxy.socket 2>/dev/null || true

cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml << 'EOF'
listen_addresses = ['127.0.0.1:5053']
server_names = ['cloudflare']
ipv6_servers = false
require_dnssec = false
require_nolog = true
require_nofilter = true

# SOCKS5 proxy - updated dynamically by router-software when proxy connects
# proxy = 'socks5://user:pass@host:port'

fallback_resolvers = ['1.1.1.1:53', '8.8.8.8:53']
ignore_system_dns = true
timeout = 5000
keepalive = 30

[sources]
  [sources.'public-resolvers']
  url = 'https://download.dnscrypt.info/resolvers-list/v2/public-resolvers.md'
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''
EOF

echo "[7/10] Downloading router software..."
mkdir -p /home/admin/router-software/data
mkdir -p /home/admin/router-software/web/templates

curl -L -o /home/admin/router-software/router-software https://github.com/CleoV2/proxy-router-releases/releases/download/v1.0.2/router-software-arm64
curl -L -o /home/admin/router-software/web/templates/index.html https://github.com/CleoV2/proxy-router-releases/releases/download/v1.0.2/index.html
curl -L -o /home/admin/router-software/web/templates/admin.html https://github.com/CleoV2/proxy-router-releases/releases/download/v1.0.2/admin.html

chmod +x /home/admin/router-software/router-software
chown -R admin:admin /home/admin/router-software

echo "[8/10] Installing sing-box & creating configs..."
curl -fsSL https://sing-box.app/deb-install.sh | bash

cat > /home/admin/router-software/config.json << 'EOF'
{"listen_addr":"0.0.0.0","listen_port":80,"ap_interface":"wlan0","wan_interface":"eth0","ap_ssid":"ProxyRouter","ap_password":"proxy12345","ap_channel":7,"ap_subnet":"10.0.0.0/24","ap_gateway":"10.0.0.1","dhcp_start":"10.0.0.10","dhcp_end":"10.0.0.250","domain":"lan","database_path":"/home/admin/router-software/data/devices.db","singbox_config_path":"/home/admin/router-software/data/singbox.json","singbox_binary_path":"/usr/bin/sing-box"}
EOF

cat > /etc/router-software/config.json << 'EOF'
{"listen_addr":"0.0.0.0","listen_port":80,"ap_interface":"wlan0","wan_interface":"eth0","ap_ssid":"ProxyRouter","ap_password":"proxy12345","ap_channel":7,"ap_subnet":"10.0.0.0/24","ap_gateway":"10.0.0.1","dhcp_start":"10.0.0.10","dhcp_end":"10.0.0.250","domain":"lan","database_path":"/home/admin/router-software/data/devices.db","singbox_config_path":"/home/admin/router-software/data/singbox.json","singbox_binary_path":"/usr/bin/sing-box"}
EOF

mkdir -p /etc/router-software

cat > /etc/systemd/system/router-software.service << 'EOF'
[Unit]
Description=Router Software
After=network.target dnscrypt-proxy.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/admin/router-software
Environment=ROUTER_CONFIG_PATH=/etc/router-software/config.json
ExecStart=/home/admin/router-software/router-software
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "[9/10] Setting up iptables..."
sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# NAT for outbound traffic
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

# Block QUIC to force TCP
iptables -A FORWARD -i wlan0 -p udp --dport 443 -j DROP

# RETURN rules must come BEFORE REDIRECT (correct order!)
iptables -t nat -A PREROUTING -i wlan0 -p tcp -d 10.0.0.0/24 -j RETURN
iptables -t nat -A PREROUTING -i wlan0 -p tcp -d 192.168.0.0/24 -j RETURN
iptables -t nat -A PREROUTING -i wlan0 -s 10.0.0.0/24 -p tcp -j REDIRECT --to-ports 12345

netfilter-persistent save

echo "[10/10] Enabling services..."
systemctl unmask hostapd
systemctl daemon-reload
systemctl enable hostapd dnsmasq dnscrypt-proxy router-software

echo ""
echo "========================================"
echo "  Setup Complete! Rebooting..."
echo "========================================"
echo ""
echo "After reboot:"
echo "  1. Connect to WiFi: ProxyRouter (pass: proxy12345)"
echo "  2. Open: http://10.0.0.1"
echo "  3. Enter your SOCKS5 proxy and connect"
echo ""
echo "Services:"
echo "  - hostapd: WiFi Access Point"
echo "  - dnsmasq: DHCP + DNS forwarding"
echo "  - dnscrypt-proxy: DNS through SOCKS5 proxy"
echo "  - sing-box: TCP traffic proxying"
echo "  - router-software: Web portal"
echo ""
sleep 3
reboot
