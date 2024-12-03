# Deploy Liferay

In this lab you will complete a series of tasks to ensure your Kubernetes cluster is functioning correctly.

## Infrastructure Deployment

In this section several infrastructure components will be deployed to support deployment in the Kubernetes cluster.

### Calico CNI

The Calico CNI plugin provides a container network infrastructure to allow services to communicate with each other.  Once deployed the Kubernetes node state will switch to Ready indicating they are ready for deployment.

[//]: # (host:controlplane01)

Deploy the `Calico` cluster add-on:

Note that if you have [changed the service CIDR range](./01-prerequisites.md#service-network) and thus this file, you will need to save your copy onto `controlplane01` (paste to vim, then save) and apply that.

```bash
kubectl create -f ~/infra/tigera-operator.yaml 
kubectl create -f ~/infra/custom-resources.yaml
```

### CoreDNS

[//]: # (host:controlplane01)

Deploy the `CoreDNS` cluster add-on:

Note that if you have [changed the service CIDR range](./01-prerequisites.md#service-network) and thus this file, you will need to save your copy onto `controlplane01` (paste to vim, then save) and apply that.

```bash
kubectl apply -f ~/infra/coredns.yaml
```

### Local Path Storage

Local Path storage provides a way to mount volumes in a local cluster for any services that need them.

Deploy the `Local Path Storage` cluster add-on:

```bash
kubectl apply -f ~/infra/local-path-storage.yaml
```

### Verification

Run the following to verify that the infrastructure components have been deploying properly:

```bash
kubectl get pods --all-namespaces
```

> output

```
NAMESPACE            NAME                                       READY   STATUS      RESTARTS       AGE
calico-apiserver     calico-apiserver-b4676fc7b-xzrph           1/1     Running     2 (138m ago)   6h1m
calico-apiserver     calico-apiserver-b4676fc7b-zvwrv           1/1     Running     2 (138m ago)   6h1m
calico-system        calico-kube-controllers-7d868b8f66-mbnsk   1/1     Running     1 (139m ago)   6h2m
calico-system        calico-node-5lv22                          1/1     Running     1 (139m ago)   6h2m
calico-system        calico-node-hpwfm                          1/1     Running     1 (139m ago)   6h2m
calico-system        calico-typha-6fc47c4db6-skb78              1/1     Running     1 (139m ago)   6h2m
calico-system        csi-node-driver-2p8n9                      2/2     Running     2 (139m ago)   6h2m
calico-system        csi-node-driver-847c8                      2/2     Running     2 (139m ago)   6h2m
kube-system          coredns-f5799776f-4kv6s                    1/1     Running     2 (139m ago)   6h24m
kube-system          coredns-f5799776f-fs7hm                    1/1     Running     2 (139m ago)   6h24m
local-path-storage   local-path-provisioner-dbff48958-pbbk4     1/1     Running     3 (138m ago)   6h24m
tigera-operator      tigera-operator-b974bcbbb-jmwzs            1/1     Running     2 (126m ago)   6h2m
```

List the nodes in the remote Kubernetes cluster:

```bash
kubectl get nodes
```

> output

```
NAME       STATUS      ROLES    AGE    VERSION
node01     Ready       <none>   118s   v1.28.4
node02     Ready       <none>   118s   v1.28.4
```

The nodes should now be in a ready status since the Calico CNI plugin provides service to service networking which is needed for the nodes to function.

## Liferay Deployment

In this section you will verify the ability to create and manage [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

Deploy Liferay dependencies by running the following:

```bash
kubectl create namespace liferay
kubectl apply -k ~/liferay -n=liferay
```

[//]: # (command:kubectl wait deployment -n default nginx --for condition=Available=True --timeout=90s)

List the pods created by the deployment:

```bash
watch kubectl get pods -n liferay
```

> output

```
NAME                        READY   STATUS    RESTARTS   AGE
database-59cf69b794-w78vv   1/1     Running   0          2m19s
search-5bb7758db9-5zk6c     1/1     Running   0          2m19s
```

Once the above pods are running, deploy Liferay by running the following:

```bash
kubectl apply -f ~/liferay/liferay.yaml -n=liferay
```

List the pods created by the deployment:

```bash
watch kubectl get pods -n liferay
```

> output

```
NAME                        READY   STATUS    RESTARTS   AGE
database-59cf69b794-gs78m   1/1     Running     0          115m
liferay-6d6d777465-zndxs    1/1     Running     0          114m
search-5bb7758db9-w7rkd     1/1     Running     0          115m
```

### Services

In this section you will verify the ability to access applications remotely using [port forwarding](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/).

Create a service to expose deployment liferay on node ports.

```bash
kubectl expose deploy liferay --type=NodePort --port 8080 -n=liferay
```

Find the port used to access the Liferay Service:

[//]: # (command:sleep 2)

```bash
kubectl get service liferay -n=liferay
```

> output

```
NAME      TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
liferay   NodePort   10.96.236.85   <none>        8080:31759/TCP   51m
```

From the host access the Liferay Service using the following:

`$NODE01` and `$NODE02` are the IPs that were set for each node and `$PORT_NUMBER` is obtained from the output above.  For example:

* 192.168.100.21:31759
* 192.168.100.22:31759

```bash
$NODE01:$PORT_NUMBER
$NODE02:$PORT_NUMBER
```
Prev: [Configuring kubectl for Remote Access](./10-configuring-kubectl.md)
