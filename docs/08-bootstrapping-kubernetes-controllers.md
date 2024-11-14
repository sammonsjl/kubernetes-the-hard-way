# Bootstrapping the Kubernetes Control Plane

In this lab you will bootstrap the Kubernetes control plane across 3 compute instances and configure it for high availability. You will also create an external load balancer that exposes the Kubernetes API Servers to remote clients. The following components will be installed on each node: Kubernetes API Server, Scheduler, and Controller Manager.

Note that in a production-ready cluster it is recommended to have an odd number of controlplane nodes as for multi-node services like etcd, leader election and quorum work better. See lecture on this ([KodeKloud](https://kodekloud.com/topic/etcd-in-ha/), [Udemy](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/learn/lecture/14296192#overview)).


If you examine the command line arguments passed to the various control plane components, you should recognise many of the files that were created in earlier sections of this course, such as certificates, keys, kubeconfigs, the encryption configuration etc.

## Prerequisites

The commands in this lab up as far as the load balancer configuration must be run on each controller instance: `controlplane01`, `controlplane02` and `controlplane03`. Login to each controller instance using vagrant ssh terminal.

You can perform this step with [tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux).

## Provision the Kubernetes Control Plane

[//]: # (host:controlplane01-controlplane02-controlplane03)

### Install the Kubernetes Controller Binaries

Reference: https://kubernetes.io/releases/download/#binaries

Install the Kubernetes binaries:

```bash
{
  cd ~/downloads

  chmod +x downloads/kube-apiserver \
    downloads/kube-controller-manager \
    downloads/kube-scheduler \
    downloads/kubectl

  sudo cp downloads/kube-apiserver \
    downloads/kube-controller-manager \
    downloads/kube-scheduler \
    downloads/kubectl /usr/local/bin/

    cd ~
}
```


### Configure the Kubernetes API Server

```bash
{
    sudo mkdir -p /var/lib/kubernetes/pki

    sudo cp ca.crt ca.key /var/lib/kubernetes/pki

    for c in kube-apiserver service-account apiserver-kubelet-client etcd-server kube-scheduler kube-controller-manager
    do
      sudo cp "$c.crt" "$c.key" /var/lib/kubernetes/pki/
    done

    sudo chown root:root /var/lib/kubernetes/pki/*
    sudo chmod 600 /var/lib/kubernetes/pki/*
}
```

The instance internal IP address will be used to advertise the API Server to members of the cluster. The load balancer IP address will be used as the external endpoint to the API servers.<br>
Retrieve these internal IP addresses:

```bash
export LOADBALANCER=$(dig +short loadbalancer)
```

IP addresses of the two controlplane nodes, where the etcd servers are.

```bash
export CONTROL01=$(dig +short controlplane01)
export CONTROL02=$(dig +short controlplane02)
export CONTROL03=$(dig +short controlplane03)
```

CIDR ranges used *within* the cluster

```bash
export POD_CIDR=10.244.0.0/16
export SERVICE_CIDR=10.96.0.0/16
```

Create the `kube-apiserver.service` systemd unit file:

```bash
envsubst < templates/kube-apiserver.service.template \
| sudo tee /etc/systemd/system/kube-apiserver.service
```

### Configure the Kubernetes Controller Manager

Move the `kube-controller-manager` kubeconfig into place:

```bash
sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/
```

Create the `kube-controller-manager.service` systemd unit file:

```bash
envsubst < templates/kube-controller-manager.service.template \
| sudo tee /etc/systemd/system/kube-controller-manager.service
```

### Configure the Kubernetes Scheduler

Move the `kube-scheduler` kubeconfig into place:

```bash
sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/
```

Create the `kube-scheduler.yaml` configuration file:

```bash
sudo mkdir -p /etc/kubernetes/config/
sudo cp configs/kube-scheduler.yaml /etc/kubernetes/config/
```

Create the `kube-scheduler.service` systemd unit file:

```bash
envsubst < templates/kube-scheduler.service.template \
| sudo tee /etc/systemd/system/kube-scheduler.service
```

## Secure kubeconfigs

```bash
sudo chmod 600 /var/lib/kubernetes/*.kubeconfig
```

## Optional - Check Certificates and kubeconfigs

At `controlplane01`, `controlplane02` and `controlplane03` nodes, run the following, selecting option 3

[//]: # (command:./cert_verify.sh 3)

```
./cert_verify.sh
```


### Start the Controller Services

```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
  sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
}
```

> Allow up to 10 seconds for the Kubernetes API Server to fully initialize.


### Verification

[//]: # (sleep:10)

After running the above commands on both controlplane nodes, run the following on `controlplane01`

```bash
kubectl get componentstatuses --kubeconfig admin.kubeconfig
```

It will give you a deprecation warning here, but that's ok.

> Output

```
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE   ERROR
scheduler            Healthy   ok        
controller-manager   Healthy   ok        
etcd-0               Healthy   ok 
```

> Remember to run the above commands on each controller node: `controlplane01`, `controlplane02` and `controlplane03`.

## RBAC for Kubelet Authorization

In this section you will configure RBAC permissions to allow the Kubernetes API Server to access the Kubelet API on each worker node. Access to the Kubelet API is required for retrieving metrics, logs, and executing commands in pods.

> This tutorial sets the Kubelet `--authorization-mode` flag to `Webhook`. Webhook mode uses the [SubjectAccessReview](https://kubernetes.io/docs/admin/authorization/#checking-api-access) API to determine authorization.


[//]: # (host:controlplane01)

Run the below on the `controlplane01` node.

Create the `system:kube-apiserver-to-kubelet` [ClusterRole](https://kubernetes.io/docs/admin/authorization/rbac/#role-and-clusterrole) with permissions to access the Kubelet API and perform most common tasks associated with managing pods:

```bash
kubectl apply -f configs/kube-apiserver-to-kubelet.yaml \
  --kubeconfig admin.kubeconfig
```

## The Kubernetes Frontend Load Balancer

In this section you will provision an external load balancer to front the Kubernetes API Servers. The `kubernetes-the-hard-way` static IP address will be attached to the resulting load balancer.


### Provision a Network Load Balancer

A NLB operates at [layer 4](https://en.wikipedia.org/wiki/OSI_model#Layer_4:_Transport_layer) (TCP) meaning it passes the traffic straight through to the back end servers unfettered and does not interfere with the TLS process, leaving this to the Kube API servers.

Login to `loadbalancer` instance using `vagrant ssh` (or `multipass shell` on Apple Silicon).

[//]: # (host:loadbalancer)


```bash
sudo dnf install -y haproxy
```

Read IP addresses of controlplane nodes and this host to shell variables

```bash
CONTROL01=$(dig +short controlplane01)
CONTROL02=$(dig +short controlplane02)
CONTROL03=$(dig +short controlplane03)
LOADBALANCER=$(dig +short loadbalancer)
```

Create HAProxy configuration to listen on API server port on this host and distribute requests evently to the two controlplane nodes.

We configure it to operate as a [layer 4](https://en.wikipedia.org/wiki/Transport_layer) loadbalancer (using `mode tcp`), which means it forwards any traffic directly to the backends without doing anything like [SSL offloading](https://ssl2buy.com/wiki/ssl-offloading).

```bash
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
frontend kubernetes
    bind ${LOADBALANCER}:6443
    option tcplog
    mode tcp
    default_backend kubernetes-controlplane-nodes

backend kubernetes-controlplane-nodes
    mode tcp
    balance roundrobin
    option tcp-check
    server controlplane01 ${CONTROL01}:6443 check fall 3 rise 2
    server controlplane02 ${CONTROL02}:6443 check fall 3 rise 2
    server controlplane03 ${CONTROL03}:6443 check fall 3 rise 2
EOF
```

```bash

sudo systemctl enable haproxy
sudo systemctl start haproxy
```

### Verification

[//]: # (sleep:2)

Make a HTTP request for the Kubernetes version info:

```bash
curl -k https://${LOADBALANCER}:6443/version
```

This should output some details about the version and build information of the API server.

Next: [Installing CRI on the Kubernetes Worker Nodes](./09-install-cri-workers.md)<br>
Prev: [Bootstrapping the etcd Cluster](./07-bootstrapping-etcd.md)
