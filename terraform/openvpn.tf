# OpenVPN management via OPNsense API.
#
# The browningluke/opnsense provider does not yet support OpenVPN resources
# (see: https://github.com/browningluke/terraform-provider-opnsense#current-api-coverage).
#
# This file uses null_resource + local-exec provisioners to manage OpenVPN
# through the OPNsense REST API, keeping everything in Terraform state.
# When the provider adds OpenVPN support, these should be migrated to native resources.

resource "null_resource" "openvpn_instance" {
  count = var.ovpn_enabled ? 1 : 0

  triggers = {
    server_name    = var.ovpn_server_name
    mode           = var.ovpn_mode
    protocol       = var.ovpn_protocol
    port           = var.ovpn_port
    tunnel_network = var.ovpn_tunnel_network
    opnsense_uri   = var.opnsense_uri
    allow_insecure = var.opnsense_allow_insecure
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      INSECURE_FLAG=""
      if [ "${var.opnsense_allow_insecure}" = "true" ]; then
        INSECURE_FLAG="-k"
      fi

      # Search for existing instance by description
      EXISTING=$(curl -s $INSECURE_FLAG \
        -u "${var.opnsense_api_key}:${var.opnsense_api_secret}" \
        "${var.opnsense_uri}/api/openvpn/instances/search" | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    if row.get('description', '') == '${var.ovpn_server_name}':
        print(row.get('uuid', ''))
        break
" 2>/dev/null || echo "")

      if [ -n "$EXISTING" ]; then
        echo "OpenVPN instance '${var.ovpn_server_name}' already exists (UUID: $EXISTING). Updating..."
        METHOD="POST"
        URL="${var.opnsense_uri}/api/openvpn/instances/setInstance/$EXISTING"
      else
        echo "Creating OpenVPN instance '${var.ovpn_server_name}'..."
        METHOD="POST"
        URL="${var.opnsense_uri}/api/openvpn/instances/addInstance"
      fi

      RESULT=$(curl -s $INSECURE_FLAG \
        -u "${var.opnsense_api_key}:${var.opnsense_api_secret}" \
        -X $METHOD -H "Content-Type: application/json" \
        -d '{
          "instance": {
            "enabled": "1",
            "role": "server",
            "description": "${var.ovpn_server_name}",
            "proto": "${var.ovpn_protocol}",
            "port": "${var.ovpn_port}",
            "dev_type": "${var.ovpn_mode}",
            "tunnel_network": "${var.ovpn_tunnel_network}",
            "local_group": "",
            "crypto": "",
            "cert": "",
            "ca": ""
          }
        }' "$URL")

      echo "API response: $RESULT"

      # Apply the configuration
      curl -s $INSECURE_FLAG \
        -u "${var.opnsense_api_key}:${var.opnsense_api_secret}" \
        -X POST "${var.opnsense_uri}/api/openvpn/service/reconfigure" > /dev/null

      echo "OpenVPN instance configured."
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      INSECURE_FLAG=""
      if [ "${self.triggers.allow_insecure}" = "true" ]; then
        INSECURE_FLAG="-k"
      fi

      # Find the instance UUID by description
      UUID=$(curl -s $INSECURE_FLAG \
        -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
        "${self.triggers.opnsense_uri}/api/openvpn/instances/search" | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    if row.get('description', '') == '${self.triggers.server_name}':
        print(row.get('uuid', ''))
        break
" 2>/dev/null || echo "")

      if [ -n "$UUID" ]; then
        echo "Removing OpenVPN instance '${self.triggers.server_name}' (UUID: $UUID)..."
        curl -s $INSECURE_FLAG \
          -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
          -X POST "${self.triggers.opnsense_uri}/api/openvpn/instances/delInstance/$UUID" > /dev/null

        curl -s $INSECURE_FLAG \
          -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
          -X POST "${self.triggers.opnsense_uri}/api/openvpn/service/reconfigure" > /dev/null

        echo "OpenVPN instance removed."
      else
        echo "OpenVPN instance '${self.triggers.server_name}' not found. Nothing to remove."
      fi
    EOT

    environment = {
      OPNSENSE_API_KEY    = var.opnsense_api_key
      OPNSENSE_API_SECRET = var.opnsense_api_secret
    }
  }
}
