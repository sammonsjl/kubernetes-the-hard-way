# Lab 12 — Deploy Ghost

## What you will have at the end

[Ghost](https://ghost.org/), the open source publishing platform, running on your cluster with a
MySQL database behind it. It is served to your workstation's browser through the same load
balancer that fronts the API servers.

Along the way the deployment exercises most of what you built by hand:

| What Ghost needs                                   | What provides it                                     | Built in |
| -------------------------------------------------- | ---------------------------------------------------- | -------- |
| A database password that isn't stored in the clear | Secrets encrypted at rest in etcd                    | Lab 6    |
| Pods scheduled onto the workers                    | the scheduler and the kubelets                       | Labs 8–9 |
| Ghost reaching MySQL as `mysql`                    | a Service, CoreDNS, and kube-proxy's rules           | Labs 9, 11 |
| Ghost's pod reaching MySQL's on another node       | the Calico pod network                               | Lab 11   |
| Somewhere to keep the data                         | PersistentVolumeClaims and local-path-provisioner    | Lab 11   |
| A way in from outside the cluster                  | a NodePort Service, and HAProxy on `loadbalancer`    | Lab 8    |
| `kubectl logs`, `exec` and `port-forward`          | the API server reaching the kubelets over TLS        | Labs 4, 8 |

[//]: # (host:controlplane01)

Run the commands in this lab on `controlplane01`, except where it says otherwise.

## The namespace, the Secret and the ConfigMap

Keep everything for the application in its own namespace:

```bash
kubectl create namespace ghost
```

MySQL needs a root password and a password for the `ghost` user it creates, and Ghost needs the
second one to connect. Generate both, and store them only in a Secret:

```bash
kubectl create secret generic ghost-db -n ghost \
  --from-literal=password="$(openssl rand -hex 16)" \
  --from-literal=root-password="$(openssl rand -hex 16)"
```

### Is the Secret encrypted?

In Lab 6 you gave the API servers an encryption key, and told them to use it for Secrets. Read the
Secret straight out of etcd, bypassing the API, and look at the first bytes:

```bash
sudo etcdctl get /registry/secrets/ghost/ghost-db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key \
  --print-value-only | head -c 40 | hexdump -C
```

```text
00000000  6b 38 73 3a 65 6e 63 3a  61 65 73 63 62 63 3a 76  |k8s:enc:aescbc:v|
00000010  31 3a 6b 65 79 31 3a d9  5c 5a d4 87 95 ef d0 b4  |1:key1:.\Z......|
00000020  fd cd 12 c2 bf 54 e7 59                           |.....T.Y|
00000028
```

The prefix `k8s:enc:aescbc:v1:key1` says the value was encrypted with the `aescbc` provider using
the key named `key1`. Everything after it is ciphertext. Without Lab 6, this would be the Secret's
YAML with the passwords in plain base64, readable by anyone who can read etcd or its backups.

### Ghost's URL

Ghost writes its own address into every link, redirect and asset path it generates, so it needs to
know the address readers will use. That is the load balancer, which you will point at Ghost at the
end of this lab:

```bash
kubectl create configmap ghost-config -n ghost \
  --from-literal=url="http://$(dig +short loadbalancer)"
```

## Deploy MySQL and Ghost

Look at the manifests before applying them:

```bash
cat ghost/mysql.yaml ghost/ghost.yaml
```

A few things to notice:

- Each application has a Deployment, a Service and a PersistentVolumeClaim, and both Deployments
  use the `Recreate` strategy. A `ReadWriteOnce` volume can be attached to only one node at a
  time, so an update has to stop the old pod before it starts the new one.
- Ghost finds its database by the Service name, `database__connection__host: mysql`. CoreDNS
  resolves that name to the Service's cluster IP, and kube-proxy's rules forward it to MySQL's pod.
- Ghost has an init container that waits for MySQL's port to answer. Ghost exits if it can't
  connect when it starts, so without the wait the first few starts end in `CrashLoopBackOff`.
- The Ghost Service is `type: NodePort` with a fixed `nodePort: 30080`. Every node answers on that
  port and forwards to Ghost, wherever its pod is running.

`ghost/kustomization.yaml` puts both manifests in the `ghost` namespace. Apply it:

```bash
kubectl apply -k ghost/
```

```text
service/ghost created
service/mysql created
persistentvolumeclaim/ghost-content created
persistentvolumeclaim/mysql-data created
deployment.apps/ghost created
deployment.apps/mysql created
```

Wait for both rollouts. The first one pulls the MySQL and Ghost images, about 500 MB together, and
Ghost then creates its database schema before it reports ready. Allow a few minutes:

```bash
kubectl rollout status deployment/mysql -n ghost --timeout=600s
kubectl rollout status deployment/ghost -n ghost --timeout=600s
```

```bash
kubectl get pods,pvc -n ghost -o wide
```

```text
NAME                         READY   STATUS    RESTARTS   AGE     IP               NODE     NOMINATED NODE   READINESS GATES
pod/ghost-7f785c4987-vq955   1/1     Running   0          2m54s   10.244.140.69    node02   <none>           <none>
pod/mysql-877f69454-5jnt2    1/1     Running   0          2m54s   10.244.196.135   node01   <none>           <none>

NAME                                  STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE     VOLUMEMODE
persistentvolumeclaim/ghost-content   Bound    pvc-18609f53-d205-448e-a485-90ad9f93e697   1Gi        RWO            local-path     <unset>                 2m54s   Filesystem
persistentvolumeclaim/mysql-data      Bound    pvc-d0336c3f-c7bc-4653-b926-65ec626346fc   2Gi        RWO            local-path     <unset>                 2m54s   Filesystem
```

Your pod names, IP addresses and nodes will differ. If the two pods landed on different nodes,
every query Ghost makes crosses the Calico network between the workers.

## Smoke tests

### Logs

`kubectl logs` makes the API server connect to the kubelet on the pod's node and stream the log
from there. That connection needs the RBAC binding from Lab 8, and a kubelet certificate whose SAN
contains the node's IP address, from Lab 4:

```bash
kubectl logs -n ghost deployment/ghost -c ghost | grep -E 'Ghost booted|Your site is now available'
```

```text
[2026-09-29 14:30:47] INFO Your site is now available on http://192.168.100.30/
[2026-09-29 14:31:39] INFO Ghost booted in 53.76s
```

`-c ghost` picks the container. The pod also has the `wait-for-mysql` init container, and without
`-c` kubectl says which one it defaulted to.

Further down the log you will find `ERROR ... connect ECONNREFUSED 192.168.100.30:80`. Ghost
requests its own `url` after booting, and nothing is listening on the load balancer's port 80 yet.
The last section of this lab fixes that.

### Exec

Run a query inside the MySQL container. The password comes from the container's own environment,
where the Deployment put it from the Secret, so it never appears on your command line:

```bash
kubectl exec -n ghost deployment/mysql -- \
  sh -c 'mysql -ughost -p"$MYSQL_PASSWORD" ghost -e "SELECT title, status FROM posts"'
```

```text
mysql: [Warning] Using a password on the command line interface can be insecure.
title	status
Coming soon	published
About this site	published
```

Ghost created those posts when it set up its schema.

### Port forwarding

`kubectl port-forward` tunnels a local port to a pod, through the API server and the kubelet.
`socat` on the worker, installed in Lab 9, carries the last hop:

```bash
kubectl port-forward -n ghost service/ghost 8080:2368 >/dev/null &
sleep 2
curl -s http://127.0.0.1:8080/ghost/api/admin/site/ | jq -r .site.version
kill %1
```

```text
6.65
```

### NodePort

Every node answers on port 30080, and kube-proxy on that node forwards the connection to the Ghost
pod, even when the pod is on the other worker:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://node01:30080/
curl -s -o /dev/null -w '%{http_code}\n' http://node02:30080/
```

```text
200
200
```

## The front door

The NodePort answers on each worker separately. To give readers one address, put the load balancer
in front of both workers, the same way it fronts the three API servers.

Log in to the load balancer:

```bash
ssh loadbalancer
```

[//]: # (host:loadbalancer)

Read the workers' addresses:

```bash
NODE01=$(dig +short node01)
NODE02=$(dig +short node02)
LOADBALANCER=$(dig +short loadbalancer)
```

Add a second frontend to HAProxy, for web traffic on port 80. This time it runs in `mode http`:
HAProxy reads each request, and it can add the `X-Forwarded-For` header that tells Ghost the
reader's real address:

```bash
cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg

frontend ghost
    bind ${LOADBALANCER}:80
    mode http
    option httplog
    option forwardfor
    default_backend ghost-nodeport

backend ghost-nodeport
    mode http
    balance roundrobin
    option httpchk
    http-check send meth GET uri /ghost/api/admin/site/ ver HTTP/1.1 hdr Host ${LOADBALANCER}
    server node01 ${NODE01}:30080 check
    server node02 ${NODE02}:30080 check
EOF
```

The health check asks Ghost for the same endpoint its readiness probe uses. It sends an HTTP/1.1
request with a `Host` header on purpose. HAProxy's default check is an HTTP/1.0 request with no
`Host`, and Ghost answers that with `404`. Both workers would then be marked `DOWN`, and every
request to the site would get a `503` from HAProxy.

Check the configuration, then reload HAProxy without dropping connections to the API servers:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy
```

`haproxy -c` prints nothing when the file is valid, and the reload happens only if it is.

### Verification

On your **workstation**:

```bash
curl -s http://192.168.100.30/ | grep -o '<title>.*</title>'
```

```text
<title>Ghost</title>
```

Now open **http://192.168.100.30/** in your browser to see the site, and
**http://192.168.100.30/ghost/** to create the site's owner account and start writing.

> Ghost's admin login, like everything in this lab, is served over plain HTTP on a network only
> your workstation can reach. That is fine here. A real site would terminate TLS on the load
> balancer, and its `url` would start with `https://`.

## Where the data is

The provisioner created a directory on the node where each pod first ran. Find MySQL's:

```bash
kubectl get pv -o custom-columns=CLAIM:.spec.claimRef.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],PATH:.spec.hostPath.path
```

```text
CLAIM           NODE     PATH
ghost-content   node02   /opt/local-path-provisioner/pvc-18609f53-d205-448e-a485-90ad9f93e697_ghost_ghost-content
mysql-data      node01   /opt/local-path-provisioner/pvc-d0336c3f-c7bc-4653-b926-65ec626346fc_ghost_mysql-data
```

Delete the MySQL pod and watch its replacement start on the same node, with the same data:

```bash
kubectl delete pod -n ghost -l app=mysql
kubectl rollout status deployment/mysql -n ghost
kubectl get pods -n ghost -l app=mysql -o wide
```

```text
pod "mysql-877f69454-5jnt2" deleted from ghost namespace
deployment "mysql" successfully rolled out
NAME                    READY   STATUS    RESTARTS   AGE   IP               NODE     NOMINATED NODE   READINESS GATES
mysql-877f69454-lvtnp   1/1     Running   0          12s   10.244.196.136   node01   <none>           <none>
```

The node affinity on the volume is what keeps the new pod on that node. It is also the limitation
of local-path storage: if that node dies, so does the database.

Congratulations. You built a Kubernetes cluster by hand and are running a real application on it.

Next: [Cleaning Up](99-cleanup.md)<br>
Prev: [Cluster Add-ons](11-cluster-addons.md)
