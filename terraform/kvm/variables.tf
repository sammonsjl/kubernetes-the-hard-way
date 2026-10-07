variable "libvirt_uri" {
  description = "The libvirt instance the VMs are created in. The system one: a session VM gets user-mode networking the host cannot reach."
  type        = string
  default     = "qemu:///system"
}

# "kvm" needs hardware virtualization -- /dev/kvm, i.e. VT-x/AMD-V enabled in
# the firmware. "qemu" is pure software emulation (TCG): it boots, but every
# lab runs an order of magnitude slower. Only for proving the plumbing on a
# host without KVM.
variable "domain_type" {
  description = "kvm, or qemu for software emulation on a host without /dev/kvm."
  type        = string
  default     = "kvm"

  validation {
    condition     = contains(["kvm", "qemu"], var.domain_type)
    error_message = "domain_type must be \"kvm\" or \"qemu\"."
  }
}

variable "network_name" {
  description = "The lab's own libvirt NAT network, created and destroyed with the cluster."
  type        = string
  default     = "kthw"
}

variable "network_cidr" {
  description = <<-EOT
    The lab network. Its own NAT network rather than libvirt's "default", so
    the addresses are fixed and destroying the cluster takes the network with
    it. Reachable from this host only.

    Host .1 is libvirt's gateway and DNS. The nodes take .11-.13 (control
    plane), .21-.22 (workers) and .30 (load balancer). It does not overlap the
    ACE labs' 192.168.145.0/24 and 192.168.146.0/24, so they can coexist.

    The pod (10.244.0.0/16) and service (10.96.0.0/16) networks are set in
    the labs, not here, and must not overlap this one.
  EOT
  type        = string
  default     = "192.168.100.0/24"
}

variable "pool_name" {
  description = "The storage pool the images and disks live in, created and destroyed with the cluster."
  type        = string
  default     = "kthw"
}

variable "pool_path" {
  description = "Directory backing the storage pool."
  type        = string
  default     = "/var/lib/libvirt/images/kthw"
}

variable "image_cache_dir" {
  description = "Where the Fedora image is downloaded and its SHA-256 checked before it becomes the base volume. On local disk, not the repo's filesystem."
  type        = string
  default     = "~/.cache/kubernetes-the-hard-way"
}

variable "fedora_release" {
  description = "A Fedora release number to pin, or null to roll to the newest stable release."
  type        = number
  default     = null
}

variable "fedora_releases_url" {
  description = "Fedora's machine-readable release index."
  type        = string
  default     = "https://fedoraproject.org/releases.json"
}

variable "base_image_url" {
  description = "A complete cloud image URL, bypassing the release index. Needs base_image_checksum."
  type        = string
  default     = null
}

variable "base_image_checksum" {
  description = "SHA-256 of base_image_url."
  type        = string
  default     = null
}

variable "disk_size_gb" {
  description = "Per-VM disk size in GiB. Thin: each node's disk is a copy-on-write overlay on the one base image, and grows only as the node writes."
  type        = number
  default     = 40
}

variable "ssh_public_key_path" {
  description = "Public key injected into every node."
  type        = string
  default     = "~/.ssh/kthw_lab_ed25519.pub"
}

variable "guest_user" {
  description = "Login user created on every node: the Fedora cloud image's own default user, with passwordless sudo."
  type        = string
  default     = "fedora"
}

variable "nodes" {
  description = <<-EOT
    The six machines, sized for a 16 GB workstation: 12.5 GB allocated in all.

    A guest only takes host memory as it touches it, and the balloon device
    gives freed pages back, so the idle cluster uses well under this. The
    workers run every pod. node02 is much larger than node01 on purpose:
    Liferay (Lab 12) is one pod of about 3.5 GiB, and memory split evenly
    would leave neither worker room for it. node01 carries the add-ons. The
    control plane nodes run etcd and three Go binaries.

    mac pins each node's NIC, and cloud-init's network-config matches on it.
  EOT
  type = map(object({
    ip     = string
    mac    = string
    memory = number
    vcpu   = number
  }))
  default = {
    controlplane01 = { ip = "192.168.100.11", mac = "52:54:00:4b:08:11", memory = 1536, vcpu = 2 }
    controlplane02 = { ip = "192.168.100.12", mac = "52:54:00:4b:08:12", memory = 1536, vcpu = 2 }
    controlplane03 = { ip = "192.168.100.13", mac = "52:54:00:4b:08:13", memory = 1536, vcpu = 2 }
    node01         = { ip = "192.168.100.21", mac = "52:54:00:4b:08:21", memory = 2048, vcpu = 2 }
    node02         = { ip = "192.168.100.22", mac = "52:54:00:4b:08:22", memory = 5632, vcpu = 2 }
    loadbalancer   = { ip = "192.168.100.30", mac = "52:54:00:4b:08:30", memory = 512, vcpu = 1 }
  }
}
