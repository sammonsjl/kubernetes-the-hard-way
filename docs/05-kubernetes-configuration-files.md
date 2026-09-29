# Lab 5 — Generating Kubernetes Configuration Files for Authentication

## What you will have at the end

A [kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) for each kubelet, kube-proxy, kube-controller-manager, kube-scheduler and the `admin` user, copied to the nodes that use it. A kubeconfig tells a Kubernetes client where to find the API server and how to authenticate to it.

## Client Authentication Configs

In this section you will generate kubeconfig files for the `controller manager`, `kube-proxy`, `scheduler` clients and the `admin` user.  Run the commands in this lab on `controlplane01`.

[//]: # (host:controlplane01)

```bash
LOADBALANCER=$(dig +short loadbalancer)
```

### The kubelet Kubernetes Configuration File

When generating kubeconfig files for Kubelets the client certificate matching the Kubelets node name must be used. This will ensure Kubelets are properly authorized by the Kubernetes [Node Authorizer](https://kubernetes.io/docs/admin/authorization/node/).

Generate a kubeconfig file for worker node01 and node02:

```bash
for instance in node01 node02; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://${LOADBALANCER}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=/var/lib/kubernetes/pki/${instance}.crt \
    --client-key=/var/lib/kubernetes/pki/${instance}.key \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=${instance}.kubeconfig
done
```

Results:

```text
node01.kubeconfig
node02.kubeconfig
```

### The kube-proxy Kubernetes Configuration File

Generate a kubeconfig file for the `kube-proxy` service:

```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://${LOADBALANCER}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=/var/lib/kubernetes/pki/kube-proxy.crt \
    --client-key=/var/lib/kubernetes/pki/kube-proxy.key \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}
```

Results:

```
kube-proxy.kubeconfig
```

Reference docs for kube-proxy [here](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/)

### The kube-controller-manager Kubernetes Configuration File

Generate a kubeconfig file for the `kube-controller-manager` service:

```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=/var/lib/kubernetes/pki/kube-controller-manager.crt \
    --client-key=/var/lib/kubernetes/pki/kube-controller-manager.key \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
```

Results:

```
kube-controller-manager.kubeconfig
```

Reference docs for kube-controller-manager [here](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)

### The kube-scheduler Kubernetes Configuration File

Generate a kubeconfig file for the `kube-scheduler` service:

```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=/var/lib/kubernetes/pki/kube-scheduler.crt \
    --client-key=/var/lib/kubernetes/pki/kube-scheduler.key \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}
```

Results:

```
kube-scheduler.kubeconfig
```

Reference docs for kube-scheduler [here](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/)

### The admin Kubernetes Configuration File

Generate a kubeconfig file for the `admin` user:

```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}
```

Results:

```
admin.kubeconfig
```

Reference docs for kubeconfig [here](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)

## Distribute the Kubernetes Configuration Files

Copy the appropriate `kube-proxy` kubeconfig files to each worker instance:

```bash
for instance in node01 node02; do
  scp kube-proxy.kubeconfig ${instance}.kubeconfig ${instance}:~/
done
```

Copy the appropriate `admin.kubeconfig`, `kube-controller-manager` and `kube-scheduler` kubeconfig files to each controller instance:

```bash
for instance in controlplane01 controlplane02 controlplane03; do
  scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ${instance}:~/
done
```

Notice which server each kubeconfig points at. The kubelets and kube-proxy run on the workers, so they reach the API through the load balancer. The controller manager, the scheduler and `admin.kubeconfig` are used on the control plane nodes themselves, so they talk to the local API server on `127.0.0.1`.

## Optional: check the kubeconfigs

[//]: # (command:./cert_verify.sh 2)
[//]: # (command:ssh controlplane02 './cert_verify.sh 2')

```bash
./cert_verify.sh 2
ssh controlplane02 ./cert_verify.sh 2
ssh controlplane03 ./cert_verify.sh 2
```

Next: [Generating the Data Encryption Config and Key](./06-data-encryption-keys.md)<br>
Prev: [Certificate Authority](./04-certificate-authority.md)
