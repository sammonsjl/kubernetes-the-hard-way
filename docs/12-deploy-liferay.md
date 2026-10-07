# Lab 12 — Deploy Liferay with Helm

## What you will have at the end

[Liferay](https://www.liferay.com/), a large Java application, running on your cluster. It runs
from a container image you build yourself, from a Liferay compiled from source, and it is installed
by Liferay's own Helm chart, `liferay-default`. It is served to your workstation's browser through
the same load balancer that fronts the API servers.

This is how software usually arrives on a cluster: a chart written by someone else, for clusters
much larger than this one, that you configure through a values file. It exercises most of what you
built by hand:

| What this lab uses                                       | What provides it                                  | Built in   |
| -------------------------------------------------------- | ------------------------------------------------- | ---------- |
| An image that is in no registry                          | containerd's image store on the worker            | Lab 9      |
| A StatefulSet, whose pod has a volume claim of its own   | the controller manager, and local-path-provisioner | Labs 8, 11 |
| A pod that fits on only one of the two workers           | the scheduler                                     | Labs 2, 8  |
| An init container that prepares the volume               | the kubelet and containerd                        | Lab 9      |
| A ServiceAccount, a Role and a RoleBinding               | RBAC on the API servers                           | Lab 8      |
| A password and a release record that aren't stored in the clear | Secrets, encrypted at rest in etcd         | Lab 6      |
| One pod finding another by its Service's name            | the Calico pod network, CoreDNS, and kube-proxy   | Labs 9, 11 |
| A way in from outside the cluster                        | a NodePort Service, and HAProxy on `loadbalancer` | Lab 8      |
| `kubectl logs`, `exec` and `port-forward`                | the API server reaching the kubelets over TLS     | Labs 4, 8  |

Liferay is heavy. Its pod uses about 3.5 GiB, and its first start takes about ten minutes. That is
why `node02` has 5.5 GB in `terraform/kvm/variables.tf`, and it is the only node the pod fits on.

To keep it to one pod, this lab runs Liferay the way a developer's laptop does: with its embedded
HSQL database, and with the Elasticsearch it starts for itself as a child process. The chart can
run a database and a search server as pods of their own, and an installation you meant to keep
would.

## Build the image

The chart's default image is `liferay/dxp`, the commercial edition. It carries a trial licence
with an expiry date. Once that has passed, Liferay starts, then answers every request with a
redirect to a licence activation form. A Liferay you compile yourself has no licence to expire,
so this lab builds its own image from one.

### What you need

On your **workstation**:

- `podman`, `git`, `rsync`, `unzip`, `curl` and `java` on the `PATH`.
- A Liferay *bundle* built from source. That is the `bundles` folder which `ant all` writes
  beside a checkout of [liferay-portal](https://github.com/liferay/liferay-portal): a Tomcat with
  Liferay deployed in it. Compiling takes JDK 17, Ant 1.10 and a long time, and is not part of
  this lab, which starts from the finished bundle.

### Build

`liferay/build-image.sh` copies the bundle, leaving out the data, logs and state of the machine it
has been running on. It then hands the copy to
[liferay-docker](https://github.com/liferay/liferay-docker), the tooling Liferay builds its
published images with, which it clones into `~/.cache/kubernetes-the-hard-way` on first use. The
chart depends on the layout that tooling produces, such as `/opt/liferay` and its entrypoint
scripts. A plain copy of the bundle into an image would not work with it.

From the root of your clone of this repository, give it the path of your bundle:

```bash
liferay/build-image.sh ~/liferay/bundles
```

It takes a few minutes the first time, most of it downloading Liferay's JDK base image and
installing packages into it. The last line it prints is the image's name:

```text
localhost/kthw/liferay:source
```

```bash
podman images localhost/kthw/liferay
```

```text
REPOSITORY              TAG         IMAGE ID      CREATED         SIZE
localhost/kthw/liferay  source      2c81de79e8bb  10 seconds ago  3.14 GB
```

### Load it onto the worker

The image exists only in podman's storage on your workstation. A kubelet gets images from
containerd, and containerd normally pulls them from a registry. This cluster has no registry, so
put the image into containerd's store directly. `podman save` writes the image as a tar archive
and `ctr images import` reads one, so the two can be joined over SSH with nothing written to disk
between them:

```bash
podman save localhost/kthw/liferay:source | ssh node02 'sudo ctr -n k8s.io images import -'
```

That takes three or four minutes. `-n k8s.io` matters: containerd keeps separate image stores
for separate clients, and `k8s.io` is the one the kubelet reads. Imported into the default
namespace, the image would be on the node and invisible to Kubernetes.

Only `node02` needs it, because only `node02` has the memory for the pod.

Check that the kubelet's side of containerd can see it:

```bash
ssh node02 'sudo crictl images' | grep -E 'IMAGE|liferay'
```

```text
IMAGE                                      TAG                 IMAGE ID            SIZE
localhost/kthw/liferay                     source              2c81de79e8bbb       3.14GB
```

[//]: # (host:controlplane01)

The rest of this lab is run on `controlplane01`, except where it says otherwise.

## Install Helm

[Helm](https://helm.sh/) is a client-side tool. It renders a chart's templates into manifests with
your values, and sends them to the API server with the same kubeconfig `kubectl` uses. Nothing is
installed on the cluster for it.

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

## The chart

The chart's source is in Liferay's repository, under
[`cloud/helm/default`](https://github.com/liferay/liferay-portal/tree/master/cloud/helm/default).
Liferay publishes it to an OCI registry, the same kind of registry that holds container images.
Helm pulls a chart from one by its address and version, with no `helm repo add` first:

```bash
CHART=oci://us-central1-docker.pkg.dev/external-assets-prd/liferay-helm-chart/liferay-default
helm show chart $CHART --version 3.0.0
```

```text
Pulled: us-central1-docker.pkg.dev/external-assets-prd/liferay-helm-chart/liferay-default:3.0.0
Digest: sha256:8057fb259a0252e1c08d833673f9a8a7b488a560c19983977417a11f160072a5
apiVersion: v2
appVersion: latest
description: Liferay is an all-in-one DXP, LCAP, and Commerce platform.
icon: https://www-cdn.liferay.com/documents/d/guest/liferay-logo
name: liferay-default
type: application
version: 3.0.0
```

Every setting the chart accepts, with its default, is in the chart's `values.yaml`. It is about
600 lines. Look at two that cannot work here:

```bash
helm show values $CHART --version 3.0.0 2>/dev/null | grep -A6 -E '^(image|resources):'
```

```text
image:
    pullPolicy: IfNotPresent
    pullSecrets: []
    repository: liferay/dxp
    tag: 2026.q1.8-lts
initContainers: []
licensing:
--
resources:
    limits:
        cpu: 4000m
        memory: 8Gi
    requests:
        cpu: 2000m
        memory: 6Gi
```

`liferay/dxp` is the image with the licence. And a pod that requests 6Gi fits on neither worker,
so it would stay `Pending`.

## The values

`liferay/values.yaml` holds what this cluster changes. Read it:

```bash
cat liferay/values.yaml
```

A few things to notice:

- **The image** is the one you built, with `pullPolicy: Never`. The kubelet uses the copy in
  containerd, and fails at once with `ErrImageNeverPull` if it is not there. Without `Never` it
  would try to pull from a registry named `localhost` and report that failure, which says less.
- **The memory request** is close to what the pod really uses. The scheduler places pods by
  their requests, not by what they turn out to use. `node01` cannot offer 3.5 GiB, so the
  scheduler has one choice. A smaller request would let it choose `node01`, and the pod would
  run that node out of memory.
- **The storage class.** The chart's volume claim does not name one. A cloud cluster has a default
  StorageClass, and this cluster has none, so the claim would stay `Pending`.
  `persistence.defaultStorageClassName` fills it in.
- **Environment variables configure Liferay.** It reads any of its portal properties from a
  variable named `LIFERAY_` plus the property's name, with `_PERIOD_` for each dot.
- **There is no `dependencies` section**, which is where the chart would be given a database and
  a search server to run.

## The namespace and the ConfigMap

```bash
kubectl create namespace liferay
```

Liferay writes its own address into the links it generates, so it needs to know the address
readers will use. That is the load balancer, which you will point at Liferay at the end of this
lab. `customEnvFrom` in the values file turns every
key of this ConfigMap into an environment variable, so the key is the variable's name. This one is
the portal property `company.default.virtual.host.name`:

```bash
kubectl create configmap liferay-front-door -n liferay \
  --from-literal=LIFERAY_COMPANY_PERIOD_DEFAULT_PERIOD_VIRTUAL_PERIOD_HOST_PERIOD_NAME="$(dig +short loadbalancer)"
```

## Install the release

An installed chart is a *release*, and it has a name. This one is `liferay`:

```bash
helm install liferay $CHART --version 3.0.0 -n liferay -f liferay/values.yaml
```

```text
Pulled: us-central1-docker.pkg.dev/external-assets-prd/liferay-helm-chart/liferay-default:3.0.0
Digest: sha256:8057fb259a0252e1c08d833673f9a8a7b488a560c19983977417a11f160072a5
NAME: liferay
LAST DEPLOYED: Wed Oct  7 21:59:23 2026
NAMESPACE: liferay
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

The chart's Service is a ClusterIP. `liferay/nodeport.yaml` is a second Service in front of the
same pod, with a fixed node port for HAProxy to name later. The comment in the file says why it is
not part of the release. Apply it now:

```bash
cat liferay/nodeport.yaml
kubectl apply -n liferay -f liferay/nodeport.yaml
```

`deployed` in Helm's output means the API server accepted the manifests. It says nothing about
whether the pod has started. Wait for it:

```bash
kubectl rollout status statefulset/liferay-default -n liferay --timeout=1800s
```

```text
Waiting for 1 pods to be ready...
statefulset rolling update complete 1 pods at revision liferay-default-5cfcc46bf5...
```

That takes eight to ten minutes. Liferay creates its tables in an empty database, starts
Elasticsearch, starts over a thousand OSGi bundles, and builds its default sites when the first
request arrives. To watch it happen, open a second terminal on `controlplane01` and follow the log:

```text
kubectl logs -n liferay liferay-default-0 -c liferay-default -f
```

While you wait, `kubectl get pods -n liferay` shows the pod pass through `Init:0/2` and
`Init:1/2`, one for each init container, and then sit at `0/1 Running` until Liferay answers its
startup probe.

```bash
kubectl get pods,pvc -n liferay -o wide
```

```text
NAME                    READY   STATUS    RESTARTS   AGE    IP              NODE     NOMINATED NODE   READINESS GATES
pod/liferay-default-0   1/1     Running   0          9m2s   10.244.140.92   node02   <none>           <none>

NAME                                                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE    VOLUMEMODE
persistentvolumeclaim/liferay-persistent-volume-liferay-default-0   Bound    pvc-21ffb869-d930-478a-a618-917c37532042   1Gi        RWO            local-path     <unset>                 9m2s   Filesystem
```

The pod is on `node02`, as the memory request said it would be. A StatefulSet's pods are numbered,
not given random suffixes, and each claim is named for the pod it belongs to. If
`liferay-default-0` is deleted, its replacement has the same name and gets the same claim back.

## What Helm created

```bash
helm list -n liferay
```

```text
NAME   	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART                	APP VERSION
liferay	liferay  	1       	2026-10-07 21:59:23.796655245 +0000 UTC	deployed	liferay-default-3.0.0	latest
```

Helm keeps the manifests it rendered. Count them by kind:

```bash
helm get manifest liferay -n liferay | grep '^kind:' | sort | uniq -c
```

```text
      2 kind: ConfigMap
      1 kind: Role
      1 kind: RoleBinding
      1 kind: Secret
      2 kind: Service
      1 kind: ServiceAccount
      1 kind: StatefulSet
```

Nine objects from one command. The two Services are an ordinary one, and a headless one that gives
the pod a DNS name of its own.

Helm has no database of its own. The release record, with the chart, your values and those
manifests, is a Secret in the release's namespace:

```bash
kubectl get secrets -n liferay
```

```text
NAME                            TYPE                 DATA   AGE
liferay-default                 Opaque               1      9m3s
sh.helm.release.v1.liferay.v1   helm.sh/release.v1   1      9m3s
```

`liferay-default` is one the chart created. It holds a random password for Liferay's
administrator, which you will use at the end of this lab.

### Are the Secrets encrypted?

In Lab 6 you gave the API servers an encryption key, and told them to use it for Secrets. Read
the administrator's password straight out of etcd, bypassing the API, and look at the first bytes:

```bash
sudo etcdctl get /registry/secrets/liferay/liferay-default \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key \
  --print-value-only | head -c 40 | hexdump -C
```

```text
00000000  6b 38 73 3a 65 6e 63 3a  61 65 73 63 62 63 3a 76  |k8s:enc:aescbc:v|
00000010  31 3a 6b 65 79 31 3a c9  c4 49 43 69 07 63 74 bb  |1:key1:..ICi.ct.|
00000020  2b a0 e2 54 0d 3d 5f 03                           |+..T.=_.|
00000028
```

The prefix `k8s:enc:aescbc:v1:key1` says the value was encrypted with the `aescbc` provider using
the key named `key1`. Everything after it is ciphertext. Without Lab 6, this would be the Secret's
YAML with the password in plain base64, readable by anyone who can read etcd or its backups. The
release record beside it is stored the same way.

## Smoke tests

### The chart's own test

A chart can carry test pods, which `helm test` runs against the release. This chart has one. It
checks that the `liferay-default` Service accepts a connection on port 8080, so it exercises
CoreDNS and kube-proxy from inside the cluster:

```bash
helm test liferay -n liferay
```

```text
NAME: liferay
LAST DEPLOYED: Wed Oct  7 21:59:23 2026
NAMESPACE: liferay
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE:     liferay-default-test-connection
Last Started:   Wed Oct  7 22:08:28 2026
Last Completed: Wed Oct  7 22:08:34 2026
Phase:          Succeeded
```

### Logs

```bash
kubectl logs -n liferay liferay-default-0 -c liferay-default | grep -E 'Starting Liferay Digital|Server startup'
```

```text
Starting Liferay Digital Experience Platform 7.4.13 Update 152 (August 17, 2026)
07-Oct-2026 22:05:14.443 INFO [main] org.apache.catalina.startup.Catalina.start Server startup in [336932] milliseconds
```

Your version and date are those of the source you compiled.

### Exec

The Liferay container runs two Java processes: Liferay, and the Elasticsearch it started. Check
that both got the heap sizes from the values file:

```bash
kubectl exec -n liferay liferay-default-0 -c liferay-default -- \
  sh -c "ps -eo args | grep -oE -- '-Xmx[0-9]+[mg]' | tr '\n' ' '; echo"
```

```text
-Xmx2560m -Xmx2g -Xmx512m
```

The first two are the same process. `-Xmx2560m` is the image's default and `-Xmx2g` is
`LIFERAY_JVM_OPTS` from the values file. The JVM uses the last one it is given. `-Xmx512m` is
Elasticsearch. Ask it for its health, on the loopback port where Liferay talks to it:

```bash
kubectl exec -n liferay liferay-default-0 -c liferay-default -- \
  curl -s 'http://127.0.0.1:9201/_cluster/health' | jq '{cluster_name, status, active_shards}'
```

```text
{
  "cluster_name": "LiferayElasticsearchCluster",
  "status": "green",
  "active_shards": 18
}
```

The database is a handful of files on the volume:

```bash
kubectl exec -n liferay liferay-default-0 -c liferay-default -- ls -sh /opt/liferay/data/hypersonic
```

```text
total 15M
320K lportal.lobs
 15M lportal.log
4.0K lportal.properties
4.0K lportal.script
   0 lportal.tmp
```

### Port forwarding

```bash
kubectl port-forward -n liferay service/liferay-default 8080:8080 >/dev/null &
sleep 2
curl -s http://127.0.0.1:8080/ | grep -o '<title>.*</title>'
kill %1
```

```text
<title>Home - Liferay DXP Site - Liferay</title>
```

### NodePort

Every node answers on port 30080, through the `liferay-nodeport` Service you applied beside the
release, although the pod is only on `node02`. Ask each one, first as a browser would if it were
given the node's own name:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://node01:30080/
curl -s -o /dev/null -w '%{http_code}\n' http://node02:30080/
```

```text
500
500
```

That is Liferay refusing, not the cluster failing. The chart switches on Liferay's
`virtual.hosts.strict.access`, and with it Liferay serves only the host name it was told is its
own. That is the load balancer's address, from the ConfigMap. Send that name in the `Host` header:

```bash
LOADBALANCER=$(dig +short loadbalancer)
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: ${LOADBALANCER}" http://node01:30080/
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: ${LOADBALANCER}" http://node02:30080/
```

```text
200
200
```

The port-forward test worked without it because `127.0.0.1` and `localhost` are on the chart's
list of exceptions.

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
HAProxy reads each request, and it can add the `X-Forwarded-For` header that tells Liferay the
reader's real address:

```bash
cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg

frontend liferay
    bind ${LOADBALANCER}:80
    mode http
    option httplog
    option forwardfor
    default_backend liferay-nodeport

backend liferay-nodeport
    mode http
    balance roundrobin
    option httpchk
    http-check send meth GET uri /c/portal/robots ver HTTP/1.1 hdr Host ${LOADBALANCER}
    server node01 ${NODE01}:30080 check
    server node02 ${NODE02}:30080 check
EOF
```

`/c/portal/robots` is the path the chart's own readiness probe asks for. It is cheap for Liferay to
answer, which matters for a check that runs every two seconds from each of two servers. The check
sends the `Host` header for the reason you just saw: without it Liferay would answer `500`, and
HAProxy would mark both workers `DOWN`.

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
curl -s http://192.168.100.30/ | grep -o '<title>.*</title>'
```

```text
<title>Home - Liferay DXP Site - Liferay</title>
```

## Sign in

[//]: # (host:controlplane01)

Back on `controlplane01` (`exit` leaves the load balancer), read the administrator's password
from the Secret the chart generated:

```bash
kubectl get secret liferay-default -n liferay \
  -o jsonpath='{.data.LIFERAY_DEFAULT_PERIOD_ADMIN_PERIOD_PASSWORD}' | base64 -d; echo
```

Open **http://192.168.100.30/** in your browser, choose *Sign In*, and use
`test@liferay.com` with that password. Liferay asks for a new password straight away. The chart
sets `passwords.default.policy.change.required=true`, so the generated one is good for one sign-in.

> The sign-in, like everything in this lab, is served over plain HTTP on a network only your
> workstation can reach. That is fine here. A real site would terminate TLS on the load balancer.

## Where the data is

The provisioner created a directory on `node02` for the pod's claim. Find it:

```bash
kubectl get pv -o custom-columns=CLAIM:.spec.claimRef.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],PATH:.spec.hostPath.path
```

```text
CLAIM                                         NODE     PATH
liferay-persistent-volume-liferay-default-0   node02   /opt/local-path-provisioner/pvc-21ffb869-d930-478a-a618-917c37532042_liferay_liferay-persistent-volume-liferay-default-0
```

The database, the search index and everything Liferay writes are under that directory. The node
affinity on the volume would keep a replacement pod on `node02` even if another node had room. It
is also the limitation of local-path storage: if that node dies, so does the site.

Congratulations. You built a Kubernetes cluster by hand, and are running an application on it that
you also built yourself.

Next: [Cleaning Up](99-cleanup.md)<br>
Prev: [Cluster Add-ons](11-cluster-addons.md)
