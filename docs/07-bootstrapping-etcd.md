# Lab 7 — Bootstrapping the etcd Cluster

## What you will have at the end

A three-member [etcd](https://etcd.io/) cluster, one member on each control plane node. Clients
and peers must present certificates signed by the cluster CA.

Kubernetes components are stateless. They keep all cluster state in etcd. If you look at the
command line arguments etcd is given in its unit file, you will recognise the certificates and keys
created in Lab 4.

## Prerequisites

Run the commands in this lab on each control plane node: `controlplane01`, `controlplane02` and
`controlplane03`. Log in to each one with `ssh`.

You can do all three at once with
[tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux).

## Bootstrapping an etcd Cluster Member

### Install the etcd Binaries

[//]: # (host:controlplane01-controlplane02-controlplane03)

Extract and install the `etcd` server, the `etcdctl` client, and `etcdutl`, the offline tool for
data directories and snapshots:

```bash
tar -xf downloads/etcd-v3.7.2-linux-amd64.tar.gz
sudo install -m 0755 etcd-v3.7.2-linux-amd64/etcd* /usr/local/bin/
```

### Configure the etcd Server

Copy the certificates into place and lock them down. `ca.crt` goes in the main PKI directory, and
etcd's directory links to it, so there is only one copy of the CA certificate on the node:

```bash
{
  sudo mkdir -p /etc/etcd /var/lib/etcd /var/lib/kubernetes/pki
  sudo chmod 700 /var/lib/etcd
  sudo cp etcd-server.key etcd-server.crt /etc/etcd/
  sudo cp ca.crt /var/lib/kubernetes/pki/
  sudo chown root:root /etc/etcd/* /var/lib/kubernetes/pki/*
  sudo chmod 600 /etc/etcd/* /var/lib/kubernetes/pki/*
  sudo ln -s /var/lib/kubernetes/pki/ca.crt /etc/etcd/ca.crt
}
```

etcd serves clients and talks to its peers on this node's address, `PRIMARY_IP`, which cloud-init
set in Lab 2. It also needs the addresses of all three members for the initial cluster list:

```bash
export CONTROL01=$(dig +short controlplane01)
export CONTROL02=$(dig +short controlplane02)
export CONTROL03=$(dig +short controlplane03)
echo $PRIMARY_IP
```

Each etcd member must have a unique name within the cluster. Use the node's hostname:

```bash
export ETCD_NAME=$(hostname -s)
```

Create the `etcd.service` systemd unit file:

```bash
envsubst < templates/etcd.service.template \
  | sudo tee /etc/systemd/system/etcd.service
```

### Start the etcd Server

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now etcd
```

> Run the commands above on every control plane node: `controlplane01`, `controlplane02` and
> `controlplane03`. The first member waits for the others to join before the cluster forms, so
> `systemctl` may appear to hang on it until the second one starts.

## Verification

[//]: # (sleep:5)

Once etcd is running on all three nodes, list the cluster members from any of them:

```bash
sudo etcdctl member list -w table \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key
```

The output will be similar to this:

```text
┌──────────────────┬─────────┬────────────────┬─────────────────────────────┬─────────────────────────────┬────────────┐
│        ID        │ STATUS  │      NAME      │         PEER ADDRS          │        CLIENT ADDRS         │ IS LEARNER │
├──────────────────┼─────────┼────────────────┼─────────────────────────────┼─────────────────────────────┼────────────┤
│ 1a82afa2247e7562 │ started │ controlplane02 │ https://192.168.100.12:2380 │ https://192.168.100.12:2379 │      false │
│ b9a27230d536d1e8 │ started │ controlplane01 │ https://192.168.100.11:2380 │ https://192.168.100.11:2379 │      false │
│ cb6055e972a4f0d1 │ started │ controlplane03 │ https://192.168.100.13:2380 │ https://192.168.100.13:2379 │      false │
└──────────────────┴─────────┴────────────────┴─────────────────────────────┴─────────────────────────────┴────────────┘
```

Reference: https://etcd.io/docs/latest/op-guide/clustering/

Next: [Bootstrapping the Kubernetes Control Plane](08-bootstrapping-kubernetes-controllers.md)<br>
Prev: [Generating the Data Encryption Config and Key](06-data-encryption-keys.md)
