#!/usr/bin/env bash
#
# setup.sh - Main setup script for OPNsense VPN deployment.
#
# Establishes an SSH tunnel through a bastion host (if configured),
# then runs Terraform to deploy VPN configuration.
#
# Usage: ./setup.sh [--bastion] [--apply] [--destroy] [--plan]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"

# Default values
USE_BASTION=false
ACTION=""

# SSH tunnel PID (for cleanup)
SSH_TUNNEL_PID=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --bastion         Use SSH bastion host to tunnel to OPNsense
  --plan            Run terraform plan to preview changes
  --apply           Run terraform apply to deploy VPN
  --destroy         Run terraform destroy to remove VPN
  -h, --help        Show this help message

Environment Variables (or set in terraform.tfvars):
  OPNSENSE_URI            OPNsense host URI
  OPNSENSE_API_KEY        OPNsense API key
  OPNSENSE_API_SECRET     OPNsense API secret
  BASTION_HOST            SSH bastion hostname
  BASTION_USER            SSH bastion username
  BASTION_PORT            SSH bastion port (default: 22)

Examples:
  # Preview changes
  ./setup.sh --plan

  # Deploy VPN through a bastion host
  ./setup.sh --bastion --apply

  # Tear down VPN
  ./setup.sh --destroy
EOF
}

cleanup() {
  if [[ -n "$SSH_TUNNEL_PID" ]] && kill -0 "$SSH_TUNNEL_PID" 2>/dev/null; then
    echo "Closing SSH tunnel (PID: $SSH_TUNNEL_PID)..."
    kill "$SSH_TUNNEL_PID" 2>/dev/null || true
    wait "$SSH_TUNNEL_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

start_bastion_tunnel() {
  local bastion_host="${BASTION_HOST:-}"
  local bastion_user="${BASTION_USER:-}"
  local bastion_port="${BASTION_PORT:-22}"
  local opnsense_uri="${OPNSENSE_URI:-}"

  if [[ -z "$bastion_host" || -z "$bastion_user" ]]; then
    echo "Error: BASTION_HOST and BASTION_USER must be set for bastion mode."
    exit 1
  fi

  # Extract OPNsense host and port from URI
  local opn_host opn_port
  opn_host=$(echo "$opnsense_uri" | sed -E 's|https?://||' | cut -d: -f1)
  opn_port=$(echo "$opnsense_uri" | sed -E 's|https?://||' | grep -oE ':[0-9]+' | tr -d ':')
  opn_port="${opn_port:-443}"

  local local_port=8443

  echo "Opening SSH tunnel: localhost:${local_port} -> ${opn_host}:${opn_port} via ${bastion_user}@${bastion_host}:${bastion_port}..."
  ssh -f -N -L "${local_port}:${opn_host}:${opn_port}" \
    -p "$bastion_port" \
    "${bastion_user}@${bastion_host}" &
  SSH_TUNNEL_PID=$!

  # Wait for tunnel to be ready
  sleep 2
  if ! kill -0 "$SSH_TUNNEL_PID" 2>/dev/null; then
    echo "Error: SSH tunnel failed to start."
    exit 1
  fi

  echo "SSH tunnel established (PID: $SSH_TUNNEL_PID)."
  # Override the OPNsense URI to use the local tunnel
  export TF_VAR_opnsense_uri="https://localhost:${local_port}"
}

run_terraform() {
  local action="$1"

  cd "$TF_DIR"

  # Pass environment variables to Terraform if set
  # Skip URI override if bastion tunnel is active (already set by start_bastion_tunnel)
  if [[ "$USE_BASTION" = false && -n "${OPNSENSE_URI:-}" ]]; then
    export TF_VAR_opnsense_uri="$OPNSENSE_URI"
  fi
  [[ -n "${OPNSENSE_API_KEY:-}" ]] && export TF_VAR_opnsense_api_key="$OPNSENSE_API_KEY"
  [[ -n "${OPNSENSE_API_SECRET:-}" ]] && export TF_VAR_opnsense_api_secret="$OPNSENSE_API_SECRET"

  echo "Initializing Terraform..."
  terraform init -input=false

  case "$action" in
    plan)
      echo "Planning Terraform changes..."
      terraform plan
      ;;
    apply)
      echo "Planning Terraform changes..."
      terraform plan -out=tfplan
      echo "Applying Terraform changes..."
      terraform apply tfplan
      rm -f tfplan
      echo ""
      echo "Client configs generated in configs/ directory."
      echo "Replace PEER_PRIVATE_KEY_HERE with each peer's actual private key."
      ;;
    destroy)
      echo "Destroying Terraform resources..."
      terraform destroy -auto-approve
      ;;
  esac

  cd "$ROOT_DIR"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bastion)
      USE_BASTION=true
      shift
      ;;
    --plan)
      ACTION="plan"
      shift
      ;;
    --apply)
      ACTION="apply"
      shift
      ;;
    --destroy)
      ACTION="destroy"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Error: No action specified. Use --plan, --apply, or --destroy."
  usage
  exit 1
fi

# Start bastion tunnel if requested
if [[ "$USE_BASTION" = true ]]; then
  start_bastion_tunnel
fi

# Run Terraform action
run_terraform "$ACTION"

echo "Done."
