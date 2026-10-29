variable "port" {
  type    = number
  default = 2222
}

variable "valkey_password" {
  type      = string
  ephemeral = true
  sensitive = true
}

module "valkey" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  password         = var.valkey_password
  maxmemory        = "64mb"
  maxmemory_policy = "allkeys-lru"
  aof              = true
}
