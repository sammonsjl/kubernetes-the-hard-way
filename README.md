# Kubernetes The Hard Way

Updated: March 2024

This tutorial walks you through setting up Kubernetes the hard way on a local machine using a hypervisor.
This guide is not for people looking for a fully automated command to bring up a Kubernetes cluster.
If that's you then check out [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine), or the [Getting Started Guides](http://kubernetes.io/docs/getting-started-guides/).

Kubernetes The Hard Way is optimized for learning, which means taking the long route to ensure you understand each task required to bootstrap a Kubernetes cluster. Note that the cluster when built will not be accessible from your laptop browser - that isn't what this is about. If you want a more useable cluster, try [one of these](https://github.com/kodekloudhub/certified-kubernetes-administrator-course/tree/master/kubeadm-clusters).

This tutorial is a modified version of the original developed by [Kelsey Hightower](https://github.com/kelseyhightower/kubernetes-the-hard-way).
While the original one uses GCP as the platform to deploy kubernetes,  we use a hypervisor to deploy a cluster on a local machine. If you prefer the cloud version, refer to the original one [here](https://github.com/kelseyhightower/kubernetes-the-hard-way)

The results of this tutorial should *not* be viewed as production ready, and may receive limited support from the community, but don't let that stop you from learning!

Always run the `cert_verify.sh` script at the places it suggests, and always ensure you are on the correct node when you do stuff. If `cert_verify.sh` shows anything in red, then you have made an error in a previous step. For the controlplane node checks, run the check on `controlplane01` and on `controlplane02`

## Target Audience

The target audience for this tutorial is someone planning to support a production Kubernetes cluster and wants to understand how everything fits together.

## Cluster Details

Kubernetes The Hard Way guides you through bootstrapping a highly available Kubernetes cluster with end-to-end encryption between components and RBAC authentication.

* [Kubernetes](https://github.com/kubernetes/kubernetes) Latest version
* [Container Runtime](https://github.com/containerd/containerd) Latest version
* [Weave Networking](https://www.weave.works/docs/net/latest/kubernetes/kube-addon/)
* [etcd](https://github.com/coreos/etcd) v3.5.9
* [CoreDNS](https://github.com/coredns/coredns) v1.9.4

### Node configuration

We will be building the following:

* Three control plane nodes (`controlplane01`, `controlplane02` and `controlplance03`) running the control plane components as operating system services. This is not a kubeadm cluster as you are used to if you have been doing the CKA course. The control planes are *not* themselves nodes, therefore will not show with `kubectl get nodes`.
* Two worker nodes (`node01` and `node02`)
* One loadbalancer VM running [HAProxy](https://www.haproxy.org/) to balance requests between the two API servers and provide the endpoint for your KUBECONFIG.

## Getting Started

Start [here](./kvm/docs/01-prerequisites.md) to deploy KVM and Vagrant.