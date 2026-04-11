output "wg_server_public_key" {
  description = "WireGuard server public key"
  value       = opnsense_wireguard_server.vpn.public_key
}

output "wg_server_port" {
  description = "WireGuard server listen port"
  value       = opnsense_wireguard_server.vpn.port
}

output "wg_server_tunnel_address" {
  description = "WireGuard server tunnel address"
  value       = opnsense_wireguard_server.vpn.tunnel_address
}

output "wg_peer_ids" {
  description = "Map of WireGuard peer names to their resource IDs"
  value       = { for name, peer in opnsense_wireguard_client.peers : name => peer.id }
}

output "wg_peer_config_files" {
  description = "Paths to generated WireGuard peer configuration files"
  value       = { for name, f in local_file.wg_peer_configs : name => f.filename }
}

output "ovpn_enabled" {
  description = "Whether OpenVPN server was deployed"
  value       = var.ovpn_enabled
}
