terraform {
  required_version = ">= 1.5"

  required_providers {
    # Reads Fedora's release index. Not a built-in — it has to be declared.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
