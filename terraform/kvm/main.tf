# Kubernetes the Hard Way — lab environment on local KVM/libvirt
#
# Six VMs on this machine:
#
#   controlplane01  .11   etcd + kube-apiserver + controller-manager + scheduler,
#   controlplane02  .12     and (01 only) the admin workstation for the labs
#   controlplane03  .13
#   node01          .21   containerd + kubelet + kube-proxy
#   node02          .22
#   loadbalancer    .30   HAProxy in front of the three API servers
#
# The nodes sit on their own NAT network (192.168.100.0/24), reachable from
# this machine only. Every node's address is in /etc/hosts on every other node,
# and its own address reaches the labs as PRIMARY_IP in
# /etc/profile.d/kthw.sh.
#
# Sizing and addresses live in variables.tf.

locals {
  ssh_pubkey = trimspace(file(pathexpand(var.ssh_public_key_path)))
  prefix     = tonumber(split("/", var.network_cidr)[1])
  gateway    = cidrhost(var.network_cidr, 1)

  hosts_entries = join(" ", [for name, n in var.nodes : "'${n.ip} ${name}'"])

  image_path = "${pathexpand(var.image_cache_dir)}/${module.fedora_image.file_name}"
}

# The Fedora Cloud Base image and its checksum, from Fedora's release index.
module "fedora_image" {
  source = "../modules/fedora-image"

  fedora_release      = var.fedora_release
  fedora_releases_url = var.fedora_releases_url
  base_image_url      = var.base_image_url
  base_image_checksum = var.base_image_checksum
}

# Download the image once, into a cache on this machine, and check its SHA-256
# before anything uses it. libvirt will fetch a URL itself, but never checks
# what arrives -- and download.fedoraproject.org is a redirector, so the bytes
# come from whichever community mirror it picks.
#
# The file name carries the release and build (kthw-fedora-44-1.7.qcow2), so a
# new Fedora is a new download and a new base volume, never an overwrite of the
# one a running cluster is built on.
resource "terraform_data" "base_image" {
  triggers_replace = [module.fedora_image.url, module.fedora_image.sha256]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      URL    = module.fedora_image.url
      SHA256 = module.fedora_image.sha256
      FILE   = local.image_path
    }
    command = <<-EOT
      set -euo pipefail
      mkdir -p "$(dirname "$FILE")"
      if [ -f "$FILE" ] && echo "$SHA256  $FILE" | sha256sum -c --status; then
        echo "cached: $FILE"; exit 0
      fi
      curl -fL --retry 3 --progress-bar -o "$FILE.part" "$URL"
      echo "$SHA256  $FILE.part" | sha256sum -c -
      mv "$FILE.part" "$FILE"
    EOT
  }
}

resource "libvirt_network" "lab" {
  name      = var.network_name
  autostart = true
  forward   = { mode = "nat" }
  ips = [{
    address = local.gateway
    prefix  = local.prefix
  }]
  dns = { enable = "yes" }
}

resource "libvirt_pool" "lab" {
  name   = var.pool_name
  type   = "dir"
  target = { path = var.pool_path }
  # qcow2 on a copy-on-write filesystem (btrfs) fragments badly; libvirt sets
  # the directory NOCOW when the filesystem supports it, and ignores it
  # otherwise.
  features = { cow = { state = "no" } }
}

# The verified image, uploaded into the pool once. Every node's disk is an
# overlay on it.
resource "libvirt_volume" "base" {
  name       = module.fedora_image.file_name
  pool       = libvirt_pool.lab.name
  target     = { format = { type = "qcow2" } }
  create     = { content = { url = local.image_path } }
  depends_on = [terraform_data.base_image]
}

# A copy-on-write overlay on the base image, grown to disk_size_gb. cloud-init
# growpart expands the root filesystem into it on first boot.
resource "libvirt_volume" "disk" {
  for_each = var.nodes

  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.lab.name
  capacity = var.disk_size_gb * 1024 * 1024 * 1024
  target   = { format = { type = "qcow2" } }
  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = var.nodes

  name = "${each.key}-cloudinit"
  user_data = templatefile("${path.module}/../cloud-init/user-data.yaml.tftpl", {
    hostname      = each.key
    guest_user    = var.guest_user
    ssh_pubkey    = local.ssh_pubkey
    hosts_entries = local.hosts_entries
    primary_ip    = each.value.ip
  })
  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })
  # The static address, matched by the MAC the domain is given below, so it
  # does not depend on the image's NIC naming. The default route is written
  # 0.0.0.0/0, not "default": some cloud-init releases reject "default" as an
  # invalid address and drop the whole network config, and this network
  # serves no DHCP to fall back on.
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = {
        match       = { macaddress = each.value.mac }
        set-name    = "eth0"
        addresses   = ["${each.value.ip}/${local.prefix}"]
        routes      = [{ to = "0.0.0.0/0", via = local.gateway }]
        nameservers = { addresses = [local.gateway] }
      }
    }
  })
}

resource "libvirt_volume" "init" {
  for_each = var.nodes

  name   = "${each.key}-cloudinit.iso"
  pool   = libvirt_pool.lab.name
  create = { content = { url = libvirt_cloudinit_disk.init[each.key].path } }
}

resource "libvirt_domain" "node" {
  for_each = var.nodes

  name        = "kthw-${each.key}"
  type        = var.domain_type
  description = "Kubernetes the Hard Way — ${each.key}"
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.vcpu
  autostart   = true
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  # host-passthrough gives the guest the real CPU's features. Under TCG there
  # is no host CPU to pass through, so emulate the most capable model instead.
  cpu = var.domain_type == "kvm" ? { mode = "host-passthrough" } : { mode = "maximum" }

  # Not defaults here: a domain that does not ask for ACPI gets acpi=off, and a
  # q35 machine without it never gets past the BIOS.
  features = {
    acpi = true
    apic = {}
  }

  devices = {
    disks = [
      {
        source = { volume = { pool = libvirt_volume.disk[each.key].pool, volume = libvirt_volume.disk[each.key].name } }
        target = { bus = "virtio", dev = "vda" }
        driver = { type = "qcow2", discard = "unmap" }
      },
      {
        device = "cdrom"
        source = { volume = { pool = libvirt_volume.init[each.key].pool, volume = libvirt_volume.init[each.key].name } }
        target = { bus = "sata", dev = "sda" }
      },
    ]
    interfaces = [{
      type   = "network"
      model  = { type = "virtio" }
      mac    = { address = each.value.mac }
      source = { network = { network = libvirt_network.lab.name } }
    }]
    # `virsh console kthw-<node>` -- the way in if SSH never comes up.
    # Everything it prints is also kept in the log file, readable with sudo.
    consoles = [{
      target = { type = "serial", port = 0 }
      log    = { file = "/var/log/libvirt/qemu/kthw-${each.key}-console.log", append = "on" }
    }]
    # Required even with no display attached: with no video device at all a
    # q35 guest can hang in the BIOS.
    videos = [{ model = { type = "virtio", heads = 1, primary = "yes" } }]
    rngs   = [{ model = "virtio", backend = { random = "/dev/urandom" } }]
    # Free page reporting: memory a guest frees goes back to this host rather
    # than staying pinned to the VM.
    mem_balloon = {
      model               = "virtio"
      free_page_reporting = "on"
    }
    # The port Fedora's qemu-guest-agent listens on. Fedora Cloud ships the
    # agent, and its unit starts when this channel appears; with it,
    # `virsh domifaddr kthw-<node> --source agent` and clean shutdowns work.
    channels = [{
      source = { unix = { mode = "bind" } }
      target = { virt_io = { name = "org.qemu.guest_agent.0" } }
    }]
  }
}

# Written so `ssh controlplane01` works from anywhere once the Include line
# from Lab 2 is in ~/.ssh/config.
resource "local_file" "ssh_config" {
  filename        = "${path.module}/ssh_config"
  file_permission = "0644"

  content = join("\n", concat(
    ["# Generated by terraform. See Lab 2 for the one-line ~/.ssh/config include.", ""],
    flatten([
      for name, n in var.nodes : [
        "Host ${name}",
        "  HostName ${n.ip}",
        "  User ${var.guest_user}",
        "  IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}",
        "  IdentitiesOnly yes",
        "  StrictHostKeyChecking no",
        "  UserKnownHostsFile /dev/null",
        "  LogLevel ERROR",
        "",
      ]
    ])
  ))
}
