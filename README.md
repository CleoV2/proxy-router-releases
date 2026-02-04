# Proxy Router for Raspberry Pi

Turn your Raspberry Pi 5 into a WiFi proxy router with per-device SOCKS5 proxy support.

## Features

- **Per-device proxy routing** - Each connected device can use a different proxy
- **Web portal** - Easy proxy configuration at http://proxy.lan
- **Admin dashboard** - Monitor connected devices at http://proxy.lan/admin
- **Auto-setup** - Flash SD card and go

## Quick Start

### Option 1: Auto-Setup (Recommended)

1. **Flash Raspberry Pi OS (64-bit)** using [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
   - Enable SSH
   - Set username: `admin`
   - Configure your home WiFi (for internet during setup)

2. **Download** `firstrun.sh` from [Releases](https://github.com/CleoV2/proxy-router-releases/releases)

3. **Copy `firstrun.sh`** to the boot partition of the SD card

4. **Edit `cmdline.txt`** on the boot partition, add to the END of the line:
   ```
   systemd.run=/boot/firmware/firstrun.sh systemd.run_success_action=none systemd.unit=kernel-command-line.target
   ```

5. **Boot Pi** with ethernet connected, wait 5-10 minutes

6. **Connect to WiFi**: `ProxyRouter` (password: `proxy12345`)

7. **Configure proxy**: Open http://proxy.lan

### Option 2: Manual Install

See the `firstrun.sh` script for all setup steps.

## Usage

### User Portal
- Connect to `ProxyRouter` WiFi
- Open http://proxy.lan
- Enter your SOCKS5 proxy details
- Click Connect

### Admin Panel
- URL: http://proxy.lan/admin
- Username: `admin`
- Password: `proxy12345` (same as WiFi password)

## Requirements

- Raspberry Pi 5 (or Pi 4)
- SD Card (16GB+)
- Ethernet connection (for WAN/internet)
- Power supply

## Default Settings

| Setting | Value |
|---------|-------|
| WiFi SSID | ProxyRouter |
| WiFi Password | proxy12345 |
| Portal URL | http://proxy.lan |
| Admin URL | http://proxy.lan/admin |
| AP IP | 10.0.0.1 |
| DHCP Range | 10.0.0.10 - 10.0.0.250 |

## License

MIT
