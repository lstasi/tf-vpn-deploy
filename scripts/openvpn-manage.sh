#!/usr/bin/env bash
#
# openvpn-manage.sh - Manage OpenVPN on OPNsense via its API.
#
# Provides commands to list, create, and export OpenVPN server/client
# configurations from an OPNsense firewall.
#
# Usage: ./openvpn-manage.sh <command> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/configs"

# OPNsense connection (override via environment)
OPNSENSE_URI="${OPNSENSE_URI:-https://192.168.1.1}"
OPNSENSE_API_KEY="${OPNSENSE_API_KEY:-}"
OPNSENSE_API_SECRET="${OPNSENSE_API_SECRET:-}"
OPNSENSE_INSECURE="${OPNSENSE_INSECURE:-false}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  list-servers             List OpenVPN server instances
  list-clients             List OpenVPN client configurations
  export-config [--name]   Export OpenVPN client config (.ovpn file)
  status                   Show OpenVPN service status
  start                    Start OpenVPN service
  stop                     Stop OpenVPN service
  restart                  Restart OpenVPN service

Environment Variables:
  OPNSENSE_URI         OPNsense host URI (default: https://192.168.1.1)
  OPNSENSE_API_KEY     OPNsense API key
  OPNSENSE_API_SECRET  OPNsense API secret
  OPNSENSE_INSECURE    Allow insecure HTTPS (default: false)

Examples:
  # List all OpenVPN servers
  ./openvpn-manage.sh list-servers

  # Export client config
  ./openvpn-manage.sh export-config --name my-phone

  # Restart OpenVPN service
  ./openvpn-manage.sh restart
EOF
}

# Build curl options for OPNsense API calls
curl_opts() {
  local opts=(-s -w $'\n%{http_code}')
  if [[ "$OPNSENSE_INSECURE" = true ]]; then
    opts+=(-k)
  fi
  if [[ -n "$OPNSENSE_API_KEY" && -n "$OPNSENSE_API_SECRET" ]]; then
    opts+=(-u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}")
  fi
  echo "${opts[@]}"
}

# Make an API request to OPNsense
api_request() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local url="${OPNSENSE_URI}/api${endpoint}"
  local opts
  read -ra opts <<< "$(curl_opts)"

  local response
  if [[ "$method" == "GET" ]]; then
    response=$(curl "${opts[@]}" -X GET "$url")
  else
    response=$(curl "${opts[@]}" -X POST -H "Content-Type: application/json" -d "$data" "$url")
  fi

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "Error: API request failed with HTTP $http_code" >&2
    echo "$body" >&2
    return 1
  fi

  echo "$body"
}

list_servers() {
  echo "Fetching OpenVPN server instances..."
  local result
  result=$(api_request GET "/openvpn/instances/search")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

list_clients() {
  echo "Fetching OpenVPN client configurations..."
  local result
  result=$(api_request GET "/openvpn/export/accounts")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

export_config() {
  local client_name="${1:-}"
  if [[ -z "$client_name" ]]; then
    echo "Error: --name is required for export-config."
    echo "Usage: $(basename "$0") export-config --name <client-name>"
    exit 1
  fi

  echo "Exporting OpenVPN config for client '$client_name'..."
  local result
  result=$(api_request GET "/openvpn/export/download/${client_name}")

  local output_file="$CONFIG_DIR/${client_name}.ovpn"
  mkdir -p "$CONFIG_DIR"
  echo "$result" > "$output_file"
  echo "OpenVPN config exported to: $output_file"
}

service_action() {
  local action="$1"  # start, stop, restart
  echo "${action^}ing OpenVPN service..."
  local result
  result=$(api_request POST "/openvpn/service/${action}")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

get_status() {
  echo "Fetching OpenVPN service status..."
  local result
  result=$(api_request GET "/openvpn/service/status")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  list-servers)
    list_servers
    ;;
  list-clients)
    list_clients
    ;;
  export-config)
    CLIENT_NAME=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name)
          CLIENT_NAME="$2"
          shift 2
          ;;
        *)
          CLIENT_NAME="$1"
          shift
          ;;
      esac
    done
    export_config "$CLIENT_NAME"
    ;;
  status)
    get_status
    ;;
  start)
    service_action "start"
    ;;
  stop)
    service_action "stop"
    ;;
  restart)
    service_action "restart"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac
