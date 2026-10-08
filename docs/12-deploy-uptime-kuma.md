# Lab 12 — Deploy Uptime Kuma and Headlamp with Helm

## What you will have at the end

Two applications running on your cluster, installed with [Helm](https://helm.sh/) and served to
your workstation's browser through the same load balancer that fronts the API servers:

- [Uptime Kuma](https://uptime.kuma.pet/), a status page. You will point it at the cluster's own
  API servers, then shut one of them down and watch what happens.
- [Headlamp](https://headlamp.dev/), a web UI for the cluster you built.

Between them they exercise most of what you built by hand:

| What this lab uses                                     | What provides it                                   | Built in   |
| ------------------------------------------------------ | -------------------------------------------------- | ---------- |
| Pods scheduled onto the workers                        | the scheduler and the kubelets                     | Labs 8–9   |
| A password that isn't stored in the clear              | Secrets encrypted at rest in etcd                  | Lab 6      |
| Somewhere to keep Uptime Kuma's history                | a PersistentVolumeClaim and local-path-provisioner | Lab 11     |
| Uptime Kuma finding Headlamp by its Service's name     | CoreDNS, and kube-proxy's rules                    | Labs 9, 11 |
| Its pod reaching Headlamp's on the other node          | the Calico pod network                             | Lab 11     |
| Headlamp reading the cluster as a ServiceAccount       | RBAC and service account tokens on the API servers | Labs 4, 8  |
| A way in from outside the cluster                      | NodePort Services, and HAProxy on `loadbalancer`   | Lab 8      |
| `kubectl logs`, `exec` and `port-forward`              | the API server reaching the kubelets over TLS      | Labs 4, 8  |
| The API staying up with a control plane node shut down | three etcd members and three API servers           | Labs 7, 8  |

[//]: # (host:controlplane01)

Run the commands in this lab on `controlplane01`, except where it says otherwise.

## Install Helm

Helm is a client-side tool. It renders a *chart's* templates into manifests with your values, and
sends them to the API server with the same kubeconfig `kubectl` uses. Nothing is installed on the
cluster for it. This is how software usually arrives on a cluster: a chart written by someone else,
that you configure through a values file.

Download Helm v4.3.0, check it against the published SHA-256, and install it:

```bash
wget -q --https-only -P downloads https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz
echo "86584a54def73570558f66f5111cc53dfed56689637ae32c1201205d494f54fb  downloads/helm-v4.3.0-linux-amd64.tar.gz" | sha256sum -c -
```

```text
downloads/helm-v4.3.0-linux-amd64.tar.gz: OK
```

```bash
tar -xf downloads/helm-v4.3.0-linux-amd64.tar.gz -C downloads linux-amd64/helm
sudo install -m 0755 downloads/linux-amd64/helm /usr/local/bin/
helm version --short
```

```text
v4.3.0+gbec5b06
```

Charts are published in repositories. Add the two this lab uses:

```bash
helm repo add uptime-kuma https://helm.irsigler.cloud
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
```

The Headlamp chart comes from the Headlamp project, which is a Kubernetes SIG project. The Uptime
Kuma chart is maintained by a member of its community, not by the Uptime Kuma project.

## Uptime Kuma

### The values

Every setting a chart accepts, with its default, is in the chart's own `values.yaml`.
`helm show values uptime-kuma/uptime-kuma --version 4.2.0` prints it. `apps/uptime-kuma-values.yaml`
holds only what this cluster changes. Read it:

```bash
cat apps/uptime-kuma-values.yaml
```

A few things to notice:

- **The Service** becomes a `NodePort` with a fixed port, `30080`. Every node answers on that port
  and forwards to the pod, wherever it is running.
- **The storage class.** The chart's volume claim does not name one. A cloud cluster has a default
  StorageClass, and this cluster has none, so the claim would stay `Pending`.
- **The `Recreate` strategy.** A `ReadWriteOnce` volume can be attached to only one node at a
  time, so an update has to stop the old pod before it starts the new one.

### Install the release

Keep the application in its own namespace:

```bash
kubectl create namespace uptime-kuma
```

An installed chart is a *release*, and it has a name. This one is `uptime-kuma`:

```bash
helm install uptime-kuma uptime-kuma/uptime-kuma --version 4.2.0 -n uptime-kuma -f apps/uptime-kuma-values.yaml
```

```text
NAME: uptime-kuma
LAST DEPLOYED: Thu Oct  8 01:17:20 2026
NAMESPACE: uptime-kuma
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
1. Get the application URL by running these commands:
  export NODE_PORT=$(kubectl get --namespace uptime-kuma -o jsonpath="{.spec.ports[0].nodePort}" services uptime-kuma)
  export NODE_IP=$(kubectl get nodes --namespace uptime-kuma -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
```

`deployed` means the API server accepted the manifests. It says nothing about whether the pod has
started. Wait for it. The first start pulls the image, about 200 MB:

```bash
kubectl rollout status deployment/uptime-kuma -n uptime-kuma --timeout=600s
```

```bash
kubectl get pods,pvc,svc -n uptime-kuma -o wide
```

```text
NAME                               READY   STATUS    RESTARTS   AGE   IP              NODE     NOMINATED NODE   READINESS GATES
pod/uptime-kuma-699fd5476f-smpnn   1/1     Running   0          18s   10.244.140.74   node02   <none>           <none>

NAME                                    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE   VOLUMEMODE
persistentvolumeclaim/uptime-kuma-pvc   Bound    pvc-8aaebc98-4592-49ca-87a3-001df87b77a9   1Gi        RWO            local-path     <unset>                 18s   Filesystem

NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE   SELECTOR
service/uptime-kuma   NodePort   10.96.140.210   <none>        3001:30080/TCP   18s   app.kubernetes.io/instance=uptime-kuma,app.kubernetes.io/name=uptime-kuma
```

Your pod name, addresses and node will differ.

### The chart's own test

A chart can carry test pods, which `helm test` runs against the release. This chart has one. It
fetches the front page from the `uptime-kuma` Service by name, so it exercises CoreDNS and
kube-proxy from inside the cluster:

```bash
helm test uptime-kuma -n uptime-kuma
```

```text
NAME: uptime-kuma
LAST DEPLOYED: Thu Oct  8 01:17:20 2026
NAMESPACE: uptime-kuma
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE:     uptime-kuma-test-connection
Last Started:   Thu Oct  8 01:17:38 2026
Last Completed: Thu Oct  8 01:17:42 2026
Phase:          Succeeded
```

## The administrator and the monitors

Uptime Kuma starts with no user and nothing to watch. Generate a password for its administrator,
and keep it in a Secret, so you can read it back when you sign in:

```bash
kubectl create secret generic uptime-kuma-admin -n uptime-kuma \
  --from-literal=username=admin \
  --from-literal=password="$(openssl rand -hex 12)"
```

### Is the Secret encrypted?

In Lab 6 you gave the API servers an encryption key, and told them to use it for Secrets. Read the
Secret straight out of etcd, bypassing the API, and look at the first bytes:

```bash
sudo etcdctl get /registry/secrets/uptime-kuma/uptime-kuma-admin \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key \
  --print-value-only | head -c 40 | hexdump -C
```

```text
00000000  6b 38 73 3a 65 6e 63 3a  61 65 73 63 62 63 3a 76  |k8s:enc:aescbc:v|
00000010  31 3a 6b 65 79 31 3a ce  05 7f 24 85 34 cb 61 b3  |1:key1:...$.4.a.|
00000020  e0 65 b8 d8 23 4a ba 92                           |.e..#J..|
00000028
```

The prefix `k8s:enc:aescbc:v1:key1` says the value was encrypted with the `aescbc` provider using
the key named `key1`. Everything after it is ciphertext. Without Lab 6, this would be the Secret's
YAML with the password in plain base64, readable by anyone who can read etcd or its backups.

Helm relies on the same thing. It has no database of its own: each release's record, with the
chart and your values, is a Secret in the release's namespace.

```bash
kubectl get secrets -n uptime-kuma
```

```text
NAME                                TYPE                 DATA   AGE
sh.helm.release.v1.uptime-kuma.v1   helm.sh/release.v1   1      23s
uptime-kuma-admin                   Opaque               2      0s
```

### Create them

Uptime Kuma has no command line for adding a user or a monitor. Its web page does everything over
a WebSocket. `apps/uptime-kuma-monitors.js` speaks the same protocol, with the client library
Uptime Kuma ships for its own page, so it has to run inside the pod. Read it, then run it there
with `kubectl exec`, feeding it the script on standard input and the node addresses in its
environment:

```bash
cat apps/uptime-kuma-monitors.js
```

```bash
kubectl exec -i -n uptime-kuma deployment/uptime-kuma -- env \
  KUMA_USERNAME=admin \
  KUMA_PASSWORD="$(kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d)" \
  CONTROL01=$(dig +short controlplane01) \
  CONTROL02=$(dig +short controlplane02) \
  CONTROL03=$(dig +short controlplane03) \
  LOADBALANCER=$(dig +short loadbalancer) \
  CLUSTER_DNS=10.96.0.10 \
  node - < apps/uptime-kuma-monitors.js
```

```text
created the administrator admin
added    API server on controlplane01
added    API server on controlplane02
added    API server on controlplane03
added    API through the load balancer
added    Cluster DNS
added    Headlamp
```

> If you changed the [service network](01-prerequisites.md#lab-defaults), change `CLUSTER_DNS` to
> match.

Six monitors, each checked every 20 seconds:

- One for each API server's `/readyz`, asked directly at its own address.
- One for `/readyz` through the load balancer, which is how every client really reaches the API.
- One that asks CoreDNS to resolve `kubernetes.default.svc.cluster.local`.
- One that fetches Headlamp's front page by its Service name. Headlamp is not installed yet.

### What they say

Uptime Kuma publishes its monitors' state as Prometheus metrics, behind the administrator's
password. Give them half a minute to make their first checks, then read them:

```bash
sleep 30
PASSWORD=$(kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d)
curl -s -u "admin:${PASSWORD}" http://node01:30080/metrics | grep '^monitor_status' | sed -E 's/.*monitor_name="([^"]*)".* ([0-9])$/\2  \1/'
```

```text
1  API server on controlplane01
1  API server on controlplane02
1  API server on controlplane03
1  API through the load balancer
1  Cluster DNS
0  Headlamp
```

`1` is up and `0` is down. Five are up. Headlamp is down because there is no such Service for
CoreDNS to answer for. You will fix that at the end of this lab.

That `curl` went to `node01` on the NodePort. Every node answers on port 30080, and kube-proxy on
that node forwards the connection to the pod, even when the pod is on the other worker.

## Smoke tests

### Logs

`kubectl logs` makes the API server connect to the kubelet on the pod's node and stream the log
from there. That connection needs the RBAC binding from Lab 8, and a kubelet certificate whose SAN
contains the node's IP address, from Lab 4:

```bash
kubectl logs -n uptime-kuma deployment/uptime-kuma | grep -E 'Uptime Kuma Version|Added Monitor'
```

Uptime Kuma colours its log. Without the colours, it reads:

```text
2026-10-08T01:17:27Z [SERVER] INFO: Uptime Kuma Version: 2.5.0
2026-10-08T01:17:45Z [MONITOR] INFO: Added Monitor: 1 User ID: 1
2026-10-08T01:17:45Z [MONITOR] INFO: Added Monitor: 2 User ID: 1
2026-10-08T01:17:45Z [MONITOR] INFO: Added Monitor: 3 User ID: 1
2026-10-08T01:17:45Z [MONITOR] INFO: Added Monitor: 4 User ID: 1
2026-10-08T01:17:45Z [MONITOR] INFO: Added Monitor: 5 User ID: 1
2026-10-08T01:17:45Z [MONITOR] INFO: Added Monitor: 6 User ID: 1
```

### Exec

Uptime Kuma keeps everything in one SQLite database, on the volume:

```bash
kubectl exec -n uptime-kuma deployment/uptime-kuma -- ls -sh /app/data
```

```text
total 2.0M
4.0K db-config.json
4.0K docker-tls
 60K kuma.db
 32K kuma.db-shm
1.9M kuma.db-wal
4.0K screenshots
4.0K upload
```

### Port forwarding

`kubectl port-forward` tunnels a local port to a pod, through the API server and the kubelet.
`socat` on the worker, installed in Lab 9, carries the last hop:

```bash
kubectl port-forward -n uptime-kuma service/uptime-kuma 3001:3001 >/dev/null &
sleep 2
curl -s http://127.0.0.1:3001/api/entry-page; echo
kill %1
```

```text
{"type":"entryPage","entryPage":null}
```

## Where the data is

The provisioner created a directory on the node where the pod first ran. Find it:

```bash
kubectl get pv -o custom-columns=CLAIM:.spec.claimRef.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],PATH:.spec.hostPath.path
```

```text
CLAIM             NODE     PATH
uptime-kuma-pvc   node02   /opt/local-path-provisioner/pvc-8aaebc98-4592-49ca-87a3-001df87b77a9_uptime-kuma_uptime-kuma-pvc
```

Delete the pod and watch its replacement start on the same node:

```bash
kubectl delete pod -n uptime-kuma -l app.kubernetes.io/name=uptime-kuma
kubectl rollout status deployment/uptime-kuma -n uptime-kuma
kubectl get pods -n uptime-kuma -o wide
```

```text
pod "uptime-kuma-699fd5476f-smpnn" deleted from uptime-kuma namespace
pod "uptime-kuma-test-connection" deleted from uptime-kuma namespace
Waiting for deployment "uptime-kuma" rollout to finish: 0 of 1 updated replicas are available...
deployment "uptime-kuma" successfully rolled out
NAME                           READY   STATUS    RESTARTS   AGE   IP              NODE     NOMINATED NODE   READINESS GATES
uptime-kuma-699fd5476f-5x2fp   1/1     Running   0          12s   10.244.140.75   node02   <none>           <none>
```

The second pod deleted was the finished test pod from `helm test`, which carries the same label.
The new pod is a fresh container, and it still knows its administrator and its six monitors,
because they are in the database on the volume. Run the script again to see:

```bash
kubectl exec -i -n uptime-kuma deployment/uptime-kuma -- env \
  KUMA_USERNAME=admin \
  KUMA_PASSWORD="$(kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d)" \
  CONTROL01=$(dig +short controlplane01) \
  CONTROL02=$(dig +short controlplane02) \
  CONTROL03=$(dig +short controlplane03) \
  LOADBALANCER=$(dig +short loadbalancer) \
  CLUSTER_DNS=10.96.0.10 \
  node - < apps/uptime-kuma-monitors.js
```

```text
exists   API server on controlplane01
exists   API server on controlplane02
exists   API server on controlplane03
exists   API through the load balancer
exists   Cluster DNS
exists   Headlamp
```

The node affinity on the volume is what keeps the new pod on that node. It is also the limitation
of local-path storage: if that node dies, so does the data.

## Headlamp

Headlamp shows the cluster in a browser: nodes, pods, logs, and every object you created in these
labs. Its values file only gives its Service a fixed NodePort, `30081`:

```bash
cat apps/headlamp-values.yaml
kubectl create namespace headlamp
helm install headlamp headlamp/headlamp --version 0.45.0 -n headlamp -f apps/headlamp-values.yaml
kubectl rollout status deployment/headlamp -n headlamp --timeout=600s
```

Count what the chart created, by kind:

```bash
helm get manifest headlamp -n headlamp | grep '^kind:' | sort | uniq -c
```

```text
      1 kind: ClusterRoleBinding
      1 kind: Deployment
      1 kind: Secret
      1 kind: Service
      1 kind: ServiceAccount
```

The ClusterRoleBinding is the one to look at:

```bash
kubectl get clusterrolebinding headlamp-admin -o wide
```

```text
NAME             ROLE                        AGE   USERS   GROUPS   SERVICEACCOUNTS
headlamp-admin   ClusterRole/cluster-admin   11s                    headlamp/headlamp
```

The chart binds Headlamp's ServiceAccount to `cluster-admin`. Headlamp has no users of its own.
You sign in to it with a Kubernetes token, and it passes that token to the API server with every
request, so what you can see and do is whatever that token's owner may. A token for the `headlamp`
ServiceAccount is therefore a key to the whole cluster. That is convenient in a lab that only your
workstation can reach, and something to change anywhere else.

Uptime Kuma has been asking for Headlamp every 20 seconds. Wait half a minute, and look again:

```bash
sleep 30
PASSWORD=$(kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d)
curl -s -u "admin:${PASSWORD}" http://node01:30080/metrics | grep '^monitor_status' | sed -E 's/.*monitor_name="([^"]*)".* ([0-9])$/\2  \1/'
```

```text
1  API server on controlplane01
1  API server on controlplane02
1  API server on controlplane03
1  API through the load balancer
1  Cluster DNS
1  Headlamp
```

The sixth monitor is up. A pod in one namespace found a Service in another by name, through
CoreDNS, and reached a pod behind it over the Calico network.

## The front door

The NodePorts answer on each worker separately. To give each application one address, put the load
balancer in front of both workers, the same way it fronts the three API servers.

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

Add two more frontends to HAProxy: port 80 for Uptime Kuma and port 8080 for Headlamp. These run in
`mode http`: HAProxy reads each request, and it can add the `X-Forwarded-For` header that tells
the application the reader's real address:

```bash
cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg

frontend uptime-kuma
    bind ${LOADBALANCER}:80
    mode http
    option httplog
    option forwardfor
    default_backend uptime-kuma-nodeport

backend uptime-kuma-nodeport
    mode http
    balance roundrobin
    option httpchk
    http-check send meth GET uri /api/entry-page ver HTTP/1.1 hdr Host ${LOADBALANCER}
    server node01 ${NODE01}:30080 check
    server node02 ${NODE02}:30080 check

frontend headlamp
    bind ${LOADBALANCER}:8080
    mode http
    option httplog
    option forwardfor
    default_backend headlamp-nodeport

backend headlamp-nodeport
    mode http
    balance roundrobin
    option httpchk
    http-check send meth GET uri / ver HTTP/1.1 hdr Host ${LOADBALANCER}
    server node01 ${NODE01}:30081 check
    server node02 ${NODE02}:30081 check
EOF
```

The health checks send an HTTP/1.1 request with a `Host` header on purpose. HAProxy's default check
is an HTTP/1.0 request with no `Host`, which many applications refuse. Uptime Kuma's check asks for
`/api/entry-page` because `/` answers with a redirect, and a check expects a `200`.

Both pages keep a WebSocket open to their server. The `timeout client` and `timeout server` of one
hour, which Lab 8 set for long `kubectl` connections, keep those open too.

Check the configuration, then reload HAProxy without dropping connections to the API servers:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy
```

`haproxy -c` prints nothing when the file is valid, and the reload happens only if it is. Give
HAProxy a few seconds after the reload to finish its first health checks. Until a worker has
passed, it answers `503`.

### Verification

On your **workstation**:

```bash
curl -s http://192.168.100.30/api/entry-page; echo
curl -s http://192.168.100.30:8080/ | grep -o '<title>.*</title>'
```

```text
{"type":"entryPage","entryPage":null}
<title>Headlamp</title>
```

## Sign in

[//]: # (host:controlplane01)

Back on `controlplane01` (`exit` leaves the load balancer).

**Uptime Kuma** is at **http://192.168.100.30/**. The username is `admin`, and the password is the
one in the Secret:

```bash
kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d; echo
```

**Headlamp** is at **http://192.168.100.30:8080/**. It asks for a token. Ask the API server to
issue one for Headlamp's ServiceAccount, valid for a day:

```bash
kubectl create token headlamp -n headlamp --duration=24h
```

Paste the whole output into Headlamp's sign-in page. The token is signed with the service account
key from Lab 4, and the API servers check it with the matching certificate.

> Both sign-ins, like everything in this lab, are served over plain HTTP on a network only your
> workstation can reach. That is fine here. A real site would terminate TLS on the load balancer.

## Break something

Three control plane nodes are there so that one can fail. Keep Uptime Kuma's dashboard open in
your browser, and take one away.

On your **workstation**, shut down `controlplane02`. Not `controlplane01`, which is where you are
running `kubectl`:

```bash
virsh -c qemu:///system shutdown kthw-controlplane02
```

Within a minute, the bar for *API server on controlplane02* turns red in the dashboard. Back on
`controlplane01`, read the same thing from the metrics:

```bash
sleep 60
PASSWORD=$(kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d)
curl -s -u "admin:${PASSWORD}" http://node01:30080/metrics | grep '^monitor_status' | sed -E 's/.*monitor_name="([^"]*)".* ([0-9])$/\2  \1/'
```

```text
1  API server on controlplane01
0  API server on controlplane02
1  API server on controlplane03
1  API through the load balancer
1  Cluster DNS
1  Headlamp
```

One API server is down, and *API through the load balancer* is still up. HAProxy's own health
check noticed the dead server and stopped sending it connections. `kubectl` uses the same address,
so it still works:

```bash
kubectl get nodes
```

```text
NAME     STATUS   ROLES    AGE   VERSION
node01   Ready    <none>   11m   v1.37.1
node02   Ready    <none>   11m   v1.37.1
```

So does everything behind the API. etcd lost one of its three members and still has the two it
needs to agree on a write:

```bash
sudo etcdctl endpoint health --cluster \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key 2>&1 | grep -E -o 'https://[0-9.:]+ is [a-z]+'
```

```text
https://192.168.100.11:2379 is healthy
https://192.168.100.13:2379 is healthy
https://192.168.100.12:2379 is unhealthy
```

Shutting down a second control plane node would leave etcd with one member of three. It would stop
accepting writes, and the API with it.

Bring the node back. On your **workstation**:

```bash
virsh -c qemu:///system start kthw-controlplane02
```

Every service on it was enabled in systemd in Labs 7 and 8, so it rejoins on its own. Give it a
minute, and the bar turns green again:

```bash
sleep 60
PASSWORD=$(kubectl get secret uptime-kuma-admin -n uptime-kuma -o jsonpath='{.data.password}' | base64 -d)
curl -s -u "admin:${PASSWORD}" http://node01:30080/metrics | grep '^monitor_status' | sed -E 's/.*monitor_name="([^"]*)".* ([0-9])$/\2  \1/'
```

```text
1  API server on controlplane01
1  API server on controlplane02
1  API server on controlplane03
1  API through the load balancer
1  Cluster DNS
1  Headlamp
```

Congratulations. You built a highly available Kubernetes cluster by hand, and you have just watched
it survive losing a control plane node.

Next: [Cleaning Up](99-cleanup.md)<br>
Prev: [Cluster Add-ons](11-cluster-addons.md)
