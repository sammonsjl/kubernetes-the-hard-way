# Installing the Client Tools

Begin by logging into `controlplane01` using `vagrant ssh` for KVM.

## Access all VMs

Here we create an SSH key pair for the user who we are logged in as. We will copy the public key of this pair to the other controlplanes and both workers to permit us to use password-less SSH (and SCP) go get from `controlplane01` to these other nodes in the context of the user which exists on all nodes.

Generate SSH key pair on `controlplane01` node:

[//]: # (host:controlplane01)

```bash
ssh-keygen -t rsa
```

Leave all settings to default by pressing `ENTER` at any prompt.

Add this key to the local `authorized_keys` (`controlplane01`) as in some commands we `scp` to ourself.

```bash
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
```

Copy the key to the other hosts. You will be asked to enter a password for each of the `ssh-copy-id` commands. The password is:
* KVM - `vagrant`

The option `-o StrictHostKeyChecking=no` tells it not to ask if you want to connect to a previously unknown host. Not best practice in the real world, but speeds things up here.

`$(whoami)` selects the appropriate user name to connect to the remote VMs. On KVM this evaluates to `vagrant`

```bash
ssh-copy-id -o StrictHostKeyChecking=no $(whoami)@controlplane02
ssh-copy-id -o StrictHostKeyChecking=no $(whoami)@controlplane03
ssh-copy-id -o StrictHostKeyChecking=no $(whoami)@loadbalancer
ssh-copy-id -o StrictHostKeyChecking=no $(whoami)@node01
ssh-copy-id -o StrictHostKeyChecking=no $(whoami)@node02
```



For each host, the output should be similar to this. If it is not, then you may have entered an incorrect password. Retry the step.

```
Number of key(s) added: 1
```

Verify connection

```
ssh controlplane01
exit

ssh controlplane02
exit

ssh controlplane03
exit

ssh node01
exit

ssh node02
exit
```

### Download Binaries

In this section you will download the binaries for the various Kubernetes components. The binaries will be stored in the `downloads` directory on the `jumpbox`, which will reduce the amount of internet bandwidth required to complete this tutorial as we avoid downloading the binaries multiple times for each machine in our Kubernetes cluster.

From the `kubernetes-the-hard-way` directory create a `downloads` directory using the `mkdir` command:

```bash
mkdir downloads
```

The binaries that will be downloaded are listed in the `downloads.txt` file, which you can review using the `cat` command:

```bash
cat downloads.txt
```

Download the binaries listed in the `downloads.txt` file using the `wget` command:

```bash
wget -q --progress=bar:force \
  --https-only \
  --timestamping \
  -P downloads \
  -i downloads.txt
```

Depending on your internet connection speed it may take a while to download the `584` megabytes of binaries, and once the download is complete, you can list them using the `ls` command:

```bash
ls -loh downloads
```

```text
total 561M
-rw-r--r--. 1 vagrant 51M Oct 15 09:37 cni-plugins-linux-amd64-v1.6.0.tgz
-rw-r--r--. 1 vagrant 46M Oct 14 20:47 containerd-1.7.23-linux-amd64.tar.gz
-rw-r--r--. 1 vagrant 18M Aug 13 10:48 crictl-v1.31.1-darwin-amd64.tar.gz
-rw-r--r--. 1 vagrant 20M Sep 10 18:31 etcd-v3.5.16-linux-amd64.tar.gz
-rw-r--r--. 1 vagrant 87M Oct 23 04:41 kube-apiserver
-rw-r--r--. 1 vagrant 81M Oct 23 04:41 kube-controller-manager
-rw-r--r--. 1 vagrant 54M Oct 23 04:41 kubectl
-rw-r--r--. 1 vagrant 74M Oct 23 04:41 kubelet
-rw-r--r--. 1 vagrant 62M Oct 23 04:41 kube-proxy
-rw-r--r--. 1 vagrant 61M Oct 23 04:41 kube-scheduler
-rw-r--r--. 1 vagrant 11M Oct 21 22:31 runc.amd64
```

## Install kubectl

The [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl) command line utility is used to interact with the Kubernetes API Server. Download and install `kubectl` from the official release binaries:

Reference: [https://kubernetes.io/docs/tasks/tools/install-kubectl/](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

We will be using `kubectl` early on to generate `kubeconfig` files for the controlplane components.

```bash
sudo cp downloads/kubectl /usr/local/bin/
sudo chmod +x /usr/local/bin/kubectl
```

### Verification

Verify `kubectl` is installed:

```
kubectl version --client
```

output will be similar to this, although versions may be newer:

```
Client Version: v1.31.2
Kustomize Version: v5.4.2
```

Next: [Certificate Authority](04-certificate-authority.md)<br>
Prev: Compute Resources ([KVM](02-compute-resources.md))