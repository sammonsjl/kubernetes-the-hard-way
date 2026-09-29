# Which Fedora Cloud Base image the lab is built from, and its SHA-256.
#
# The same module the sibling hard-way labs use, so they all follow Fedora
# forward the same way: unset, every plan reads Fedora's release index and takes
# the newest stable release; fedora_release pins one; base_image_url +
# base_image_checksum bypass the index altogether.

# Fedora's machine-readable release index, read on every plan. This is what
# makes the lab roll forward on its own: when the next Fedora ships, this is
# where it shows up. Skipped entirely when base_image_url is set, so a reader
# with no route to fedoraproject.org can still build the estate.
data "http" "fedora_releases" {
  count = var.base_image_url == null ? 1 : 0

  url                = var.fedora_releases_url
  request_headers    = { Accept = "application/json" }
  request_timeout_ms = 20000

  retry {
    attempts     = 3
    min_delay_ms = 2000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "${var.fedora_releases_url} answered ${self.status_code}. Set fedora_release to pin a release, or base_image_url + base_image_checksum to bypass this lookup."
    }
  }
}

locals {
  # releases.json is a flat list of every artifact of every edition — a few
  # hundred entries across four architectures — so this has to be narrow. The
  # link regex carries most of the load and does it in one place:
  #
  #   /releases/<digits>/  a SHIPPED release. Prereleases live under
  #                        /releases/test/45_Beta/ and nightlies under
  #                        /development/45/, and neither matches. This is the
  #                        test that keeps a beta out during release week.
  #   Cloud/x86_64         not Server, Workstation, KDE, IoT, Silverblue, Labs,
  #                        Spins or Container; not aarch64, ppc64le, s390x.
  #   Generic              not Fedora-Cloud-Base-UEFI-UKI-*.qcow2, which ships
  #                        beside it under the same variant and will not boot
  #                        the seabios machine in ../../kvm; and not the AmazonEC2
  #                        .raw.xz, Azure .vhdfixed.xz, GCE .tar.gz or Vagrant
  #                        .box siblings, all of which are also variant Cloud.
  #   -<rel>-<build>       the build number. 44 alone is not a URL; 44-1.7 is.
  #
  # The version test is belt to those braces: a prerelease is "45_Beta" there,
  # and Rawhide is "Rawhide", so neither survives ^[0-9]+$.
  fedora_images = var.base_image_url != null ? [] : [
    for e in jsondecode(data.http.fedora_releases[0].response_body) : e
    if can(regex("^[0-9]+$", try(e.version, "")))
    && try(e.variant, "") == "Cloud"
    && try(e.subvariant, "") == "Cloud_Base"
    && try(e.arch, "") == "x86_64"
    && can(regex("/releases/[0-9]+/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-[0-9]+-[0-9.]+\\.x86_64\\.qcow2$", try(e.link, "")))
    && can(regex("^[0-9a-f]{64}$", try(e.sha256, "")))
  ]

  # null means roll: take the highest release the index offers. A number pins,
  # and the exact URL, build number and checksum still come from the index.
  fedora_release = var.base_image_url != null ? null : coalesce(
    var.fedora_release,
    try(max([for e in local.fedora_images : tonumber(e.version)]...), 0),
  )

  fedora_image = try(
    [for e in local.fedora_images : e if tonumber(e.version) == local.fedora_release][0],
    null,
  )

  base_image_url      = var.base_image_url != null ? var.base_image_url : try(local.fedora_image.link, "")
  base_image_checksum = var.base_image_url != null ? var.base_image_checksum : try(local.fedora_image.sha256, "")

  # "44-1.7" — release AND build. This goes in the file name, so a new Fedora
  # arrives as a NEW file and a new base volume rather than quietly replacing
  # the one a running estate was built from.
  base_image_build = try(
    regex("Generic-([0-9]+-[0-9.]+)\\.x86_64\\.qcow2$", local.base_image_url)[0],
    substr(sha256(local.base_image_url), 0, 8),
  )

  base_image_file_name = "kthw-fedora-${local.base_image_build}.qcow2"
}

