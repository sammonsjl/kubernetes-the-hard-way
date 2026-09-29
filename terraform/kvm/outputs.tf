output "nodes" {
  description = "Node name to address."
  value       = { for name, n in var.nodes : name => n.ip }
}

output "ssh_config_path" {
  description = "Include this from ~/.ssh/config to get `ssh controlplane01` and friends."
  value       = abspath(local_file.ssh_config.filename)
}

output "base_image" {
  description = "The image the nodes were built from. Put `release` into fedora_release in terraform.tfvars to stop the lab rolling forward."
  value = {
    release   = module.fedora_image.release
    url       = module.fedora_image.url
    sha256    = module.fedora_image.sha256
    file_name = module.fedora_image.file_name
    pinned    = var.fedora_release != null || var.base_image_url != null
  }
}
