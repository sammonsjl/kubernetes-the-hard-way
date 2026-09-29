# Lab 3 — Installing the Client Tools

## What you will have at the end

- The lab's configuration files on every node.
- `controlplane01` set up as the admin workstation: it can SSH to every other node without a
  password, it holds the Kubernetes release binaries (and has passed them on), and `kubectl` is
  installed.

## Copy the lab files to the nodes

Run this on your **workstation**, from the root of your clone of this repository. It copies the
files the later labs render and apply:

- `templates/`: systemd units and configs that `envsubst` fills in with addresses
- `configs/`: the files that are used as-is
- `addons/` and `ghost/`: the manifests for Labs 11 and 12
- `downloads.txt`: the list of binaries to fetch
- `cert_verify.sh`: an optional checker for Labs 4, 5, 8 and 9

```bash
for n in controlplane01 controlplane02 controlplane03 node01 node02; do
  scp -rq templates configs addons ghost downloads.txt cert_verify.sh ${n}:~/
done
```

## Access all VMs from controlplane01

From here on, most labs are run on `controlplane01`. It generates the certificates and
configuration and copies them to the other nodes, so it needs SSH access to all of them.

Log in to it:

```bash
ssh controlplane01
```

[//]: # (host:controlplane01)

Generate a key pair for the `fedora` user on `controlplane01`, and authorize it locally too, since
some later commands `scp` to `controlplane01` itself:

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
```

The other nodes have no password to type into `ssh-copy-id`. Their only credential is your lab key,
and that stays on your workstation. So the public key is carried across from there instead. Back on
your **workstation**:

```bash
PUBKEY=$(ssh controlplane01 cat .ssh/id_ed25519.pub)
for n in controlplane02 controlplane03 node01 node02 loadbalancer; do
  echo "$PUBKEY" | ssh $n 'cat >> ~/.ssh/authorized_keys'
done
```

Now, on `controlplane01`, check that it can reach every node. `-o StrictHostKeyChecking=accept-new`
records each host key on first contact instead of asking:

```bash
for n in controlplane01 controlplane02 controlplane03 node01 node02 loadbalancer; do
  ssh -o StrictHostKeyChecking=accept-new $n hostname
done
```

```text
controlplane01
controlplane02
controlplane03
node01
node02
loadbalancer
```

## Download Binaries

In this section you download the binaries for the Kubernetes components. They go into the
`downloads` directory on `controlplane01` and are copied to the other nodes from there, so each
binary is fetched from the internet only once.

The binaries are listed in `downloads.txt`:

```bash
cat downloads.txt
```

Download them:

```bash
wget -q --show-progress \
  --https-only \
  --timestamping \
  -P downloads \
  -i downloads.txt
```

That is about 460 MB. List the downloaded files:

```bash
ls -oh downloads
```

```text
total 463M
-rw-r--r--. 1 fedora 35M Sep 24 23:40 containerd-2.4.1-linux-amd64.tar.gz
-rw-r--r--. 1 fedora 19M Sep  1 08:40 crictl-v1.37.0-linux-amd64.tar.gz
-rw-r--r--. 1 fedora 23M Sep 22 21:18 etcd-v3.7.2-linux-amd64.tar.gz
-rw-r--r--. 1 fedora 92M Sep 23 19:12 kube-apiserver
-rw-r--r--. 1 fedora 76M Sep 23 19:12 kube-controller-manager
-rw-r--r--. 1 fedora 60M Sep 23 19:12 kubectl
-rw-r--r--. 1 fedora 59M Sep 23 19:12 kubelet
-rw-r--r--. 1 fedora 44M Sep 23 19:12 kube-proxy
-rw-r--r--. 1 fedora 49M Sep 23 19:12 kube-scheduler
-rw-r--r--. 1 fedora 11M Sep 25 19:20 runc.amd64
```

Sizes and dates will differ a little.

## Copy Binaries to every node

```bash
for instance in controlplane02 controlplane03 node01 node02; do
  scp -rq downloads ${instance}:~/
done
```

## Install kubectl

The [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl) command line utility is used
to interact with the Kubernetes API Server. You will also use it in Lab 5 to generate kubeconfig
files for the control plane components.

```bash
sudo install -m 0755 downloads/kubectl /usr/local/bin/
```

### Verification

```bash
kubectl version --client
```

```text
Client Version: v1.37.1
Kustomize Version: v5.8.1
```

Next: [Certificate Authority](04-certificate-authority.md)<br>
Prev: [Compute Resources](02-compute-resources.md)
