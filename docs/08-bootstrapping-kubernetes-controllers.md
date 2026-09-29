# Lab 8 — Bootstrapping the Kubernetes Control Plane

## What you will have at the end

The Kubernetes API Server, Scheduler and Controller Manager running as systemd services on all three
control plane nodes, with an HAProxy load balancer in front of the three API servers. The load
balancer is the address every client outside the control plane will use.

If you look at the command line arguments these components are given, you will recognise many of
the files created in earlier labs: certificates, keys, kubeconfigs and the encryption
configuration.

A production cluster uses an odd number of control plane nodes, because etcd needs a majority of
its members to agree. Three members keep working with one of them down.

## Prerequisites

Run the commands in this lab, up to the RBAC section, on each control plane node:
`controlplane01`, `controlplane02` and `controlplane03`.

You can do all three at once with
[tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux).

## Provision the Kubernetes Control Plane

[//]: # (host:controlplane01-controlplane02-controlplane03)

### Install the Kubernetes Controller Binaries

Reference: https://kubernetes.io/releases/download/#binaries

```bash
sudo install -m 0755 \
  downloads/kube-apiserver \
  downloads/kube-controller-manager \
  downloads/kube-scheduler \
  downloads/kubectl \
  /usr/local/bin/
```

### Configure the Kubernetes API Server

Put the certificates and keys the control plane uses into the PKI directory:

```bash
{
  sudo mkdir -p /var/lib/kubernetes/pki

  sudo cp ca.crt ca.key /var/lib/kubernetes/pki/

  for c in kube-apiserver service-account apiserver-kubelet-client etcd-server kube-scheduler kube-controller-manager; do
    sudo cp "$c.crt" "$c.key" /var/lib/kubernetes/pki/
  done

  sudo chown root:root /var/lib/kubernetes/pki/*
  sudo chmod 600 /var/lib/kubernetes/pki/*
}
```

The API server advertises itself to the rest of the cluster on this node's address,
`PRIMARY_IP`. The load balancer's address is the issuer of service account tokens, because it is
the stable name of the API as a whole:

```bash
export LOADBALANCER=$(dig +short loadbalancer)
```

It stores its state in etcd, on the three control plane nodes:

```bash
export CONTROL01=$(dig +short controlplane01)
export CONTROL02=$(dig +short controlplane02)
export CONTROL03=$(dig +short controlplane03)
```

The address ranges used *inside* the cluster:

```bash
export POD_CIDR=10.244.0.0/16
export SERVICE_CIDR=10.96.0.0/16
```

Create the `kube-apiserver.service` systemd unit file:

```bash
envsubst < templates/kube-apiserver.service.template \
  | sudo tee /etc/systemd/system/kube-apiserver.service
```

A few of its flags are worth reading closely:

- `--authorization-mode=Node,RBAC`. The Node authorizer limits each kubelet to the objects of the
  pods on its own node. RBAC covers everyone else.
- `--kubelet-certificate-authority`. The API server verifies each kubelet's serving certificate
  against the cluster CA when it connects for `logs`, `exec` and `port-forward`. This is why the
  node certificates in Lab 4 carry the node's IP address.
- `--encryption-provider-config`. This is the file from Lab 6. Secrets are encrypted before they
  reach etcd.

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

The controller manager gives each node a slice of `POD_CIDR` (`--allocate-node-cidrs`), and signs
certificates with the cluster CA's key (`--cluster-signing-*`). That is why the CA key is on the
control plane nodes and nowhere else.

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

The scheduler reads its settings from this file (`--config`) rather than from flags. Here that is only its kubeconfig and leader election, which stops three schedulers from placing the same pod at the same time.

Create the `kube-scheduler.service` systemd unit file:

```bash
envsubst < templates/kube-scheduler.service.template \
  | sudo tee /etc/systemd/system/kube-scheduler.service
```

### Secure the kubeconfigs

```bash
sudo chmod 600 /var/lib/kubernetes/*.kubeconfig
```

### Optional: check the certificates and kubeconfigs

[//]: # (command:./cert_verify.sh 3)

```bash
./cert_verify.sh 3
```

### Start the Controller Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now kube-apiserver kube-controller-manager kube-scheduler
```

> Allow up to 10 seconds for the Kubernetes API Server to fully initialize.

### Verification

[//]: # (sleep:10)

Ask the local API server whether it is ready. `?verbose` lists each check it runs, and etcd is one
of them:

```bash
kubectl get --raw='/readyz?verbose' --kubeconfig admin.kubeconfig
```

```text
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
...
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed
```

The controller manager and the scheduler each serve their own health endpoint, on the loopback
address only:

```bash
curl -sk https://127.0.0.1:10257/healthz; echo
curl -sk https://127.0.0.1:10259/healthz; echo
```

```text
ok
ok
```

> In older versions of this tutorial, `kubectl get componentstatuses` did this job. That API has
> been deprecated since v1.19 and only ever checked one etcd member. The health endpoints above are
> what it was replaced with.

> Remember to run the commands above on each control plane node: `controlplane01`,
> `controlplane02` and `controlplane03`.

## RBAC for Kubelet Authorization

In this section you configure RBAC permissions that let the Kubernetes API Server reach the Kubelet
API on each worker node. The API server needs that access to fetch metrics and logs and to run
commands in pods.

> The kubelets in Lab 9 set their `authorization.mode` to `Webhook`. In Webhook mode the kubelet
> asks the API server, through the
> [SubjectAccessReview](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
> API, whether the caller may do what it is asking.

[//]: # (host:controlplane01)

Run this on the `controlplane01` node only.

Create the `system:kube-apiserver-to-kubelet`
[ClusterRole](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole)
with permission to use the Kubelet API, and bind it to the `kube-apiserver` user. That user is the
`apiserver-kubelet-client` certificate's common name:

```bash
kubectl apply -f configs/kube-apiserver-to-kubelet.yaml \
  --kubeconfig admin.kubeconfig
```

## The Kubernetes Frontend Load Balancer

In this section you set up a load balancer to front the three Kubernetes API Servers.

### Provision a Network Load Balancer

A network load balancer works at [layer 4](https://en.wikipedia.org/wiki/Transport_layer) (TCP).
It passes traffic straight through to the back-end servers without touching TLS, so clients still
authenticate to the API servers with their own certificates.

Log in to the `loadbalancer` node:

```bash
ssh loadbalancer
```

[//]: # (host:loadbalancer)

```bash
sudo dnf install -y haproxy
```

SELinux is enforcing on this node, as Fedora ships it. Its policy lets HAProxy bind and connect only to the ports of well-known web services, and 6443 is not one of them. Without the change below, HAProxy refuses to start, and the journal shows the reason:

```text
[ALERT] : Binding [/etc/haproxy/haproxy.cfg:11] for frontend kubernetes: protocol tcpv4: cannot bind socket (Permission denied)
```

The `Permission denied` comes from SELinux, not from file permissions. Let HAProxy use any port:

```bash
sudo setsebool -P haproxy_connect_any 1
```

Read the addresses of the control plane nodes into shell variables:

```bash
CONTROL01=$(dig +short controlplane01)
CONTROL02=$(dig +short controlplane02)
CONTROL03=$(dig +short controlplane03)
LOADBALANCER=$(dig +short loadbalancer)
```

Configure HAProxy to listen on the API server port and spread connections across the three control
plane nodes. `mode tcp` makes it a layer 4 load balancer: it forwards the traffic as-is and does no
[TLS offloading](https://en.wikipedia.org/wiki/TLS_termination_proxy).

```bash
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    log /dev/log local0

defaults
    log     global
    timeout connect 5s
    timeout client  1h
    timeout server  1h

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

The one-hour client and server timeouts are deliberate. `kubectl logs -f`, `exec` and every
controller's watch keep a connection open for a long time, and a short timeout cuts them off in
the middle.

```bash
sudo systemctl enable --now haproxy
```

### Verification

[//]: # (sleep:2)

Make an HTTPS request for the Kubernetes version info through the load balancer:

```bash
curl -k https://${LOADBALANCER}:6443/version
```

```text
{
  "major": "1",
  "minor": "37",
  "gitVersion": "v1.37.1",
  ...
  "platform": "linux/amd64"
}
```

Next: [Bootstrapping the Kubernetes Worker Nodes](09-bootstrapping-kubernetes-workers.md)<br>
Prev: [Bootstrapping the etcd Cluster](07-bootstrapping-etcd.md)
