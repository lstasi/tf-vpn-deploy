# Generate WireGuard client configuration files.
#
# Produces a .conf file for each peer, ready to import into the WireGuard app.
# After `terraform apply`, find the configs in the configs/ directory.

resource "local_file" "wg_peer_configs" {
  for_each = var.wg_peers

  filename        = "${path.module}/../configs/wg-${each.key}.conf"
  file_permission = "0600"

  content = <<-EOCONF
[Interface]
# Peer: ${each.key}
PrivateKey = PEER_PRIVATE_KEY_HERE
Address = ${join(", ", each.value.tunnel_address)}
DNS = ${join(", ", var.wg_dns)}

[Peer]
PublicKey = ${opnsense_wireguard_server.vpn.public_key}
Endpoint = ${var.wg_endpoint}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = ${each.value.keepalive}
EOCONF
}
