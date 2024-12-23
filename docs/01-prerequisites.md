# Kubernetes The Hard Way on KVM

## Prerequisites

### Hardware Requirements

This lab provisions 6 VMs on your workstation.

- 32GB RAM
- 8 core or better CPU e.g. Intel Core-i7/Core-i9, AMD Ryzen-7/Ryzen-9. May work with fewer, but will be slow and may crash unexpectedly.
- 50 GB disk space

### KVM

Download and install [KVM](https://linux-kvm.org/page/HOWTO) on the Linux Host

### Vagrant

Vagrant provides an easy way to deploy multiple virtual machines on KVM consistently.

Download and install [Vagrant](https://www.vagrantup.com/) on the Linux Host.

### Lab Defaults

The labs have been configured with the following networking defaults. It is not recommended to change these.

#### Virtual Machine Network

The network used by the KVM virtual machines is `192.168.100.0/24`.

To change this, edit the [Vagrantfile](../vagrant/Vagrantfile) in your cloned copy, and set the new value for the network prefix at line 14. This should not overlap any of the other network settings.

Note that you do not need to edit any of the other scripts to make the above change. It is all managed by shell variable computations based on the assigned VM IP addresses and the values in the hosts file (also computed).

It is *recommended* that you leave the pod and service networks with the following defaults. If you change them then you will also need to edit one or both of the CoreDNS and Calico networking manifests to accommodate your change.

#### Pod Network

The network used to assign IP addresses to pods is `10.244.0.0/16`.

To change this, open all the `.md` files in the [docs](../docs) directory in your favourite IDE and do a global replace on<br>
`POD_CIDR=10.244.0.0/16`<br>
with the new CDIR range.  This should not overlap any of the other network settings.

#### Service Network

The network used to assign IP addresses to Cluster IP services is `10.96.0.0/16`.

To change this, open all the `.md` files in the [docs](../docs) directory in your favourite IDE and do a global replace on<br>
`SERVICE_CIDR=10.96.0.0/16`<br>
with the new CDIR range.  This should not overlap any of the other network settings.

## Running Commands in Parallel with tmux

[tmux](https://github.com/tmux/tmux/wiki) can be used to run commands on multiple compute instances at the same time. Labs in this tutorial may require running the same commands across multiple compute instances, in those cases consider using tmux and splitting a window into multiple panes with synchronize-panes enabled to speed up the provisioning process.

> The use of tmux is optional and not required to complete this tutorial.

![tmux screenshot](../images/tmux-screenshot.png)

> Enable synchronize-panes by pressing `CTRL+B` followed by `"` to split the window into two panes. In each pane (selectable with mouse), ssh to the host(s) you will be working with.</br>Next type `CTRL+X` at the prompt to begin sync. In sync mode, the dividing line between panes will be red. Everything you type or paste in one pane will be echoed in the other.<br>To disable synchronization type `CTRL+X` again.</br></br>Note that the `CTRL-X` key binding is provided by a `.tmux.conf` loaded onto the VM by the vagrant provisioner.

Next: [Compute Resources](02-compute-resources.md)
