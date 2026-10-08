# Lab 2 — Provisioning Compute Resources

## What you will have at the end

Six Fedora VMs on your workstation that can reach and name each other, and that you can reach by
name with `ssh controlplane01` and so on. Nothing Kubernetes-specific is on them yet.

## The machines

| VM               | Address          | Role                                                               | RAM     | vCPU |
| ---------------- | ---------------- | ------------------------------------------------------------------ | ------- | ---- |
| `controlplane01` | `192.168.100.11` | etcd and the control plane; also where you run the admin commands | 1536 MB | 2    |
| `controlplane02` | `192.168.100.12` | etcd and the control plane                                         | 1536 MB | 2    |
| `controlplane03` | `192.168.100.13` | etcd and the control plane                                         | 1536 MB | 2    |
| `node01`         | `192.168.100.21` | worker: containerd, kubelet, kube-proxy                            | 2048 MB | 2    |
| `node02`         | `192.168.100.22` | worker                                                             | 2048 MB | 2    |
| `loadbalancer`   | `192.168.100.30` | HAProxy in front of the three API servers                          | 512 MB  | 1    |

Three control plane nodes are the smallest etcd cluster that tolerates losing a member. The load
balancer gives clients one stable address for the API, whichever API server is answering.

Every pod runs on the workers: Calico, CoreDNS and the storage provisioner from Lab 11, and
the two applications from Lab 12. On a host with 32 GB, `terraform/kvm/terraform.tfvars.example`
has roomier sizes.

## Bring them up

Clone this repository on your workstation, if you have not already:

```bash
git clone https://github.com/sammonsjl/kubernetes-the-hard-way.git
cd kubernetes-the-hard-way
```

Then, from the `terraform/kvm` directory:

```bash
cd terraform/kvm
terraform init
terraform apply
```

The first run does the following, in order:

1. Reads [Fedora's release index](https://fedoraproject.org/releases.json) and picks the newest
   stable Cloud Base image.
2. Downloads it once (~560 MB) to `~/.cache/kubernetes-the-hard-way`, and checks its SHA-256
   against the index before using it. The download comes through `download.fedoraproject.org`,
   which redirects to a community mirror, so this check matters.
3. Creates the lab's NAT network `kthw` and storage pool `kthw`, then uploads the image into the
   pool as a base volume.
4. Gives each VM its own disk as a copy-on-write overlay on that base, plus a cloud-init disk.
   Then it boots them.

The VMs themselves come up in seconds. Terraform prints the addresses when it finishes, and
`terraform output` shows them again.

> **The lab follows Fedora forward.** Each `terraform apply` builds on the newest stable Fedora.
> If a new release lands partway through and you would rather not move, `terraform output
> base_image` prints the release number. Put it in `terraform.tfvars` as `fedora_release`.

### What cloud-init did

Very little, on purpose:

- It created the `fedora` user, with passwordless sudo and your lab key.
- It installed the tools the labs use from the first command: `dig`, `envsubst`, `openssl`,
  `wget`, `tmux`, `vim`, `git`, `jq`.
- It wrote all six names into `/etc/hosts`, after deleting the cloud image's `127.0.1.1` entry for
  the node's own hostname. If that entry stays, `controlplane01` resolves to a loopback address *on
  controlplane01*. The labs read node addresses with `dig`, so that address would end up in
  certificate SANs and in the etcd member list.
- It wrote `/etc/profile.d/kthw.sh`, which exports `PRIMARY_IP`: the node's own address, which
  the etcd, API server and kubelet templates bind to.

Everything else, from kernel modules to swap to SELinux, is done by hand in the lab that needs it.

## Reaching them

Terraform writes an `ssh_config` next to the configuration. Include it once, and every node is
reachable by name:

```bash
printf '\nInclude %s\n' "$(terraform output -raw ssh_config_path)" >> ~/.ssh/config
```

The leading newline matters. If `~/.ssh/config` does not end in a newline, a plain `echo` joins the
`Include` onto your last line and makes it unparsable.

If your `~/.ssh/config` already has a `Host *` block, put the `Include` line **below** it. On
recent OpenSSH, an `Include` placed before a `Host *` block is parsed but its `Host` entries are
never applied. `ssh -vvv` shows this as `(parse only)`.

> **Repo on a NAS/NFS mount?** `Include` refuses a file it does not think you or root own, and NFS
> often reports files under the server's uid. If `ssh` says `Bad owner or permissions`, copy the
> file somewhere local instead:
> ```bash
> cp terraform/kvm/ssh_config ~/.ssh/kthw-ssh-config
> printf '\nInclude %s\n' ~/.ssh/kthw-ssh-config >> ~/.ssh/config
> ```

Then, from anywhere:

```bash
ssh controlplane01
```

If you would rather not touch `~/.ssh/config`, use `ssh -F terraform/kvm/ssh_config controlplane01`.
It does the same thing.

## Verify

Every node should answer and resolve every other node:

```bash
for n in controlplane01 controlplane02 controlplane03 node01 node02 loadbalancer; do
  ssh $n 'echo "$(hostname) $PRIMARY_IP -> $(dig +short loadbalancer)"'
done
```

```text
controlplane01 192.168.100.11 -> 192.168.100.30
controlplane02 192.168.100.12 -> 192.168.100.30
controlplane03 192.168.100.13 -> 192.168.100.30
node01 192.168.100.21 -> 192.168.100.30
node02 192.168.100.22 -> 192.168.100.30
loadbalancer 192.168.100.30 -> 192.168.100.30
```

## Troubleshooting

**`Error reading response body ... connection reset by peer` on the first plan.** That is the
download of Fedora's release index from `fedoraproject.org` being cut off partway. Nothing has
been created yet. Run `terraform apply` again.

**SSH hangs or is refused, or the Verify loop prints no address after the arrow.** cloud-init may
still be running: SSH answers before it has installed the tools and written `/etc/hosts`. Check a node's console log, where
cloud-init prints `kthw: <node> ready after N seconds` when it is done:

```bash
sudo tail /var/log/libvirt/qemu/kthw-controlplane01-console.log
```

Or attach to the console directly with `virsh -c qemu:///system console kthw-controlplane01`
(leave with `Ctrl-]`).

**One VM is broken.** Replace just that one:

```bash
terraform apply -replace='libvirt_domain.node["node01"]' -replace='libvirt_volume.disk["node01"]'
```

## Stopping and starting

You do not need to finish in one sitting. The VMs are ordinary libvirt domains named `kthw-*`:

```bash
for n in $(virsh -c qemu:///system list --name | grep ^kthw-); do
  virsh -c qemu:///system shutdown $n
done
```

and to start them again:

```bash
for n in $(virsh -c qemu:///system list --name --inactive | grep ^kthw-); do
  virsh -c qemu:///system start $n
done
```

From Lab 7 onward, every service you install is enabled in systemd, so the cluster comes back
together on its own after a restart.

Next: [Client tools](03-client-tools.md)<br>
Prev: [Prerequisites](01-prerequisites.md)
