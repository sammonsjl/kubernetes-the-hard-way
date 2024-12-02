# Kubernetes The Hard Way

This tutorial walks you through setting up Kubernetes the hard way on a local machine using a hypervisor. This 
guide is not for someone looking for a fully automated tool to bring up a Kubernetes cluster. Kubernetes The Hard Way is optimized for learning, which means taking the long route to ensure you understand each task required to bootstrap a Kubernetes cluster.

> The results of this tutorial should not be viewed as production ready.

## Target Audience

The target audience for this tutorial is someone who wants to understand the fundamentals of Kubernetes and how the core components fit together.

## Cluster Details

Kubernetes The Hard Way guides you through bootstrapping a highly available Kubernetes cluster with end-to-end encryption between components and RBAC authentication.

* [kubernetes](https://github.com/kubernetes/kubernetes) v1.31.2
* [etcd](https://github.com/etcd-io/etcd) v3.5.16
* [containerd](https://github.com/containerd/containerd) v1.7.23]
* [calico](https://projectcalico.docs.tigera.io/)
* [coredns](https://github.com/coredns/coredns) v1.9.4

### Node configuration

We will be building the following:

* Three control plane nodes (`controlplane01`, `controlplane02` and `controlplane03`) running the control plane 
  components as operating system services. This is not a kubeadm cluster as you are used to if you have been doing the CKA course. The control planes are *not* themselves nodes, therefore will not show with `kubectl get nodes`.
* Two worker nodes (`node01` and `node02`)
* One loadbalancer VM running [HAProxy](https://www.haproxy.org/) to balance requests between the two API servers and provide the endpoint for your KUBECONFIG.

## Labs

This tutorial requires four (4) ARM64 based virtual or physical machines connected to the same network. While ARM64 based machines are used for the tutorial, the lessons learned can be applied to other platforms.

* [Prerequisites](docs/01-prerequisites.md)
* [Provisioning Compute Resources](docs/02-compute-resources.md)
* [Client Tools](docs/03-client-tools.md)
* [Provisioning the CA and Generating TLS Certificates](docs/04-certificate-authority.md)
* [Generating Kubernetes Configuration Files for Authentication](docs/05-kubernetes-configuration-files.md)
* [Generating the Data Encryption Config and Key](docs/06-data-encryption-keys.md)
* [Bootstrapping the etcd Cluster](docs/07-bootstrapping-etcd.md)
* [Bootstrapping the Kubernetes Control Plane](docs/08-bootstrapping-kubernetes-controllers.md)
* [Bootstrapping the Kubernetes Worker Nodes](docs/09-bootstrapping-kubernetes-workers.md)
* [Configuring kubectl for Remote Access](docs/10-configuring-kubectl.md)
* [Deploy Liferay](docs/11-deploy-liferay.md)
