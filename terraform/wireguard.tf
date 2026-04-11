resource "opnsense_wireguard_client" "peers" {
  for_each = var.wg_peers

  name       = each.key
  public_key = each.value.public_key
  tunnel_address = each.value.tunnel_address
  keepalive  = each.value.keepalive
}

resource "opnsense_wireguard_server" "vpn" {
  name           = var.wg_server_name
  port           = var.wg_listen_port
  tunnel_address = [var.wg_tunnel_address]
  dns            = var.wg_dns
  peers          = [for peer in opnsense_wireguard_client.peers : peer.id]
}
