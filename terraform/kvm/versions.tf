terraform {
  required_version = ">= 1.5"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# The system instance, not qemu:///session: a session VM gets user-mode
# networking with no address the host can reach. Being in the `libvirt` group
# is enough to use it without sudo.
provider "libvirt" {
  uri = var.libvirt_uri
}
