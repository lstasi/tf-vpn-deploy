#!/usr/bin/env bash
#
# wireguard-manage.sh - Manage WireGuard on OPNsense via its API.
#
# Provides commands to manage WireGuard server and peers,
# generate keys, and export client configuration files.
#
# Usage: ./wireguard-manage.sh <command> [options]

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
  list-servers              List WireGuard server instances
  list-peers                List WireGuard peers (clients)
  gen-keys                  Generate a new WireGuard keypair
  add-peer [options]        Add a new WireGuard peer
  remove-peer --id <id>     Remove a WireGuard peer
  export-configs            Export all peer configurations (.conf files)
  export-config --name <n>  Export a single peer configuration
  status                    Show WireGuard service status
  start                     Start WireGuard service
  stop                      Stop WireGuard service
  restart                   Restart WireGuard service
  apply                     Apply pending WireGuard configuration

Add Peer Options:
  --name <name>             Peer name (required)
  --pubkey <key>            Peer public key (auto-generated if omitted)
  --address <cidr>          Peer tunnel address (e.g. 10.10.0.2/32)
  --keepalive <seconds>     Persistent keepalive interval (default: 25)

Environment Variables:
  OPNSENSE_URI         OPNsense host URI (default: https://192.168.1.1)
  OPNSENSE_API_KEY     OPNsense API key
  OPNSENSE_API_SECRET  OPNsense API secret
  OPNSENSE_INSECURE    Allow insecure HTTPS (default: false)
  WG_ENDPOINT          WireGuard server public endpoint (host:port)

Examples:
  # List all peers
  ./wireguard-manage.sh list-peers

  # Generate a keypair for a new peer
  ./wireguard-manage.sh gen-keys

  # Add a peer
  ./wireguard-manage.sh add-peer --name phone --address 10.10.0.2/32

  # Export all configs
  ./wireguard-manage.sh export-configs
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
  echo "Fetching WireGuard server instances..."
  local result
  result=$(api_request GET "/wireguard/server/searchServer")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

list_peers() {
  echo "Fetching WireGuard peers..."
  local result
  result=$(api_request GET "/wireguard/client/searchClient")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

gen_keys() {
  if command -v wg &>/dev/null; then
    local privkey pubkey
    privkey=$(wg genkey)
    pubkey=$(echo "$privkey" | wg pubkey)
    echo "Private Key: $privkey"
    echo "Public Key:  $pubkey"
  else
    echo "Generating keys via OPNsense API..."
    local result
    result=$(api_request GET "/wireguard/server/keyPair")
    echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
  fi
}

add_peer() {
  local name="" pubkey="" address="" keepalive=25

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --pubkey) pubkey="$2"; shift 2 ;;
      --address) address="$2"; shift 2 ;;
      --keepalive) keepalive="$2"; shift 2 ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done

  if [[ -z "$name" || -z "$address" ]]; then
    echo "Error: --name and --address are required."
    exit 1
  fi

  # Generate keys if not provided
  if [[ -z "$pubkey" ]]; then
    if command -v wg &>/dev/null; then
      local privkey
      privkey=$(wg genkey)
      pubkey=$(echo "$privkey" | wg pubkey)
      echo "Generated keypair for peer '$name':"
      echo "  Private Key: $privkey"
      echo "  Public Key:  $pubkey"
      echo "  (Save the private key - you'll need it for the client config)"
    else
      echo "Error: --pubkey is required when 'wg' tool is not installed."
      exit 1
    fi
  fi

  echo "Adding WireGuard peer '$name'..."
  local data
  data=$(cat <<EOJSON
{
  "client": {
    "enabled": "1",
    "name": "$name",
    "pubkey": "$pubkey",
    "tunneladdress": "$address",
    "keepalive": "$keepalive"
  }
}
EOJSON
)

  local result
  result=$(api_request POST "/wireguard/client/addClient" "$data")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"

  echo "Applying configuration..."
  apply_config
}

remove_peer() {
  local peer_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) peer_id="$2"; shift 2 ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done

  if [[ -z "$peer_id" ]]; then
    echo "Error: --id is required."
    exit 1
  fi

  echo "Removing WireGuard peer '$peer_id'..."
  local result
  result=$(api_request POST "/wireguard/client/delClient/$peer_id")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"

  echo "Applying configuration..."
  apply_config
}

export_single_config() {
  local name="$1"
  local endpoint="${WG_ENDPOINT:-}"

  echo "Fetching server info..."
  local server_info
  server_info=$(api_request GET "/wireguard/server/searchServer")

  local server_pubkey server_port
  server_pubkey=$(echo "$server_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
rows = data.get('rows', [])
if rows:
    print(rows[0].get('pubkey', ''))
" 2>/dev/null || echo "SERVER_PUBLIC_KEY")

  server_port=$(echo "$server_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
rows = data.get('rows', [])
if rows:
    print(rows[0].get('port', '51820'))
" 2>/dev/null || echo "51820")

  echo "Fetching peer info for '$name'..."
  local peers_info
  peers_info=$(api_request GET "/wireguard/client/searchClient")

  local peer_address
  peer_address=$(echo "$peers_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
rows = data.get('rows', [])
for row in rows:
    if row.get('name') == '$name':
        print(row.get('tunneladdress', ''))
        break
" 2>/dev/null || echo "PEER_ADDRESS")

  if [[ -z "$endpoint" ]]; then
    endpoint="${OPNSENSE_URI##*://}:${server_port}"
  fi

  mkdir -p "$CONFIG_DIR"
  local output_file="$CONFIG_DIR/wg-${name}.conf"

  cat > "$output_file" <<EOCONF
[Interface]
# Peer: ${name}
PrivateKey = PEER_PRIVATE_KEY_HERE
Address = ${peer_address}
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${server_pubkey}
Endpoint = ${endpoint}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOCONF

  echo "WireGuard config exported to: $output_file"
  echo "Note: Replace PEER_PRIVATE_KEY_HERE with the peer's private key."
}

export_all_configs() {
  echo "Fetching all WireGuard peers..."
  local peers_info
  peers_info=$(api_request GET "/wireguard/client/searchClient")

  local peer_names
  peer_names=$(echo "$peers_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    print(row.get('name', ''))
" 2>/dev/null)

  if [[ -z "$peer_names" ]]; then
    echo "No WireGuard peers found."
    return
  fi

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    export_single_config "$name"
  done <<< "$peer_names"
}

service_action() {
  local action="$1"
  echo "${action^}ing WireGuard service..."
  local result
  result=$(api_request POST "/wireguard/service/${action}")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

get_status() {
  echo "Fetching WireGuard service status..."
  local result
  result=$(api_request GET "/wireguard/service/show")
  echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
}

apply_config() {
  echo "Reconfiguring WireGuard..."
  local result
  result=$(api_request POST "/wireguard/service/reconfigure")
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
  list-peers)
    list_peers
    ;;
  gen-keys)
    gen_keys
    ;;
  add-peer)
    add_peer "$@"
    ;;
  remove-peer)
    remove_peer "$@"
    ;;
  export-configs)
    export_all_configs
    ;;
  export-config)
    PEER_NAME=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name) PEER_NAME="$2"; shift 2 ;;
        *) PEER_NAME="$1"; shift ;;
      esac
    done
    if [[ -z "$PEER_NAME" ]]; then
      echo "Error: --name is required for export-config."
      exit 1
    fi
    export_single_config "$PEER_NAME"
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
  apply)
    apply_config
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
