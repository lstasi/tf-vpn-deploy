#!/usr/bin/env bash
#
# deploy-android.sh - Deploy VPN configs to an Android device via ADB.
#
# Pushes OpenVPN (.ovpn) or WireGuard (.conf) configuration files
# to an Android device, or generates QR codes for easy scanning.
#
# Usage: ./deploy-android.sh <command> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/configs"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  push [--file <path>]      Push VPN config to Android device via ADB
  push-all                  Push all configs from configs/ directory
  qr [--file <path>]        Display QR code for a WireGuard config
  list                      List available config files
  check                     Check if ADB is connected and device is available

Push Options:
  --file <path>             Path to the config file to push
  --dest <path>             Destination on device (default: /sdcard/Download/)

Prerequisites:
  - adb (Android Debug Bridge) must be installed and on PATH
  - Device must be connected via USB or network (adb connect)
  - For QR codes: qrencode must be installed

Examples:
  # Check device connectivity
  ./deploy-android.sh check

  # Push a specific config
  ./deploy-android.sh push --file configs/wg-phone.conf

  # Push all config files
  ./deploy-android.sh push-all

  # Show QR code for WireGuard config
  ./deploy-android.sh qr --file configs/wg-phone.conf
EOF
}

check_adb() {
  if ! command -v adb &>/dev/null; then
    echo "Error: 'adb' is not installed or not on PATH."
    echo "Install Android SDK Platform Tools:"
    echo "  macOS:   brew install android-platform-tools"
    echo "  Linux:   sudo apt install adb"
    echo "  Windows: Download from https://developer.android.com/tools/releases/platform-tools"
    exit 1
  fi

  local devices
  devices=$(adb devices | grep -Ecv "^(List|$)")
  if [[ "$devices" -eq 0 ]]; then
    echo "Error: No Android device connected."
    echo "Connect a device via USB or run: adb connect <ip>:<port>"
    exit 1
  fi

  echo "Android device detected:"
  adb devices -l | grep -v "^List" | grep -v "^$"
}

push_file() {
  local file="$1"
  local dest="${2:-/sdcard/Download/}"

  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file"
    exit 1
  fi

  check_adb

  local filename
  filename=$(basename "$file")

  echo "Pushing '$filename' to device at '${dest}'..."
  adb push "$file" "${dest}${filename}"
  echo "File pushed successfully."

  # Detect file type and suggest app
  case "$filename" in
    *.ovpn)
      echo ""
      echo "To import in OpenVPN Connect:"
      echo "  1. Open OpenVPN Connect app"
      echo "  2. Tap the + button or Import"
      echo "  3. Select 'File' tab"
      echo "  4. Navigate to Downloads and select '$filename'"
      ;;
    *.conf)
      echo ""
      echo "To import in WireGuard app:"
      echo "  1. Open WireGuard app"
      echo "  2. Tap the + button"
      echo "  3. Select 'Import from file or archive'"
      echo "  4. Navigate to Downloads and select '$filename'"
      ;;
  esac
}

push_all() {
  check_adb

  local count=0
  for file in "$CONFIG_DIR"/*.ovpn "$CONFIG_DIR"/*.conf; do
    [[ -f "$file" ]] || continue
    local filename
    filename=$(basename "$file")
    echo "Pushing '$filename'..."
    adb push "$file" "/sdcard/Download/${filename}"
    count=$((count + 1))
  done

  if [[ "$count" -eq 0 ]]; then
    echo "No .ovpn or .conf files found in $CONFIG_DIR/"
    echo "Run the export commands first to generate configuration files."
    exit 1
  fi

  echo ""
  echo "Pushed $count config file(s) to /sdcard/Download/ on the device."
}

show_qr() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file"
    exit 1
  fi

  if ! command -v qrencode &>/dev/null; then
    echo "Error: 'qrencode' is not installed."
    echo "Install it with:"
    echo "  macOS:   brew install qrencode"
    echo "  Linux:   sudo apt install qrencode"
    exit 1
  fi

  echo "QR code for: $(basename "$file")"
  echo "Scan this with the WireGuard app on your phone:"
  echo ""
  qrencode -t ansiutf8 < "$file"
}

list_configs() {
  echo "Available config files in $CONFIG_DIR/:"
  echo ""
  local count=0
  for file in "$CONFIG_DIR"/*.ovpn "$CONFIG_DIR"/*.conf; do
    [[ -f "$file" ]] || continue
    local filename size
    filename=$(basename "$file")
    size=$(wc -c < "$file")
    printf "  %-30s %s bytes\n" "$filename" "$size"
    count=$((count + 1))
  done

  if [[ "$count" -eq 0 ]]; then
    echo "  (no config files found)"
    echo ""
    echo "Generate configs with:"
    echo "  ./wireguard-manage.sh export-configs"
    echo "  ./openvpn-manage.sh export-config --name <client>"
  fi
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  push)
    FILE=""
    DEST="/sdcard/Download/"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file) FILE="$2"; shift 2 ;;
        --dest) DEST="$2"; shift 2 ;;
        *) FILE="$1"; shift ;;
      esac
    done
    if [[ -z "$FILE" ]]; then
      echo "Error: --file is required."
      exit 1
    fi
    push_file "$FILE" "$DEST"
    ;;
  push-all)
    push_all
    ;;
  qr)
    FILE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file) FILE="$2"; shift 2 ;;
        *) FILE="$1"; shift ;;
      esac
    done
    if [[ -z "$FILE" ]]; then
      echo "Error: --file is required."
      exit 1
    fi
    show_qr "$FILE"
    ;;
  list)
    list_configs
    ;;
  check)
    check_adb
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
