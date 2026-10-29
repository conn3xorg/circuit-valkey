# Facts give each host's distribution, which picks the package and the
# systemd unit. Every supported distribution ships Valkey in its own
# repositories.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os     = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  family = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) ? "debian" : "redhat" }

  redhat_hosts = { for name, h in var.hosts : name => h if local.family[name] == "redhat" }

  # Debian and Ubuntu name the package and the unit valkey-server; the Red
  # Hat family calls both valkey.
  service = { for name, f in local.family : name => f == "debian" ? "valkey-server" : "valkey" }

  # Owned as the package owns valkey.conf. On the Red Hat family a
  # tmpfiles rule resets everything in /etc/valkey to valkey:root at boot.
  group = { for name, f in local.family : name => f == "debian" ? "valkey" : "root" }

  main_file   = "/etc/valkey/valkey.conf"
  config_file = "/etc/valkey/conn3x.conf"
  auth_file   = "/etc/valkey/conn3x-auth.conf"

  # Valkey reads an include where it appears and a later setting wins, so
  # this file goes last in valkey.conf and the password file last in this.
  # The save points are Valkey's own defaults. dir is spelt out because
  # Rocky Linux's valkey.conf says ./ and leans on the unit's working
  # directory.
  config = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    bind ${join(" ", var.bind)}
    port ${var.port}
    maxmemory ${var.maxmemory}
    maxmemory-policy ${var.maxmemory_policy}
    dir /var/lib/valkey
    save ${var.rdb ? "3600 1 300 100 60 10000" : "\"\""}
    appendonly ${var.aof ? "yes" : "no"}
    include ${local.auth_file}
    EOT

  # Inside double quotes Valkey reads \\ and \" as escapes, so any password
  # without a line break comes through as typed.
  auth = "requirepass \"${replace(replace(var.password, "\\", "\\\\"), "\"", "\\\"")}\"\n"
}

# SELinux only lets Valkey bind ports labelled redis_port_t, which 6379
# already is. Another port gets the label here, on hosts where SELinux is on.
circuit "valkey_selinux" {
  hosts = local.redhat_hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "semanage" {
    for_each = var.port == 6379 ? [] : ["policycoreutils-python-utils"]
    package {
      name = item.value
    }
  }

  step "port" {
    for_each = var.port == 6379 ? [] : [tostring(var.port)]
    command {
      command = "semanage port -a -t redis_port_t -p tcp ${item.value} || semanage port -m -t redis_port_t -p tcp ${item.value}"
      unless  = "! selinuxenabled || semanage port -l | awk '$1 == \"redis_port_t\" && $2 == \"tcp\"' | grep -qw ${item.value}"
    }
  }
}

circuit "valkey" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "server" {
    package {
      name = local.service[each.key]
    }
  }

  # Upstream's advice: without it, the fork behind a background save or an
  # AOF rewrite can fail under memory pressure, and Valkey warns at start.
  step "overcommit" {
    sysctl {
      name  = "vm.overcommit_memory"
      value = "1"
    }
  }

  step "config" {
    depends_on = [conn3x_package.valkey__server]
    file {
      path    = local.config_file
      content = local.config
      owner   = "valkey"
      group   = local.group[each.key]
      mode    = "0640"
    }
  }

  # The password lands in a file only Valkey and root can read, never in
  # state or the plan.
  step "auth" {
    depends_on = [conn3x_package.valkey__server]
    file {
      path       = local.auth_file
      content_wo = local.auth
      owner      = "valkey"
      group      = local.group[each.key]
      mode       = "0640"
    }
  }

  # The distribution's valkey.conf stays as packaged apart from this line,
  # so its own defaults still apply to anything not set here.
  step "include" {
    line {
      path   = local.main_file
      regexp = "^include ${replace(local.config_file, ".", "\\.")}$"
      line   = "include ${local.config_file}"
    }
  }

  # Valkey has no reload; bind, port and the password only change on a
  # restart. It runs here rather than in a handler so the service step
  # below finds it running with the new settings. A restart saves the
  # dataset first when persistence is on, and loads it again on start.
  step "restart" {
    depends_on = [conn3x_command.valkey_selinux__port, conn3x_sysctl.valkey__overcommit]
    command {
      command = "systemctl restart ${local.service[each.key]}"
      triggers = {
        config  = conn3x_file.valkey__config[each.key].revision
        auth    = conn3x_file.valkey__auth[each.key].revision
        include = conn3x_line.valkey__include[each.key].revision
      }
    }
  }

  step "running" {
    service {
      name    = local.service[each.key]
      state   = "started"
      enabled = true
    }
  }
}
