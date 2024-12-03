# Provisioning a CA and Generating TLS Certificates

In this lab you will provision a [PKI Infrastructure](https://en.wikipedia.org/wiki/Public_key_infrastructure) using openssl to bootstrap a Certificate Authority, and generate TLS certificates for the following components: kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kube-proxy and etcd.

# Where to do these?

You can do these on any machine with `openssl` on it. But you should be able to copy the generated files to the provisioned VMs. Or just do these from one of the controlplane nodes.

In our case we do the following steps on the `controlplane01` node, as we have set it up to be the administrative client.

[//]: # (host:controlplane01)

## Certificate Authority

In this section you will provision a Certificate Authority that can be used to generate additional TLS certificates.

Query IPs of hosts we will insert as certificate subject alternative names (SANs), which will be read from `/etc/hosts`.

Set up environment variables. Run the following:

```bash
export CONTROL01=$(dig +short controlplane01)
export CONTROL02=$(dig +short controlplane02)
export CONTROL03=$(dig +short controlplane03)
export LOADBALANCER=$(dig +short loadbalancer)
```

Compute cluster internal API server service address, which is always `.1` in the service CIDR range. This is also required as a SAN in the API server certificate. Run the following:

```bash
export SERVICE_CIDR=10.96.0.0/24
export API_SERVICE=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.1", $1, $2, $3) }')
```

Check that the environment variables are set. Run the following:

```bash
echo $CONTROL01
echo $CONTROL02
echo $CONTROL03
echo $LOADBALANCER
echo $SERVICE_CIDR
echo $API_SERVICE
```

The output should look like this with one IP address per line. If you changed any of the defaults mentioned in the [prerequisites](./01-prerequisites.md) page, then addresses may differ.

```
192.168.56.11
192.168.56.12
192.168.56.30
10.96.0.0/24
10.96.0.1
```

Prepare the `ca.conf` openssl conf file:

```bash
envsubst < templates/ca.conf.template \
  > ca.conf
```

Take a moment to review the `ca.conf` configuration file:

```bash
cat ca.conf
```

You don't need to understand everything in the `ca.conf` file to complete this tutorial, but you should consider it a starting point for learning `openssl` and the configuration that goes into managing certificates at a high level.

Every certificate authority starts with a private key and root certificate. In this section we are going to create a self-signed certificate authority, and while that's all we need for this tutorial, this shouldn't be considered something you would do in a real-world production level environment.

Generate the CA configuration file, certificate, and private key:

```bash
{
  openssl req -x509 -noenc -newkey rsa:4096 \
    -keyout ca.key -out ca.crt -days 36500 -config ca.conf
}
```

Results:

```txt
ca.crt ca.key
```

## Create Client and Server Certificates

In this section you will generate client and server certificates for each Kubernetes component and a client certificate for the Kubernetes `admin` user.

Generate the certificates and private keys:

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

The results of running the above command will generate a private key, certificate request, and signed SSL certificate for each of the Kubernetes components. You can list the generated files with the following command:

## Verify the PKI

Run the following, and select option 1 to check all required certificates were generated.

[//]: # (command:./cert_verify.sh 1)

```
./cert_verify.sh
```

Expected output:

```
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

If there are any errors, please review above steps and then re-verify

## Distribute the Certificates

Copy the appropriate certificates and private keys to each instance:

```bash
{
for instance in controlplane01 controlplane02 controlplane03; do
  scp -o StrictHostKeyChecking=no ca.crt ca.key kube-apiserver.key kube-apiserver.crt \
    apiserver-kubelet-client.crt apiserver-kubelet-client.key \
    service-account.key service-account.crt \
    etcd-server.key etcd-server.crt \
    kube-controller-manager.key kube-controller-manager.crt \
    kube-scheduler.key kube-scheduler.crt \
    ${instance}:~/
done

for instance in node01 node02 ; do
  scp ca.crt kube-proxy.crt kube-proxy.key ${instance}.key ${instance}.crt ${instance}:~/
done
}
```

## Optional - Check Certificates on controlplane02 and controlplane03

Run the following on `controlplane02` and `controlplane03`, selecting option 1

[//]: # (commandssh controlplane02 './cert_verify.sh 1')

```
./cert_verify.sh
```

Next: [Generating Kubernetes Configuration Files for Authentication](05-kubernetes-configuration-files.md)<br>
Prev: [Client tools](03-client-tools.md)
