# Bootstrapping the Kubernetes Worker Nodes

In this lab you will bootstrap two Kubernetes worker nodes. The following components will be installed: [runc](https://github.com/opencontainers/runc), [container networking plugins](https://github.com/containernetworking/cni), [containerd](https://github.com/containerd/containerd), [kubelet](https://kubernetes.io/docs/admin/kubelet), and [kube-proxy](https://kubernetes.io/docs/concepts/cluster-administration/proxies).


## Prerequisites

The commands in this lab must be run on each worker instance: `node01` and `node02` Login to each controller instance using vagrant ssh terminal.

You can perform this step with [tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux).

## Provisioning a Kubernetes Worker Node

[//]: # (host:node01-node02)

Install the OS dependencies:

```bash
  sudo dnf install -y socat conntrack ipset
```

> The socat binary enables support for the `kubectl port-forward` command.

### Disable Swap

By default, the kubelet will fail to start if is enabled. It is [recommended](https://github.com/kubernetes/kubernetes/issues/7294) that swap be disabled to ensure Kubernetes can provide proper resource allocation and quality of service.

Verify if swap is enabled:

```bash
swapon --show
```

If output is empty then swap is not enabled. If swap is enabled run the following command to disable swap immediately:

```bash
sudo touch /etc/systemd/zram-generator.conf 

sudo swapoff -a
```

> To ensure swap remains off after reboot consult your Linux distro documentation.

### Install the worker node binaries:

```bash
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes/pki \
  /var/run/kubernetes
```

```bash
{
  cd ~/downloads

  mkdir -p containerd
  tar -xvf crictl-v1.31.1-linux-amd64.tar.gz
  tar -xvf containerd-1.7.23-linux-amd64.tar.gz -C containerd
  sudo tar -xvf cni-plugins-linux-amd64-v1.6.0.tgz -C /opt/cni/bin/
  mv runc.amd64 runc
  chmod +x crictl kubectl kube-proxy kubelet runc 
  sudo cp crictl kubectl kube-proxy kubelet runc /usr/local/bin/
  sudo cp containerd/bin/* /bin/

  cd ~
}
```

### Configure the Kubelet

CIDR ranges used *within* the cluster

```bash
export POD_CIDR=10.244.0.0/16
export SERVICE_CIDR=10.96.0.0/16
```

Compute cluster DNS addess, which is conventionally .10 in the service CIDR range

```bash
export CLUSTER_DNS=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.10", $1, $2, $3) }')
```

### Configure CNI Networking

Create the `bridge` network configuration file:

```bash
envsubst < templates/10-bridge.conf.template \
| sudo tee /etc/cni/net.d/10-bridge.conf
```

```bash
sudo cp configs/99-loopback.conf /etc/cni/net.d/
```

### Configure containerd

Install the `containerd` configuration files:

```bash
{
  sudo mkdir -p /etc/containerd/
  sudo cp configs/containerd-config.toml /etc/containerd/config.toml
  sudo cp configs/containerd.service /etc/systemd/system/
}
```

### Configure the Kubelet

Create the `kubelet-config.yaml` configuration file:

```bash
{

  envsubst < templates/kubelet-config.yaml.template \
|   sudo tee /var/lib/kubelet/kubelet-config.yaml

  envsubst < templates/kubelet.service.template \
|   sudo tee /etc/systemd/system/kubelet.service

  sudo cp ${HOSTNAME}.kubeconfig /var/lib/kubelet
  sudo cp ${HOSTNAME}.key ${HOSTNAME}.crt /var/lib/kubernetes/pki/
  sudo cp ${HOSTNAME}.kubeconfig /var/lib/kubelet
  sudo cp ca.crt /var/lib/kubernetes/pki/
}
```

### Configure the Kubernetes Proxy

```bash
{
  envsubst < templates/kube-proxy-config.yaml.template \
|   sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml

  sudo cp kube-proxy.crt kube-proxy.key /var/lib/kubernetes/pki/
  sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy
  sudo cp configs/kube-proxy.service /etc/systemd/system/
}
```

### Fix Permissions

```bash
sudo chown root:root /var/lib/kubernetes/pki/*
sudo chmod 600 /var/lib/kubernetes/pki/*
sudo chown root:root /var/lib/kubelet/*
sudo chmod 600 /var/lib/kubelet/*
```

### Start the Worker Services

```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable containerd kubelet kube-proxy
  sudo systemctl start containerd kubelet kube-proxy
}
```

## Verification

[//]: # (host:controlplane01)

Now return to the `controlplane01` node.

List the registered Kubernetes nodes from the controlplane node:

```bash
kubectl get nodes --kubeconfig admin.kubeconfig
```

Output will be similar to

```
NAME       STATUS     ROLES    AGE   VERSION
node01     NotReady   <none>   93s   v1.28.4
node02     NotReady   <none>   93s   v1.28.4
```

The node is not ready as we have not yet installed pod networking. This comes later.


## Optional - Check Certificates and kubeconfigs

At `node01` node, run the following, selecting option 4

[//]: # (command:./cert_verify.sh 4)

```
./cert_verify.sh
```

Next: [TLS Bootstrapping Kubernetes Workers](./11-tls-bootstrapping-kubernetes-workers.md)<br>
Prev: [Installing CRI on the Kubernetes Worker Nodes](./09-install-cri-workers.md)
