# Kubernetes The Hard Way

This tutorial walks you through setting up Kubernetes the hard way, on six KVM virtual machines on
your own Linux workstation. It is not for someone looking for a fully automated tool to bring up a
Kubernetes cluster. Kubernetes The Hard Way is optimized for learning. It takes the long route so
that you understand each task required to bootstrap a Kubernetes cluster.

> The results of this tutorial should not be viewed as production ready.

## Target Audience

The target audience for this tutorial is someone who wants to understand the fundamentals of
Kubernetes and how the core components fit together.

## Cluster Details

Kubernetes The Hard Way guides you through bootstrapping a highly available Kubernetes cluster
with end-to-end encryption between components and RBAC authentication. Every component is a
release binary you install by hand and run under a systemd unit you write yourself.

* [kubernetes](https://github.com/kubernetes/kubernetes) v1.37.1
* [etcd](https://github.com/etcd-io/etcd) v3.7.2
* [containerd](https://github.com/containerd/containerd) v2.4.1
* [runc](https://github.com/opencontainers/runc) v1.5.2
* [calico](https://docs.tigera.io/calico/latest/about) v3.32.2
* [coredns](https://github.com/coredns/coredns) v1.14.7
* [local-path-provisioner](https://github.com/rancher/local-path-provisioner) v0.0.37

When it is built, you install two applications on it with Helm and reach them from your browser
through the cluster's own load balancer: [Uptime Kuma](https://uptime.kuma.pet/), a status page
that you point at the cluster's own API servers, and [Headlamp](https://headlamp.dev/), a web UI
for the cluster.

### Node configuration

```
                          your workstation
                                 │
                 ┌───────────────┴────────────────┐
                 │ loadbalancer  192.168.100.30   │  HAProxy
                 │   :6443 → the API servers      │
                 │   :80   → Uptime Kuma          │
                 │   :8080 → Headlamp             │
                 └───────┬────────────────┬───────┘
          ┌──────────────┘                └───────────────┐
┌─────────┴──────────────────────┐   ┌────────────────────┴────────────┐
│ controlplane01  .11            │   │ node01  .21                     │
│ controlplane02  .12            │   │ node02  .22                     │
│ controlplane03  .13            │   │   containerd · kubelet ·        │
│   etcd · kube-apiserver ·      │   │   kube-proxy                    │
│   controller-manager ·         │   │   Calico · CoreDNS ·            │
│   scheduler                    │   │   Uptime Kuma · Headlamp        │
└────────────────────────────────┘   └─────────────────────────────────┘
               all on the kthw libvirt NAT network, 192.168.100.0/24
```

* Three control plane nodes (`controlplane01`, `controlplane02` and `controlplane03`), running
  etcd and the control plane components as systemd services. `controlplane01` is also where you
  run the admin commands.
* Two worker nodes (`node01` and `node02`).
* One load balancer VM running [HAProxy](https://www.haproxy.org/). It balances requests across
  the three API servers and is the endpoint in your kubeconfig. In the last lab it becomes the
  front door for both applications as well.

The VMs are Fedora Cloud, built by [Terraform](https://developer.hashicorp.com/terraform) against
local libvirt/KVM. They follow Fedora forward: each build uses the newest stable release unless you
pin one.

## What you need

* A Linux workstation with KVM (`/dev/kvm`), libvirt and Terraform
* 16 GB of RAM (the six VMs are allocated 9 GB), and ~20 GB of free disk
* Outbound internet access

Details are in [Lab 1](docs/01-prerequisites.md).

## Labs

* [Prerequisites](docs/01-prerequisites.md)
* [Provisioning Compute Resources](docs/02-compute-resources.md)
* [Client Tools](docs/03-client-tools.md)
* [Provisioning the CA and Generating TLS Certificates](docs/04-certificate-authority.md)
* [Generating Kubernetes Configuration Files for Authentication](docs/05-kubernetes-configuration-files.md)
* [Generating the Data Encryption Config and Key](docs/06-data-encryption-keys.md)
* [Bootstrapping the etcd Cluster](docs/07-bootstrapping-etcd.md)
* [Bootstrapping the Kubernetes Control Plane](docs/08-bootstrapping-kubernetes-controllers.md)
* [Bootstrapping the Kubernetes Worker Nodes](docs/09-bootstrapping-kubernetes-workers.md)
* [Configuring kubectl for Remote Access](docs/10-configuring-kubectl.md)
* [Cluster Add-ons](docs/11-cluster-addons.md)
* [Deploy Uptime Kuma and Headlamp with Helm](docs/12-deploy-uptime-kuma.md)
* [Cleaning Up](docs/99-cleanup.md)

## Repository layout

| Path                   | What it is                                                                          |
| ---------------------- | ----------------------------------------------------------------------------------- |
| `terraform/`           | The six VMs: the `kvm` root, the Fedora image module, and the cloud-init template    |
| `templates/`           | Configs and systemd units the labs fill in with node addresses, using `envsubst`    |
| `configs/`             | Configs and units used as-is                                                        |
| `addons/`              | The Calico installation and the CoreDNS manifest (Lab 11)                           |
| `apps/`                | Helm values for Uptime Kuma and Headlamp (Lab 12)                                   |
| `downloads.txt`        | The pinned release binaries                                                         |
| `cert_verify.sh`       | An optional checker for the certificates and kubeconfigs in Labs 4, 5, 8 and 9      |
