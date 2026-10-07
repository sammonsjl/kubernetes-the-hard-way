# Lab 1 — Prerequisites

## What you will have at the end

A Linux workstation that can run six KVM virtual machines, with Terraform installed and a dedicated
SSH key for the lab.

## What you need

|             |                                                                                                                                                                                                            |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Host OS** | Linux with KVM. Built and tested on Arch; Fedora and Ubuntu work the same way.                                                                                                                             |
| **RAM**     | **16 GB minimum, 24 GB comfortable.** `terraform/kvm/variables.tf` allocates 12.5 GB across the six VMs. A guest takes host memory only as it touches it, but by the end of Lab 12 they have touched nearly all of it. On a 16 GB desktop, close other heavy applications from Lab 11 onward and expect the host to swap during Lab 12. |
| **CPU**     | 4 cores workable, 8 comfortable. Hardware virtualization (VT-x/AMD-V) must be enabled in the firmware.                                                                                                      |
| **Disk**    | ~20 GB free under `/var/lib/libvirt/images`. Each VM has a 40 GiB disk, but they are thin copy-on-write overlays on one Fedora image and grow only as the node writes.                                    |
| **Network** | Outbound internet from the host. The VMs download the Kubernetes release binaries and pull container images from Docker Hub and quay.io.                                                                  |

## KVM and libvirt

Check that the CPU's virtualization extensions are on and the kernel has exposed them:

```bash
ls -l /dev/kvm
```

If `/dev/kvm` does not exist, enable VT-x or AMD-V (sometimes labelled *SVM*) in the firmware setup.

Install libvirt and QEMU, then start the daemon:

*Arch:*

```bash
sudo pacman -S --needed libvirt qemu-base dnsmasq
sudo systemctl enable --now libvirtd.socket
```

*Fedora:*

```bash
sudo dnf -y install @virtualization
sudo systemctl enable --now libvirtd.socket
```

*Ubuntu:*

```bash
sudo apt install -y qemu-system-x86 libvirt-daemon-system dnsmasq-base
```

Add yourself to the `libvirt` group, so that Terraform can drive `qemu:///system` without sudo. Log
out and back in for the group to apply.

```bash
sudo usermod -aG libvirt "$USER"
```

> **The system instance, not the session one.** Terraform talks to `qemu:///system`. A VM in
> `qemu:///session` gets user-mode networking, which has no address your host can reach. That is no
> use for a cluster you will SSH into six ways and curl from the host.

Check that it answers:

```bash
virsh -c qemu:///system list --all
```

## Terraform

*Arch:*

```bash
sudo pacman -S --needed terraform
```

*Fedora:* use [HashiCorp's dnf repo](https://developer.hashicorp.com/terraform/install).

*Ubuntu:* use [HashiCorp's apt repo](https://developer.hashicorp.com/terraform/install).

You can use `tofu` (OpenTofu) instead of `terraform` everywhere in these labs. The configuration
uses nothing specific to either tool.

## An SSH key for the lab

Terraform puts one public key into all six VMs. Use a dedicated key, so the lab machines never see
your everyday one:

```bash
ssh-keygen -t ed25519 -N '' -C 'kubernetes-the-hard-way lab key' -f ~/.ssh/kthw_lab_ed25519
```

Keep it at that path, or set `ssh_public_key_path` in `terraform/kvm/terraform.tfvars` to where it
is.

> **Keep the private key on local disk**, even if this repo lives on a NAS. `ssh` refuses a key it
> does not believe you own, and a network filesystem often presents files under a different uid
> than your local account.

## Lab defaults

These networks are fixed. Changing them is possible, but it is a search-and-replace across the labs
and the add-on manifests, and none of the three may overlap another.

| Network             | CIDR               | Set in                                                                  |
| ------------------- | ------------------ | ----------------------------------------------------------------------- |
| **VM network**      | `192.168.100.0/24` | `network_cidr` and `nodes` in `terraform/kvm/variables.tf`               |
| **Pod network**     | `10.244.0.0/16`    | `POD_CIDR` in Labs 8 and 9, and `addons/calico-custom-resources.yaml`    |
| **Service network** | `10.96.0.0/16`     | `SERVICE_CIDR` in Labs 4, 8 and 9, and the `clusterIP` in `addons/coredns.yaml` |

The VM network is a libvirt NAT network of the lab's own. It is reachable from your host and from
nowhere else, and `terraform destroy` removes it.

## Running commands in parallel with tmux

Several labs run the same commands on three control plane nodes or two workers. With
[tmux](https://github.com/tmux/tmux/wiki) **on your workstation**, you can split a window into
panes, SSH to a different node in each, and type into all of them at once:

1. `tmux`, then `Ctrl-b "` (or `Ctrl-b %`) to split, once for each node.
2. In each pane, `ssh controlplane01`, `ssh controlplane02`, and so on (Lab 2 sets up these names).
3. `Ctrl-b :setw synchronize-panes on` and press Enter. Everything you type now goes to every pane.
   Use `off` to stop.

> tmux is optional. You can also run each command on each node in turn.

![tmux screenshot](../images/tmux-screenshot.png)

## Verify

```bash
terraform version
virsh -c qemu:///system list --all
ls ~/.ssh/kthw_lab_ed25519.pub
```

Next: [Provisioning Compute Resources](02-compute-resources.md)
