# Lab 10 — Configuring kubectl for Remote Access

## What you will have at the end

A default kubeconfig on `controlplane01` for the `admin` user, pointed at the load balancer rather
than at the local API server. After this, `kubectl` works with no `--kubeconfig` flag, and it keeps
working if any one control plane node goes down.

> Run the commands in this lab from the same directory you generated the admin client certificate
> in, which is the home directory on `controlplane01`.

## The Admin Kubernetes Configuration File

Every kubeconfig names an API server to connect to. For high availability, this one uses the
address of the load balancer in front of the API servers.

[//]: # (host:controlplane01)

On `controlplane01`, get the load balancer's address:

```bash
LOADBALANCER=$(dig +short loadbalancer)
```

Generate a kubeconfig for the `admin` user. Without `--kubeconfig`, `kubectl config` writes to
`~/.kube/config`, the file `kubectl` reads by default:

```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://${LOADBALANCER}:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

  kubectl config use-context kubernetes-the-hard-way
}
```

`--embed-certs` copies the certificate and key into the kubeconfig, so it keeps working if the
`.crt` and `.key` files in the home directory are moved or deleted.

Reference doc for kubectl config
[here](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/).

## Verification

Check the health of the cluster through the load balancer:

```bash
kubectl get --raw='/readyz'; echo
```

```text
ok
```

List the nodes:

```bash
kubectl get nodes
```

```text
NAME     STATUS     ROLES    AGE   VERSION
node01   NotReady   <none>   2m    v1.37.1
node02   NotReady   <none>   2m    v1.37.1
```

The nodes are still `NotReady`, because there is no pod networking yet. The next lab installs it.

Check that the server and client versions match:

```bash
kubectl version
```

```text
Client Version: v1.37.1
Kustomize Version: v5.8.1
Server Version: v1.37.1
```

Next: [Cluster Add-ons](11-cluster-addons.md)<br>
Prev: [Bootstrapping the Kubernetes Worker Nodes](09-bootstrapping-kubernetes-workers.md)
