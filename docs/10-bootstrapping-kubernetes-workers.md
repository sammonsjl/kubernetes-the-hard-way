# Bootstrapping the Kubernetes Worker Nodes

In this lab you will bootstrap two Kubernetes worker nodes. The following components will be installed: [runc](https://github.com/opencontainers/runc), [container networking plugins](https://github.com/containernetworking/cni), [containerd](https://github.com/containerd/containerd), [kubelet](https://kubernetes.io/docs/admin/kubelet), and [kube-proxy](https://kubernetes.io/docs/concepts/cluster-administration/proxies).


## Prerequisites

The commands in this lab must be run on each worker instance: `node01` and `node02` Login to each controller instance using SSH Terminal.

You can perform this step with [tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux).

## Provisioning a Kubernetes Worker Node

[//]: # (host:node01-node02)

Install the OS dependencies:

```bash
{
  sudo dnf install -y socat conntrack ipset
}
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
sudo swapoff -a
```

> To ensure swap remains off after reboot consult your Linux distro documentation.

Create the installation directories:

```bash
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes
```

Install the worker binaries:

```bash
{
  mkdir -p containerd
  tar -xvf crictl-v1.28.0-linux-arm.tar.gz
  tar -xvf containerd-1.7.8-linux-arm64.tar.gz -C containerd
  sudo tar -xvf cni-plugins-linux-arm64-v1.3.0.tgz -C /opt/cni/bin/
  mv runc.arm64 runc
  chmod +x crictl kubectl kube-proxy kubelet runc 
  sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
  sudo mv containerd/bin/* /bin/
}
```


### Configure CNI Networking

Create the `bridge` network configuration file:

```bash
mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/
```

### Configure containerd

Install the `containerd` configuration files:

```bash
{
  mkdir -p /etc/containerd/
  mv containerd-config.toml /etc/containerd/config.toml
  mv containerd.service /etc/systemd/system/
}
```

### Configure the Kubelet

Create the `kubelet-config.yaml` configuration file:

```bash
{
  mv kubelet-config.yaml /var/lib/kubelet/
  mv kubelet.service /etc/systemd/system/
}
```

### Configure the Kubernetes Proxy

```bash
{
  mv kube-proxy-config.yaml /var/lib/kube-proxy/
  mv kube-proxy.service /etc/systemd/system/
}
```

### Start the Worker Services

```bash
{
  systemctl daemon-reload
  systemctl enable containerd kubelet kube-proxy
  systemctl start containerd kubelet kube-proxy
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

### The kubelet Kubernetes Configuration File

When generating kubeconfig files for Kubelets the client certificate matching the Kubelet's node name must be used. This will ensure Kubelets are properly authorized by the Kubernetes [Node Authorizer](https://kubernetes.io/docs/admin/authorization/node/).

Get the kube-api server load-balancer IP.

```bash
LOADBALANCER=$(dig +short loadbalancer)
```

Generate a kubeconfig file for the first worker node.

On `controlplane01`:
```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://${LOADBALANCER}:6443 \
    --kubeconfig=node01.kubeconfig

  kubectl config set-credentials system:node:node01 \
    --client-certificate=/var/lib/kubernetes/pki/node01.crt \
    --client-key=/var/lib/kubernetes/pki/node01.key \
    --kubeconfig=node01.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:node01 \
    --kubeconfig=node01.kubeconfig

  kubectl config use-context default --kubeconfig=node01.kubeconfig
}
```

Results:

```
node01.kubeconfig
```

### Copy certificates, private keys and kubeconfig files to the worker node:
On `controlplane01`:

```bash
scp ca.crt node01.crt node01.key node01.kubeconfig node01:~/
```


### Download and Install Worker Binaries

All the following commands from here until the [verification](#verification) step must be run on `node01`

[//]: # (host:node01)


```bash
KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

wget -q --show-progress --https-only --timestamping \
  https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kube-proxy \
  https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubelet 
```

Reference: https://kubernetes.io/releases/download/#binaries

Create the installation directories:

```bash
sudo mkdir -p \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes/pki \
  /var/run/kubernetes
```

Install the worker binaries:

```bash
{
  chmod +x kube-proxy kubelet
  sudo mv kube-proxy kubelet /usr/local/bin/
}
```

### Configure the Kubelet

On `node01`:

Copy keys and config to correct directories and secure

```bash
{
  sudo mv ${HOSTNAME}.key ${HOSTNAME}.crt /var/lib/kubernetes/pki/
  sudo mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubelet.kubeconfig
  sudo mv ca.crt /var/lib/kubernetes/pki/
  sudo mv kube-proxy.crt kube-proxy.key /var/lib/kubernetes/pki/
  sudo chown root:root /var/lib/kubernetes/pki/*
  sudo chmod 600 /var/lib/kubernetes/pki/*
  sudo chown root:root /var/lib/kubelet/*
  sudo chmod 600 /var/lib/kubelet/*
}
```

CIDR ranges used *within* the cluster

```bash
POD_CIDR=10.244.0.0/16
SERVICE_CIDR=10.96.0.0/16
```

Compute cluster DNS addess, which is conventionally .10 in the service CIDR range

```bash
CLUSTER_DNS=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.10", $1, $2, $3) }')
```

Create the `kubelet-config.yaml` configuration file:

Reference: https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/

```bash
cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /var/lib/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
containerRuntimeEndpoint: unix:///var/run/containerd/containerd.sock
clusterDomain: cluster.local
clusterDNS:
  - ${CLUSTER_DNS}
cgroupDriver: systemd
resolvConf: /run/systemd/resolve/resolv.conf
runtimeRequestTimeout: "15m"
tlsCertFile: /var/lib/kubernetes/pki/${HOSTNAME}.crt
tlsPrivateKeyFile: /var/lib/kubernetes/pki/${HOSTNAME}.key
registerNode: true
EOF
```

> The `resolvConf` configuration is used to avoid loops when using CoreDNS for service discovery on systems running `systemd-resolved`.

Create the `kubelet.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --kubeconfig=/var/lib/kubelet/kubelet.kubeconfig \\
  --node-ip=${PRIMARY_IP} \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Configure the Kubernetes Proxy

On `node01`:

```bash
sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/
```

Create the `kube-proxy-config.yaml` configuration file:

Reference: https://kubernetes.io/docs/reference/config-api/kube-proxy-config.v1alpha1/

```bash
cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: /var/lib/kube-proxy/kube-proxy.kubeconfig
mode: iptables
clusterCIDR: ${POD_CIDR}
EOF
```

Create the `kube-proxy.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

## Optional - Check Certificates and kubeconfigs

At `node01` node, run the following, selecting option 4

[//]: # (command:./cert_verify.sh 4)

```
./cert_verify.sh
```


### Start the Worker Services

On `node01`:

```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable kubelet kube-proxy
  sudo systemctl start kubelet kube-proxy
}
```

> Remember to run the above commands on worker node: `node01`

Next: [TLS Bootstrapping Kubernetes Workers](./11-tls-bootstrapping-kubernetes-workers.md)<br>
Prev: [Installing CRI on the Kubernetes Worker Nodes](./09-install-cri-workers.md)
