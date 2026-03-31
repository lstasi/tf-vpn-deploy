## OPNsense Connection

variable "opnsense_uri" {
  description = "OPNsense host URI (e.g. https://192.168.1.1)"
  type        = string
}

variable "opnsense_api_key" {
  description = "OPNsense API key"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "OPNsense API secret"
  type        = string
  sensitive   = true
}

variable "opnsense_allow_insecure" {
  description = "Allow insecure HTTPS connections to OPNsense"
  type        = bool
  default     = false
}

## SSH Bastion

variable "bastion_host" {
  description = "SSH bastion host for tunneling to OPNsense"
  type        = string
  default     = ""
}

variable "bastion_user" {
  description = "SSH user for the bastion host"
  type        = string
  default     = ""
}

variable "bastion_port" {
  description = "SSH port for the bastion host"
  type        = number
  default     = 22
}

## WireGuard

variable "wg_server_name" {
  description = "WireGuard server instance name"
  type        = string
  default     = "wg0"
}

variable "wg_listen_port" {
  description = "WireGuard listen port"
  type        = number
  default     = 51820
}

variable "wg_tunnel_address" {
  description = "WireGuard tunnel address CIDR (e.g. 10.10.0.1/24)"
  type        = string
  default     = "10.10.0.1/24"
}

variable "wg_dns" {
  description = "DNS servers for WireGuard clients"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "wg_peers" {
  description = "Map of WireGuard peer configurations"
  type = map(object({
    public_key     = string
    tunnel_address = list(string)
    keepalive      = optional(number, 25)
  }))
  default = {}
}
