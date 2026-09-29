output "url" {
  description = "Where to download the image."
  value       = local.base_image_url

  precondition {
    condition     = var.base_image_url == null || var.base_image_checksum != null
    error_message = "base_image_url needs base_image_checksum with it. An unverified image is not worth the escape hatch."
  }
  precondition {
    condition     = local.base_image_url != ""
    error_message = var.fedora_release == null ? "No stable Fedora Cloud Base Generic x86_64 qcow2 found in ${var.fedora_releases_url}. Set base_image_url + base_image_checksum to bypass it." : "Fedora ${var.fedora_release} has no Cloud Base Generic x86_64 qcow2 in ${var.fedora_releases_url} — it is probably end-of-life and gone from the index. Try a newer number, or null to roll to the latest."
  }
}

output "sha256" {
  description = "The image's SHA-256, from the index (or base_image_checksum)."
  value       = local.base_image_checksum
}

output "release" {
  description = "The Fedora release number, or null when base_image_url bypasses the index."
  value       = local.fedora_release
}

output "file_name" {
  description = "kthw-fedora-<release>-<build>.qcow2: a new Fedora arrives as a new file, never an overwrite of the one a running estate was built from."
  value       = local.base_image_file_name
}
