output "config_file" {
  description = "Path of the settings file the circuit writes on each host and includes from valkey.conf."
  value       = local.config_file
}

output "services" {
  description = "systemd unit running Valkey on each host, by host name."
  value       = local.service
}
