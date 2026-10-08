# Lab 11 — Cluster Add-ons

## What you will have at the end

The three add-ons every workload in Lab 12 depends on, each running as pods on the cluster:

- **Calico**: the pod network. With it the nodes turn `Ready`, and pods on different nodes can
  reach each other.
- **CoreDNS**: cluster DNS. With it a pod can find a Service by name.
- **local-path-provisioner**: storage. With it a PersistentVolumeClaim gets a directory on a
  node's disk.

Up to this point, every component was a binary you installed and a unit file you wrote. From here
on, the cluster runs its own infrastructure, and you install it with `kubectl`.

[//]: # (host:controlplane01)

Run the commands in this lab on `controlplane01`.

## Calico CNI

The kubelet delegates pod networking to a [CNI](https://www.cni.dev/) plugin. When it starts a pod,
it asks the plugin to give the pod an address from the node's slice of `POD_CIDR` and to connect
it to the network. Calico provides that plugin, and routes pod traffic between the nodes by
encapsulating it in VXLAN.

Calico is installed by an operator. Install the operator first, from the manifest pinned to Calico
v3.32.2:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/tigera-operator.yaml
```

The manifest is short: a namespace, RBAC, and the operator's Deployment. It contains none of
Calico's CustomResourceDefinitions. The operator creates those itself when it starts, including
`Installation`, the resource you create next. Wait for that definition to exist and be accepted by
the API server, not just for the operator pod to be running. The pod reports ready a moment before
its CRDs are registered, and creating an `Installation` in that gap fails with `no matches for kind
"Installation"`:

```bash
until kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; do sleep 2; done
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
```

```text
customresourcedefinition.apiextensions.k8s.io/installations.operator.tigera.io condition met
```

The operator does nothing until it is told what to install. Tell it, with an `Installation`
resource whose IP pool is this cluster's pod network, `10.244.0.0/16`:

```bash
cat addons/calico-custom-resources.yaml
kubectl create -f addons/calico-custom-resources.yaml
```

> If you changed the [pod network](01-prerequisites.md#lab-defaults), change the `cidr` in this file
> to match before creating it. The IP pool cannot be changed after Calico is installed.

The operator now starts `calico-node` on every node. `calico-node` copies the CNI plugin binaries
into `/opt/cni/bin` and writes the network configuration to `/etc/cni/net.d`, the two directories
that Lab 9 created and containerd reads. This takes a minute or two, most of it spent pulling images.

The operator reports its progress in a `TigeraStatus` resource named `calico`. That resource does not exist until the operator has started working on the `Installation`, so first wait for it to be created, then for it to report `Available`:

```bash
kubectl wait --for=create tigerastatus/calico --timeout=120s
kubectl wait --for=condition=Available tigerastatus/calico --timeout=300s
```

```text
tigerastatus.operator.tigera.io/calico condition met
tigerastatus.operator.tigera.io/calico condition met
```

The nodes are now `Ready`:

```bash
kubectl get nodes
```

```text
NAME     STATUS   ROLES    AGE   VERSION
node01   Ready    <none>   9m    v1.37.1
node02   Ready    <none>   9m    v1.37.1
```

## CoreDNS

[//]: # (host:controlplane01)

Every pod's `/etc/resolv.conf` names `10.96.0.10` as its DNS server, because that is the
`clusterDNS` the kubelets were given in Lab 9. CoreDNS is what answers there. Its Service in
`addons/coredns.yaml` asks for exactly that address:

```bash
grep clusterIP addons/coredns.yaml
```

```text
  clusterIP: 10.96.0.10
```

> If you changed the [service network](01-prerequisites.md#lab-defaults), change this address to
> match first.

Deploy it:

```bash
kubectl apply -f addons/coredns.yaml
kubectl rollout status deployment/coredns -n kube-system
```

Check that a pod can resolve a Service by name. `kubernetes` in the `default` namespace is the
Service in front of the API server itself. Its full name is
`<service>.<namespace>.svc.cluster.local`:

```bash
kubectl run dnstest --image=busybox:1.37 --restart=Never --rm -it -- \
  nslookup kubernetes.default.svc.cluster.local
```

```text
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1

pod "dnstest" deleted from default namespace
```

> Use the full name with busybox. Its `nslookup` does not apply the search domains in
> `/etc/resolv.conf`, so the short name `kubernetes.default` comes back `NXDOMAIN`, even though an
> application in the same pod would resolve it. That result is a limitation of the tool, not a
> problem with CoreDNS.

## Local Path Storage

[local-path-provisioner](https://github.com/rancher/local-path-provisioner) answers a
PersistentVolumeClaim by creating a directory under `/opt/local-path-provisioner` on the node where
the pod is scheduled. The pod is then pinned to that node. It is the simplest way to give a
single-replica database somewhere to keep its data, and nothing more than that. There is no
replication, so the data is lost if the node is.

Deploy it, pinned to v0.0.37:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.37/deploy/local-path-storage.yaml
kubectl rollout status deployment/local-path-provisioner -n local-path-storage
```

It creates a StorageClass named `local-path`. Lab 12's volume claim asks for it by name:

```bash
kubectl get storageclass
```

```text
NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  10s
```

## Verification

Everything the add-ons started should be `Running`:

```bash
kubectl get pods -A
```

```text
NAMESPACE            NAME                                       READY   STATUS    RESTARTS   AGE
calico-system        calico-kube-controllers-75d8fd4f49-wnw54   1/1     Running   0          110s
calico-system        calico-node-hfp6t                          1/1     Running   0          105s
calico-system        calico-node-kztwt                          1/1     Running   0          106s
calico-system        calico-typha-7d986fb8f-nx7mv               1/1     Running   0          111s
calico-system        csi-node-driver-mqzh7                      2/2     Running   0          111s
calico-system        csi-node-driver-nkv7m                      2/2     Running   0          111s
kube-system          coredns-7868d85f5f-w756b                   1/1     Running   0          46s
kube-system          coredns-7868d85f5f-xlhfd                   1/1     Running   0          45s
local-path-storage   local-path-provisioner-7c7ff4f446-xrwhr    1/1     Running   0          11s
tigera-operator      tigera-operator-74c8fbcbcc-ftvwp           1/1     Running   0          2m32s
```

Next: [Deploy Uptime Kuma and Headlamp with Helm](12-deploy-uptime-kuma.md)<br>
Prev: [Configuring kubectl for Remote Access](10-configuring-kubectl.md)
