# Lab 9 — Bootstrapping the Kubernetes Worker Nodes

## What you will have at the end

Two worker nodes running [runc](https://github.com/opencontainers/runc),
[containerd](https://github.com/containerd/containerd),
[kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/) and
[kube-proxy](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/), and
registered with the cluster. They will show as `NotReady` until Lab 11 installs pod networking.

## Prerequisites

Run the commands in this lab on each worker node: `node01` and `node02`. Log in to each one with
`ssh`.

You can do both at once with
[tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux).

## Provisioning a Kubernetes Worker Node

[//]: # (host:node01-node02)

### Install the OS dependencies

```bash
sudo dnf install -y socat conntrack-tools iptables-nft
```

- `socat` carries the traffic for `kubectl port-forward`.
- `conntrack` is how kube-proxy clears stale connection-tracking entries when a Service's
  endpoints change.
- `iptables` is the interface kube-proxy programs Services through. On Fedora it is backed by
  nftables, and the kernel does the work either way.

### Prepare the kernel

Pods on a node talk to each other over a Linux bridge. Two things are off by default and need to be
on:

- the `overlay` module, which containerd's snapshotter uses to layer container images
- `br_netfilter`, which makes traffic crossing that bridge visible to iptables. Without it,
  kube-proxy's Service rules never see pod-to-pod traffic, and a pod cannot reach a Service backed
  by a pod on the same node.

Load both now, and on every boot:

```bash
cat <<EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF
sudo systemctl restart systemd-modules-load.service
```

Then have the kernel pass bridged traffic through iptables, and forward packets between
interfaces. A node forwards all the time: pod to pod, and pod to the outside world.

```bash
cat <<EOF | sudo tee /etc/sysctl.d/10-kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

### SELinux stays on

Earlier versions of this tutorial set SELinux to permissive on every node. Nothing in this build
needs that, so it stays enforcing, as Fedora ships it:

```bash
getenforce
```

```text
Enforcing
```

Fedora's `container-selinux` policy is already installed, and its file contexts cover
`/usr/local/bin` as well as `/usr/bin`. So the binaries you are about to install get the right
domains without any relabelling: `containerd` runs as `container_runtime_t`, the kubelet as
`kubelet_t`, and every container, from Calico to MySQL, as `spc_t`. Once the cluster is running
you can see this with `ps -eZ`.

`spc_t` is the *super-privileged container* domain, so this is not strict. containerd's
`enable_selinux` option is off by default, and without it containers don't get the per-container
labels that keep them apart from each other. Turning it on is how you would get that isolation,
and it is beyond this tutorial.

### Disable Swap

By default the kubelet refuses to start on a node with swap turned on, and this lab keeps that
default (`failSwapOn: true` in the kubelet config). If some of a pod's memory can be quietly
swapped out, the requests and limits the scheduler relies on stop meaning what they say.

Fedora doesn't use a swap partition. It creates a compressed swap device in RAM, `zram0`, on every
boot:

```bash
swapon --show
```

```text
NAME       TYPE      SIZE USED PRIO
/dev/zram0 partition 2.8G   0B  100
```

An empty `zram-generator.conf` in `/etc` overrides the packaged one, so no zram device is created
at boot. `swapoff` turns off the one that exists now:

```bash
sudo touch /etc/systemd/zram-generator.conf
sudo swapoff -a
```

Running `swapon --show` again should print nothing.

### Install the worker binaries

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
  mkdir -p containerd
  tar -xf downloads/crictl-v1.37.0-linux-amd64.tar.gz
  tar -xf downloads/containerd-2.4.1-linux-amd64.tar.gz -C containerd
  sudo install -m 0755 crictl downloads/kube-proxy downloads/kubelet /usr/local/bin/
  sudo install -m 0755 downloads/runc.amd64 /usr/local/bin/runc
  sudo install -m 0755 containerd/bin/* /usr/local/bin/
}
```

The containerd tarball has three binaries: `containerd`, the daemon; `containerd-shim-runc-v2`,
which containerd starts once per pod to call `runc`; and `ctr`, a low-level client. containerd
finds the shim and `runc` by looking them up on its `PATH`, which includes `/usr/local/bin`.

The CNI directories are empty for now. In Lab 11, Calico puts its plugin binaries in `/opt/cni/bin`
and its network configuration in `/etc/cni/net.d`, and containerd reads them from there.

### Configure containerd

```bash
{
  sudo mkdir -p /etc/containerd/
  sudo cp configs/containerd-config.toml /etc/containerd/config.toml
  sudo cp configs/containerd.service /etc/systemd/system/
}
```

Look at `/etc/containerd/config.toml`. It sets only one thing: `SystemdCgroup = true`. Everything else is containerd 2's default, including the CNI directories, the snapshotter and runc as the runtime. `containerd config default` prints the full set. Both the kubelet and runc create cgroups for every container, and they must use the same cgroup driver, here systemd. containerd's default is `false`. If the two disagree, pods start and are then killed soon after.

The unit is `Type=notify`: containerd tells systemd when its socket is ready. The kubelet is ordered after containerd, so it starts only once containerd can take its requests.

`crictl` talks to containerd over the CRI socket. Tell it where that socket is:

```bash
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
```

### Configure the Kubelet

The address ranges used *inside* the cluster:

```bash
export POD_CIDR=10.244.0.0/16
export SERVICE_CIDR=10.96.0.0/16
```

The cluster DNS service goes at `.10` in the service range, by convention. CoreDNS takes that
address in Lab 11, and every pod's `/etc/resolv.conf` points to it:

```bash
export CLUSTER_DNS=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.10", $1, $2, $3) }')
```

Create the kubelet's configuration file and systemd unit, and put its certificate and kubeconfig in
place. `HOSTNAME` is `node01` or `node02`, so each node picks up its own files:

```bash
{
  envsubst < templates/kubelet-config.yaml.template \
    | sudo tee /var/lib/kubelet/kubelet-config.yaml

  envsubst < templates/kubelet.service.template \
    | sudo tee /etc/systemd/system/kubelet.service

  sudo cp ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubelet.kubeconfig
  sudo cp ${HOSTNAME}.key ${HOSTNAME}.crt /var/lib/kubernetes/pki/
  sudo cp ca.crt /var/lib/kubernetes/pki/
}
```

### Configure the Kubernetes Proxy

```bash
{
  envsubst < templates/kube-proxy-config.yaml.template \
    | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml

  sudo cp kube-proxy.crt kube-proxy.key /var/lib/kubernetes/pki/
  sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/
  sudo cp configs/kube-proxy.service /etc/systemd/system/
}
```

### Fix Permissions

```bash
sudo chown root:root /var/lib/kubernetes/pki/* /var/lib/kubelet/* /var/lib/kube-proxy/*
sudo chmod 600 /var/lib/kubernetes/pki/* /var/lib/kubelet/* /var/lib/kube-proxy/*
```

### Start the Worker Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now containerd kubelet kube-proxy
```

Check that containerd answers on its socket:

```bash
sudo crictl version
```

```text
Version:  0.1.0
RuntimeName:  containerd
RuntimeVersion:  v2.4.1
RuntimeApiVersion:  v1
```

> Remember to run the commands above on both worker nodes: `node01` and `node02`.

## Optional: check the certificates and kubeconfigs

[//]: # (command:./cert_verify.sh 4)

On `node01` and `node02`:

```bash
./cert_verify.sh 4
```

## Verification

[//]: # (host:controlplane01)

Return to `controlplane01` and list the registered nodes:

```bash
kubectl get nodes -o wide --kubeconfig admin.kubeconfig
```

```text
NAME     STATUS     ROLES    AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                          KERNEL-VERSION                    CONTAINER-RUNTIME
node01   NotReady   <none>   6s    v1.37.1   192.168.100.21   <none>        Fedora Linux 44 (Cloud Edition)   6.19.10-300.fc44.x86_64 (amd64)   containerd://2.4.1
node02   NotReady   <none>   11s   v1.37.1   192.168.100.22   <none>        Fedora Linux 44 (Cloud Edition)   6.19.10-300.fc44.x86_64 (amd64)   containerd://2.4.1
```

The nodes are `NotReady` because there is no pod network yet. The kubelet reports that containerd
has no CNI configuration. Lab 11 fixes that:

```bash
kubectl describe node node01 --kubeconfig admin.kubeconfig | grep -m1 -o 'container runtime network not ready.*initialized'
```

```text
container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized
```

Next: [Configuring kubectl for Remote Access](10-configuring-kubectl.md)<br>
Prev: [Bootstrapping the Kubernetes Control Plane](08-bootstrapping-kubernetes-controllers.md)
