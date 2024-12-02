# Bootstrapping the etcd Cluster

Kubernetes components are stateless and store cluster state in [etcd](https://etcd.io/). In this lab you will bootstrap a three node etcd cluster and configure it for high availability and secure remote access.

If you examine the command line arguments passed to etcd in its unit file, you should recognise some of the certificates and keys created in earlier sections of this course.

## Prerequisites

The commands in this lab must be run on each controller instance: `controlplane01`, `controlplane02` and `controlplane03`. Login to each of these using an SSH terminal.

### Running commands in parallel with tmux

[tmux](https://github.com/tmux/tmux/wiki) can be used to run commands on multiple compute instances at the same time.

## Bootstrapping an etcd Cluster Member

### Install the etcd Binaries

[//]: # (host:controlplane01-controlplane02-controlplane03)

Extract and install the `etcd` server and the `etcdctl` command line utility:

```bash
{
  tar -xvf downloads/etcd-v3.5.16-linux-amd64.tar.gz
  sudo mv etcd-v3.5.16-linux-amd64/etcd* /usr/local/bin/
}
```

### Configure the etcd Server

Copy and secure certificates. Note that we place `ca.crt` in our main PKI directory and link it from etcd to not have multiple copies of the cert lying around.

```bash
{
  sudo mkdir -p /etc/etcd /var/lib/etcd /var/lib/kubernetes/pki
  sudo cp etcd-server.key etcd-server.crt /etc/etcd/
  sudo cp ca.crt /var/lib/kubernetes/pki/
  sudo chown root:root /etc/etcd/*
  sudo chmod 600 /etc/etcd/*
  sudo chown root:root /var/lib/kubernetes/pki/*
  sudo chmod 600 /var/lib/kubernetes/pki/*
  sudo ln -s /var/lib/kubernetes/pki/ca.crt /etc/etcd/ca.crt
}
```

The instance internal IP address will be used to serve client requests and communicate with etcd cluster peers.<br>
Retrieve the internal IP address of the controlplane(etcd) nodes, and also that of controlplane01, controlplane02 and controlplane03 for the etcd cluster member list

```bash
export CONTROL01=$(dig +short controlplane01)
export CONTROL02=$(dig +short controlplane02)
export CONTROL03=$(dig +short controlplane03)
```

Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current compute instance:

```bash
export ETCD_NAME=$(hostname -s)
```

Copy the `etcd.service` systemd unit file:

```bash
envsubst < templates/etcd.service.template \
| sudo tee /etc/systemd/system/etcd.service
```

### Start the etcd Server

```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable etcd
  sudo systemctl start etcd
}
```

> Remember to run the above commands on each controller node: `controlplane01`, `controlplane02` and `controlplane03`.

## Verification

[//]: # (sleep:5)

List the etcd cluster members.

After running the above commands on both controlplane nodes, run the following on each controller node: `controlplane01`, `controlplane02` and `controlplane03`.

```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key
```

Output will be similar to this

```
1a82afa2247e7562, started, controlplane02, https://192.168.100.12:2380, https://192.168.100.12:2379, false
b9a27230d536d1e8, started, controlplane01, https://192.168.100.11:2380, https://192.168.100.11:2379, false
cb6055e972a4f0d1, started, controlplane03, https://192.168.100.13:2380, https://192.168.100.13:2379, false
```

Reference: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#starting-etcd-clusters

Next: [Bootstrapping the Kubernetes Control Plane](./08-bootstrapping-kubernetes-controllers.md)<br>
Prev: [Generating the Data Encryption Config and Key](./06-data-encryption-keys.md)
