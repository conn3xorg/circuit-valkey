variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "centos", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel, centos or fedora."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "bind" {
  type        = list(string)
  default     = ["127.0.0.1", "-::1"]
  description = "Addresses Valkey listens on, such as [\"0.0.0.0\"] or [\"127.0.0.1\", \"10.0.0.5\"]. A leading - lets Valkey start when that address isn't there. Changing it restarts Valkey."

  validation {
    condition     = length(var.bind) > 0 && alltrue([for a in var.bind : can(regex("^-?(\\*|[0-9A-Fa-f.:]+)$", a))])
    error_message = "bind needs at least one IP address, such as \"0.0.0.0\" or \"::1\", optionally with a leading -, or \"*\"."
  }
}

variable "port" {
  type        = number
  default     = 6379
  description = "TCP port Valkey listens on. Changing it restarts Valkey."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a port number from 1 to 65535."
  }
}

variable "password" {
  type        = string
  ephemeral   = true
  sensitive   = true
  nullable    = false
  description = "Password every client must give with AUTH, set as requirepass for the default user. Pass it at run time with -var or TF_VAR_password; it never reaches state or the plan."

  validation {
    condition     = length(var.password) > 0 && !can(regex("[\\r\\n]", var.password))
    error_message = "password can't be empty or contain a line break."
  }
}

variable "maxmemory" {
  type        = string
  default     = "0"
  description = "Memory Valkey may use for data before maxmemory_policy applies, such as \"256mb\" or \"2gb\". \"0\" means no limit."

  validation {
    condition     = can(regex("^[0-9]+([kmg]b?)?$", lower(var.maxmemory)))
    error_message = "maxmemory must be a number of bytes, optionally with a unit, such as \"0\", \"512mb\" or \"2gb\"."
  }
}

variable "maxmemory_policy" {
  type        = string
  default     = "noeviction"
  description = "What Valkey does at maxmemory: noeviction refuses writes; allkeys-lru and the others evict keys, which suits a cache."

  validation {
    condition     = contains(["noeviction", "allkeys-lru", "allkeys-lfu", "allkeys-random", "volatile-lru", "volatile-lfu", "volatile-random", "volatile-ttl"], var.maxmemory_policy)
    error_message = "maxmemory_policy must be one of noeviction, allkeys-lru, allkeys-lfu, allkeys-random, volatile-lru, volatile-lfu, volatile-random or volatile-ttl."
  }
}

variable "rdb" {
  type        = bool
  default     = true
  description = "Save RDB snapshots to /var/lib/valkey/dump.rdb, on Valkey's default save points and on shutdown, so data survives a restart."
}

variable "aof" {
  type        = bool
  default     = false
  description = "Log every write to the append-only file in /var/lib/valkey, fsynced once a second, so at most a second of writes is lost in a crash."
}
