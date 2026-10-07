# Lab 99 — Cleaning Up

## What you will have at the end

Your workstation as it was before Lab 2: no VMs, no lab network, no storage pool.

## Destroy the cluster

From the `terraform/kvm` directory on your **workstation**:

```bash
cd terraform/kvm
terraform destroy
```

That removes everything Terraform created: the six `kthw-*` domains, their disks and cloud-init
volumes, the base image volume, the `kthw` storage pool and its directory, the `kthw` NAT network,
and the generated `ssh_config`. Every certificate, key and kubeconfig from the labs lived only on
the VMs, so they are gone too.

Check that nothing is left:

```bash
virsh -c qemu:///system list --all | grep kthw
virsh -c qemu:///system net-list --all | grep kthw
virsh -c qemu:///system pool-list --all | grep kthw
```

All three should print nothing.

## Tidy your workstation

Remove the `Include` line Lab 2 added to `~/.ssh/config`. It points at a file that no longer exists,
which `ssh` ignores, but there is no reason to keep it.

The downloaded Fedora image stays in a cache, so the next `terraform apply` doesn't download it
again. Delete it if you are finished:

```bash
rm -rf ~/.cache/kubernetes-the-hard-way
```

And the lab SSH key, if you won't be back:

```bash
rm ~/.ssh/kthw_lab_ed25519 ~/.ssh/kthw_lab_ed25519.pub
```

Prev: [Deploy Liferay with Helm](12-deploy-liferay.md)
