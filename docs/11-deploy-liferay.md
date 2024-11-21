# Deploy Liferay

In this lab you will complete a series of tasks to ensure your Kubernetes cluster is functioning correctly.

```

## Deployments

In this section you will verify the ability to create and manage [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

Create a deployment for the [nginx](https://nginx.org/en/) web server:

```bash
kubectl create deployment nginx --image=nginx:alpine
```

[//]: # (command:kubectl wait deployment -n default nginx --for condition=Available=True --timeout=90s)

List the pod created by the `nginx` deployment:

```bash
kubectl get pods -l app=nginx
```

> output

```
NAME                    READY   STATUS    RESTARTS   AGE
nginx-dbddb74b8-6lxg2   1/1     Running   0          10s
```

### Services

In this section you will verify the ability to access applications remotely using [port forwarding](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/).

Create a service to expose deployment nginx on node ports.

```bash
kubectl expose deploy nginx --type=NodePort --port 80
```

[//]: # (command:sleep 2)

```bash
PORT_NUMBER=$(kubectl get svc -l app=nginx -o jsonpath="{.items[0].spec.ports[0].nodePort}")
```

Test to view NGINX page

```bash
curl http://node01:$PORT_NUMBER
curl http://node02:$PORT_NUMBER
```

> output

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
 # Output Truncated for brevity
<body>
```

### Logs

In this section you will verify the ability to [retrieve container logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

Retrieve the full name of the `nginx` pod:

```bash
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")
```

Print the `nginx` pod logs:

```bash
kubectl logs $POD_NAME
```

> output

```
10.32.0.1 - - [20/Mar/2019:10:08:30 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/7.58.0" "-"
10.40.0.0 - - [20/Mar/2019:10:08:55 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/7.58.0" "-"
```

### Exec

In this section you will verify the ability to [execute commands in a container](https://kubernetes.io/docs/tasks/debug-application-cluster/get-shell-running-container/#running-individual-commands-in-a-container).

Print the nginx version by executing the `nginx -v` command in the `nginx` container:

```bash
kubectl exec -ti $POD_NAME -- nginx -v
```

> output

```
nginx version: nginx/1.23.1
```

Clean up test resources


```bash
kubectl delete pod -n default busybox
kubectl delete service -n default nginx
kubectl delete deployment -n default nginx
```

Next: [End to End Tests](./17-e2e-tests.md)</br>
Prev: [DNS Addon](./15-dns-addon.md)
