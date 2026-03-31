# tf-vpn-deploy

Terraform configuration to deploy and manage VPN services (OpenVPN and WireGuard) on OPNsense firewalls. All VPN infrastructure is managed through Terraform. Includes a helper script for SSH bastion tunneling and a utility for deploying client configurations to Android devices.

## Features

- **Terraform-managed WireGuard** — Provision WireGuard servers and peers on OPNsense via the [browningluke/opnsense](https://registry.terraform.io/providers/browningluke/opnsense/latest) Terraform provider, with automatic client config file generation.
- **Terraform-managed OpenVPN** — Deploy OpenVPN instances via the OPNsense API through Terraform `null_resource` (native provider support is [not yet available](https://github.com/browningluke/terraform-provider-opnsense#current-api-coverage)).
- **SSH bastion support** — Tunnel through a bastion host to reach OPNsense in private networks.
- **Android deployment** — Push `.ovpn` / `.conf` files to Android via ADB, or generate QR codes for easy scanning.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [curl](https://curl.se/) + [python3](https://www.python.org/) (required for OpenVPN API provisioners)
- [adb](https://developer.android.com/tools/releases/platform-tools) (optional — for Android deployment)
- [qrencode](https://fukuchi.org/works/qrencode/) (optional — for QR code generation)
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
export TF_VAR_opnsense_uri="https://192.168.1.1"
export TF_VAR_opnsense_api_key="your-api-key"
export TF_VAR_opnsense_api_secret="your-api-secret"
```

### 2. Deploy VPN via Terraform

```bash
# Direct connection
./scripts/setup.sh --apply

# Through an SSH bastion host
export BASTION_HOST="bastion.example.com"
export BASTION_USER="admin"
./scripts/setup.sh --bastion --apply

# Or use Terraform directly
cd terraform
terraform init
terraform plan
terraform apply
```

After `terraform apply`, WireGuard client config files are automatically generated in the `configs/` directory. Replace `PEER_PRIVATE_KEY_HERE` in each `.conf` file with the peer's actual private key.

### 3. Manage VPN

All VPN changes are made by editing `terraform.tfvars` (or the `.tf` files) and running:

```bash
# Preview changes
./scripts/setup.sh --plan

# Apply changes
./scripts/setup.sh --apply

# Tear down everything
./scripts/setup.sh --destroy
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
│   ├── provider.tf                 # OPNsense + hashicorp providers
│   ├── variables.tf                # Input variables
│   ├── wireguard.tf                # WireGuard server and peer resources
│   ├── openvpn.tf                  # OpenVPN management via API (null_resource)
│   ├── configs.tf                  # Client config file generation (local_file)
│   ├── outputs.tf                  # Output values
│   └── terraform.tfvars.example    # Example variable values
├── scripts/                        # Helper scripts
│   ├── setup.sh                    # Bastion tunnel + terraform orchestration
│   └── deploy-android.sh           # Push configs to Android via ADB
├── configs/                        # Generated client configurations (via Terraform)
│   └── .gitkeep
├── .gitignore
└── README.md
```

## Security Notes

- **Never commit `terraform.tfvars`** — it contains API credentials. The `.gitignore` excludes it.
- **Generated configs contain private keys** — the `configs/` directory is gitignored except for `.gitkeep`.
- **API credentials** — Use OPNsense API keys with minimum required permissions.
- **SSH bastion** — Ensure your bastion host is properly hardened and uses key-based authentication.
