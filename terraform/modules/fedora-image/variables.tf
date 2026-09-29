variable "fedora_release" {
  description = "A Fedora release number to pin, or null to take the newest stable release in the index."
  type        = number
  default     = null
}

variable "fedora_releases_url" {
  description = "Fedora's machine-readable release index."
  type        = string
  default     = "https://fedoraproject.org/releases.json"
}

variable "base_image_url" {
  description = "A complete cloud image URL, bypassing the index. Needs base_image_checksum."
  type        = string
  default     = null
}

variable "base_image_checksum" {
  description = "SHA-256 of base_image_url."
  type        = string
  default     = null
}
