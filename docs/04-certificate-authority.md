# Lab 4 — Provisioning a CA and Generating TLS Certificates

## What you will have at the end

A [PKI](https://en.wikipedia.org/wiki/Public_key_infrastructure) built with `openssl`: a
certificate authority, and a certificate signed by it for each of kube-apiserver,
kube-controller-manager, kube-scheduler, each kubelet, kube-proxy, etcd, the service account signer
and the `admin` user. Each one is on the nodes that need it.

## Where to do this

You can do this on any machine with `openssl` that can copy files to the VMs. Here it is done on
`controlplane01`, the admin workstation.

[//]: # (host:controlplane01)

## Certificate Authority

The certificates carry node addresses as subject alternative names (SANs). Read them from
`/etc/hosts`:

```bash
export CONTROL01=$(dig +short controlplane01)
export CONTROL02=$(dig +short controlplane02)
export CONTROL03=$(dig +short controlplane03)
export NODE01=$(dig +short node01)
export NODE02=$(dig +short node02)
export LOADBALANCER=$(dig +short loadbalancer)
```

The API server is also reachable inside the cluster at the first address of the service network,
so that address needs to be a SAN too:

```bash
export SERVICE_CIDR=10.96.0.0/16
export API_SERVICE=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.1", $1, $2, $3) }')
```

Check that the variables are set:

```bash
echo $CONTROL01 $CONTROL02 $CONTROL03 $NODE01 $NODE02 $LOADBALANCER
echo $SERVICE_CIDR $API_SERVICE
```

```text
192.168.100.11 192.168.100.12 192.168.100.13 192.168.100.21 192.168.100.22 192.168.100.30
10.96.0.0/16 10.96.0.1
```

Render the `ca.conf` openssl configuration file from its template:

```bash
envsubst < templates/ca.conf.template > ca.conf
```

Take a moment to review it:

```bash
cat ca.conf
```

You don't need to understand everything in `ca.conf` to complete this tutorial. It is a good
starting point for learning `openssl` and the configuration that goes into managing certificates.

Two SANs in it are worth noticing now:

- The **node01** and **node02** sections name the node's IP address. The same certificate is the
  kubelet's *serving* certificate. In Lab 8 the API server is told to verify the kubelets against
  this CA, and it reaches each kubelet by IP address. Without the IP in the SAN, `kubectl logs`,
  `exec` and `port-forward` fail with a certificate error.
- The **kube-apiserver** section names every control plane node, the load balancer, `127.0.0.1`,
  the in-cluster service address and the `kubernetes.default...` DNS names. It covers every name
  a client could use to reach an API server.

Every certificate authority starts with a private key and a root certificate. Here you create a
self-signed one. That is enough for this tutorial, but it is not how you would run a CA in
production.

Generate the CA's private key and self-signed certificate:

```bash
openssl req -x509 -noenc -newkey rsa:4096 \
  -keyout ca.key -out ca.crt -days 36500 -config ca.conf
```

Results:

```text
ca.crt ca.key
```

## Create Client and Server Certificates

Generate a key, a signing request and a signed certificate for each Kubernetes component and for
the `admin` user:

```bash
certs=(
  "admin" "node01" "node02"
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "apiserver-kubelet-client"
  "kube-apiserver"
  "etcd-server"
  "service-account"
)
```

```bash
for i in ${certs[*]}; do
  openssl req -noenc -newkey rsa:4096 -keyout ${i}.key -out ${i}.csr -config ca.conf -section ${i}

  openssl x509 -req -days 36500 -in ${i}.csr -CA ca.crt -CAkey ca.key \
     -CAcreateserial -out ${i}.crt -copy_extensions copyall
done
```

Check that the kubelet certificates picked up the node's address:

```bash
openssl x509 -in node01.crt -noout -ext subjectAltName
```

```text
X509v3 Subject Alternative Name:
    DNS:node01, IP Address:192.168.100.21, IP Address:127.0.0.1
```

## Verify the PKI

Run the following to check that every required certificate was generated:

[//]: # (command:./cert_verify.sh 1)

```bash
./cert_verify.sh 1
```

Expected output:

```text
The selected option is 1, proceeding the certificate verification of Master node
ca cert and key found, verifying the authenticity
ca cert and key are correct
kube-apiserver cert and key found, verifying the authenticity
kube-apiserver cert and key are correct
kube-controller-manager cert and key found, verifying the authenticity
kube-controller-manager cert and key are correct
kube-scheduler cert and key found, verifying the authenticity
kube-scheduler cert and key are correct
service-account cert and key found, verifying the authenticity
service-account cert and key are correct
apiserver-kubelet-client cert and key found, verifying the authenticity
apiserver-kubelet-client cert and key are correct
etcd-server cert and key found, verifying the authenticity
etcd-server cert and key are correct
admin cert and key found, verifying the authenticity
admin cert and key are correct
kube-proxy cert and key found, verifying the authenticity
kube-proxy cert and key are correct
```

If there are any errors, review the steps above and then run the check again.

## Distribute the Certificates

Copy the certificates and private keys each node needs:

```bash
for instance in controlplane01 controlplane02 controlplane03; do
  scp ca.crt ca.key kube-apiserver.key kube-apiserver.crt \
    apiserver-kubelet-client.crt apiserver-kubelet-client.key \
    service-account.key service-account.crt \
    etcd-server.key etcd-server.crt \
    kube-controller-manager.key kube-controller-manager.crt \
    kube-scheduler.key kube-scheduler.crt \
    ${instance}:~/
done

for instance in node01 node02; do
  scp ca.crt kube-proxy.crt kube-proxy.key ${instance}.key ${instance}.crt ${instance}:~/
done
```

## Optional: check the certificates on controlplane02 and controlplane03

[//]: # (command:ssh controlplane02 './cert_verify.sh 1')

```bash
ssh controlplane02 ./cert_verify.sh 1
ssh controlplane03 ./cert_verify.sh 1
```

Next: [Generating Kubernetes Configuration Files for Authentication](05-kubernetes-configuration-files.md)<br>
Prev: [Client tools](03-client-tools.md)
