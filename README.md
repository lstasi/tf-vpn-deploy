# tf-vpn-deploy

Terraform configuration and management scripts to deploy and manage VPN services (OpenVPN and WireGuard) on OPNsense firewalls. Includes tooling for SSH bastion tunneling and deploying client configurations to Android devices.

## Features

- **Terraform-managed WireGuard** — Provision WireGuard servers and peers on OPNsense via the [browningluke/opnsense](https://registry.terraform.io/providers/browningluke/opnsense/latest) Terraform provider.
- **OpenVPN management** — List, export, and control OpenVPN instances via the OPNsense API.
- **WireGuard management** — Full lifecycle management (create, list, remove peers; generate keys; export configs) via the OPNsense API.
- **SSH bastion support** — Tunnel through a bastion host to reach OPNsense in private networks.
- **Android deployment** — Push `.ovpn` / `.conf` files to Android via ADB, or generate QR codes for easy scanning.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [curl](https://curl.se/) (for API scripts)
- [python3](https://www.python.org/) (for JSON formatting)
- [adb](https://developer.android.com/tools/releases/platform-tools) (optional — for Android deployment)
- [qrencode](https://fukuchi.org/works/qrencode/) (optional — for QR code generation)
- [wg](https://www.wireguard.com/install/) (optional — for local key generation)
- An OPNsense firewall with API access enabled

## Quick Start

### 1. Configure

Copy the example variables file and edit it with your OPNsense details:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your OPNsense URI, API credentials, and VPN settings
```

Or set environment variables:

```bash
export OPNSENSE_URI="https://192.168.1.1"
export OPNSENSE_API_KEY="your-api-key"
export OPNSENSE_API_SECRET="your-api-secret"
```

### 2. Deploy WireGuard via Terraform

```bash
# Direct connection
./scripts/setup.sh --apply

# Through an SSH bastion host
export BASTION_HOST="bastion.example.com"
export BASTION_USER="admin"
./scripts/setup.sh --bastion --apply
```

### 3. Manage VPN Services

```bash
# WireGuard
./scripts/wireguard-manage.sh list-servers
./scripts/wireguard-manage.sh list-peers
./scripts/wireguard-manage.sh gen-keys
./scripts/wireguard-manage.sh add-peer --name phone --address 10.10.0.2/32
./scripts/wireguard-manage.sh export-configs

# OpenVPN
./scripts/openvpn-manage.sh list-servers
./scripts/openvpn-manage.sh export-config --name my-phone
./scripts/openvpn-manage.sh restart
```

### 4. Deploy to Android

```bash
# Check device connectivity
./scripts/deploy-android.sh check

# Push configs via ADB
./scripts/deploy-android.sh push --file configs/wg-phone.conf
./scripts/deploy-android.sh push-all

# Or show a QR code to scan
./scripts/deploy-android.sh qr --file configs/wg-phone.conf
```

## Project Structure

```
├── terraform/                      # Terraform configuration
│   ├── provider.tf                 # OPNsense provider setup
│   ├── variables.tf                # Input variables
│   ├── wireguard.tf                # WireGuard server and peer resources
│   ├── outputs.tf                  # Output values
│   └── terraform.tfvars.example    # Example variable values
├── scripts/                        # Management scripts
│   ├── setup.sh                    # Main setup (bastion tunnel + terraform)
│   ├── openvpn-manage.sh           # OpenVPN management via API
│   ├── wireguard-manage.sh         # WireGuard management via API
│   └── deploy-android.sh           # Push configs to Android via ADB
├── configs/                        # Generated client configurations
│   └── .gitkeep
├── .gitignore
└── README.md
```

## Security Notes

- **Never commit `terraform.tfvars`** — it contains API credentials. The `.gitignore` excludes it.
- **Generated configs contain private keys** — the `configs/` directory is gitignored except for `.gitkeep`.
- **API credentials** — Use OPNsense API keys with minimum required permissions.
- **SSH bastion** — Ensure your bastion host is properly hardened and uses key-based authentication.
