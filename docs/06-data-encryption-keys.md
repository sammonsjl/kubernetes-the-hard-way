# Lab 6 — Generating the Data Encryption Config and Key

## What you will have at the end

An [encryption config](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#understanding-the-encryption-at-rest-configuration) and key on each control plane node, ready for the API server to [encrypt](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data) Secrets before it writes them to etcd.

Kubernetes stores cluster state, application configuration and Secrets in etcd. Without this, a Secret is stored as plain base64, which anyone with access to etcd or its backups can read. In Lab 12 you will look at a Secret's raw bytes in etcd and see that it is encrypted.

Run the commands in this lab on `controlplane01`.

[//]: # (host:controlplane01)

## The Encryption Key

Generate an encryption key:

```bash
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

## The Encryption Config File

Create the `encryption-config.yaml` encryption config file:

```bash
envsubst < templates/encryption-config.yaml.template \
  > encryption-config.yaml
```

Copy the `encryption-config.yaml` encryption config file to each controller instance:

```bash
for instance in controlplane01 controlplane02 controlplane03; do
  scp encryption-config.yaml ${instance}:~/
done
```

Install it where the API server will read it. The file holds the key itself, so only root may read it:

```bash
for instance in controlplane01 controlplane02 controlplane03; do
  ssh ${instance} sudo install -D -o root -g root -m 0600 \
    encryption-config.yaml /var/lib/kubernetes/encryption-config.yaml
  ssh ${instance} rm encryption-config.yaml
done
```

Reference: https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#encrypting-your-data

Next: [Bootstrapping the etcd Cluster](07-bootstrapping-etcd.md)<br>
Prev: [Generating Kubernetes Configuration Files for Authentication](05-kubernetes-configuration-files.md)
