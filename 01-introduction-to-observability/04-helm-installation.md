# Section 4: Helm Installation, The Right Way

**Module:** 01 - Introduction to Observability: Prometheus and Grafana Setup
**Duration:** approximately 50 minutes
**Hands-on:** Yes. Runs on the EKS jump box.
**Prerequisites:** Sections 1 to 3. A running EKS cluster with the EBS CSI driver installed.

---

## Table of Contents

- [Why Helm](#why-helm)
- [What the Chart Actually Installs](#what-the-chart-actually-installs)
- [Before You Start](#before-you-start)
- [Lab](#lab)
  - [Step 1: Verify the Cluster Is Ready](#step-1-verify-the-cluster-is-ready)
  - [Step 2: Add the Helm Repository](#step-2-add-the-helm-repository)
  - [Step 3: Create the Namespace](#step-3-create-the-namespace)
  - [Step 4: Write the Values File](#step-4-write-the-values-file)
  - [Step 5: Install the Stack](#step-5-install-the-stack)
  - [Step 6: Verify Everything Is Running](#step-6-verify-everything-is-running)
  - [Step 7: Confirm Storage Was Provisioned](#step-7-confirm-storage-was-provisioned)
  - [Step 8: Open the Prometheus UI](#step-8-open-the-prometheus-ui)
  - [Step 9: The Targets Page](#step-9-the-targets-page)
- [What Just Happened](#what-just-happened)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Interview Questions](#interview-questions)
- [What's Next](#whats-next)

---

## Why Helm

Installing Prometheus on Kubernetes by hand means writing dozens of YAML files. Deployments, StatefulSets, Services, ConfigMaps, ServiceAccounts, ClusterRoles, ClusterRoleBindings, CustomResourceDefinitions, ServiceMonitors, PrometheusRules.

Then you have to work out which versions of each component are compatible with each other, wire them together correctly, and keep all of it in sync every time you upgrade one piece.

This is the same relationship as compiling a Linux system from source versus installing a distribution.

You can absolutely build a working system by compiling every package yourself and writing your own init scripts. People do it, and they learn a great deal. But a distribution is somebody else having already worked out which versions cooperate, wired the pieces together, tested the combination, and shipped it as a single install.

`kube-prometheus-stack` is the distribution. One command, one release, one set of tested versions.

---

## What the Chart Actually Installs

Seven things, and it is worth knowing them before you run the command rather than discovering them in the pod list afterwards.

| Component | Kubernetes object | What it does |
|---|---|---|
| Prometheus Operator | Deployment | Watches CRDs and rewrites Prometheus configuration |
| Prometheus | StatefulSet | Scrapes, stores, evaluates rules |
| Alertmanager | StatefulSet | Groups, silences and routes alerts |
| Grafana | Deployment | Dashboards, pre-wired to Prometheus |
| node-exporter | DaemonSet | Machine level metrics, one pod per node |
| kube-state-metrics | Deployment | Kubernetes object state |
| Default dashboards and rules | ConfigMaps and CRs | Roughly 30 dashboards, over 100 alerting rules |

Every one of these was a concept in Sections 1 and 2. This section is where they become pods.

---

## Before You Start

### Chart version

This lab was written against these versions:

```
NAME                                         CHART VERSION   APP VERSION
prometheus-community/kube-prometheus-stack   88.2.0          v0.93.0
```

The chart is updated frequently, so your version will very likely be higher. That is fine and expected. Where output in this document shows a version number, compare the shape of the output rather than the digits.

### Storage is the failure everyone hits

Prometheus, Alertmanager and Grafana all request PersistentVolumeClaims in this configuration.

Two separate things must be true, and EKS gives you neither by default.

**The EBS CSI driver must be installed.** It is the component that actually creates the EBS volume. We added it as an addon during cluster creation.

**A usable default StorageClass must exist.** This is the one that catches people. EKS ships a StorageClass called `gp2`, so `kubectl get sc` returns a result and the cluster looks ready. But that StorageClass uses the `kubernetes.io/aws-ebs` in-tree provisioner, which was removed from Kubernetes in version 1.31. On a 1.34 cluster nothing implements it. It is also not marked as default.

If either is missing, the PVCs sit in `Pending` forever, the StatefulSet pods never schedule, and Helm still reports a successful install.

Read that again, because it is the single most confusing failure in this whole module. Helm says `STATUS: deployed`. It looks like a Helm problem. It is a storage problem.

Step 1 verifies both.

### Port forwarding from a jump box

You will browse from your laptop to the jump box. By default `kubectl port-forward` binds to `127.0.0.1` on the machine running it, which means only that machine can reach it.

Every port-forward command in this section therefore includes `--address 0.0.0.0`. Without it, the browser reports a timeout and nothing appears wrong on the cluster at all.

You also need these inbound rules on the jump box security group, sourced to your own IP:

| Port | Used for |
|---|---|
| 9090 | Prometheus UI |
| 3000 | Grafana |
| 9093 | Alertmanager |

---

## Lab

### Step 1: Verify the Cluster Is Ready

Four checks. Two minutes here saves twenty minutes later.

```bash
kubectl get nodes
```

Both nodes must be `Ready`. If you scaled the nodegroup to zero between sessions, scale it back up and wait for them to join before continuing.

```bash
kubectl get sc
```

You need a default StorageClass whose provisioner is `ebs.csi.aws.com`:

```
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  24h
gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   5m
```

If you only see `gp2`, with no `(default)` marker and the `kubernetes.io/aws-ebs` provisioner, stop here. Create the gp3 StorageClass from CLUSTER-SETUP.md before continuing, otherwise this install will fail in a way that looks like a Helm error.

```bash
kubectl get pods -n kube-system | grep ebs-csi
```

You need to see `ebs-csi-controller` pods and one `ebs-csi-node` pod per node, all `Running`. If this returns nothing, the addon is missing and the install will hang at the storage step.

```bash
helm version --short
```

Helm 3.14 or later.

### Step 2: Add the Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Then confirm the chart resolves:

```bash
helm search repo prometheus-community/kube-prometheus-stack
```

Expected output:

```
NAME                                         CHART VERSION   APP VERSION   DESCRIPTION
prometheus-community/kube-prometheus-stack   88.2.0          v0.93.0       kube-prometheus-stack collects Kubernetes manif...
```

Two version numbers, and the difference matters.

**CHART VERSION** is the version of the packaging. It changes when the chart's templates or default values change, even if no application changed.

**APP VERSION** is the version of the Prometheus Operator being deployed.

Upgrading the chart does not necessarily upgrade the application, and the reverse is also true. When someone asks what version of Prometheus you are running, they usually mean the app version.

### Step 3: Create the Namespace

```bash
kubectl create namespace monitoring
kubectl get namespace monitoring
```

Everything in this module lives in `monitoring`. Keeping it separate means the entire stack can be removed later without touching anything else.

### Step 4: Write the Values File

A Helm chart ships with defaults. A values file is how you override them.

The full default values file for this chart is roughly 6,000 lines. You can read it yourself, and it is worth doing once:

```bash
helm show values prometheus-community/kube-prometheus-stack > /tmp/kps-defaults.yaml
wc -l /tmp/kps-defaults.yaml
```

We are going to override about a dozen of those lines.

```bash
cat > prometheus-values.yaml << 'EOF'
# ----------------------------------------------------------------
# Prometheus server
# ----------------------------------------------------------------
prometheus:
  prometheusSpec:
    # How long to keep data. Chart default is 10d.
    retention: 15d

    # How often to scrape. Chart default is 30s.
    scrapeInterval: 30s

    # Persistent storage. Without this, all metrics are lost
    # whenever the pod restarts.
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi

    # Watch every namespace for ServiceMonitors and PodMonitors,
    # not just those labelled with this release name.
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

    resources:
      requests:
        cpu: 200m
        memory: 1Gi

# ----------------------------------------------------------------
# Grafana
# ----------------------------------------------------------------
grafana:
  enabled: true
  adminPassword: "ChangeMe-Observability-2026"

  persistence:
    enabled: true
    size: 5Gi

  defaultDashboardsEnabled: true
  defaultDashboardsTimezone: utc

  service:
    type: ClusterIP

# ----------------------------------------------------------------
# Alertmanager
# ----------------------------------------------------------------
alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi

# ----------------------------------------------------------------
# Exporters
# ----------------------------------------------------------------
nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true

prometheusOperator:
  enabled: true
EOF
```

Four of these settings deserve explanation, because they are the ones you would get wrong on your own.

**`serviceMonitorSelectorNilUsesHelmValues: false`**

This is the most important line in the file, and the least obvious.

By default the chart tells Prometheus to only pick up ServiceMonitors carrying the label `release: kube-prometheus-stack`. Setting this to `false` makes Prometheus watch every ServiceMonitor in every namespace instead.

Leave it at the default and you will create a ServiceMonitor in Section 5, apply it successfully, watch `kubectl get servicemonitor` show it existing, and then find that Prometheus never scrapes the target. No error anywhere. This one line prevents that.

**`storageSpec`**

Without a `storageSpec`, Prometheus uses `emptyDir`. That works, and every metric disappears the moment the pod restarts. Since the pod restarts on every Helm upgrade, you would lose your history constantly.

**`retention: 15d`**

How long samples are kept before deletion. This interacts with the volume size. Fifteen days of a small cluster fits comfortably in 20Gi; a large cluster would not. If the disk fills, Prometheus stops accepting writes.

**`adminPassword`**

Change this value. If you leave it out entirely, the chart generates a random password and stores it in a Secret, which is more secure but adds a retrieval step during a live session.

Never commit a real password to git. In production this comes from a Secret or an external secret manager, not from a values file.

### Step 5: Install the Stack

```bash
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --wait \
  --timeout 10m
```

This takes three to five minutes. Most of that is pulling container images.

`--wait` holds the command until every pod reports ready, so a returned prompt means a working install rather than one that merely started. `--timeout 10m` prevents it hanging indefinitely if something is wrong.

Expected output:

```
NAME: kube-prometheus-stack
LAST DEPLOYED: Mon Aug 10 07:15:00 2026
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=kube-prometheus-stack"
```

`REVISION: 1` is worth noticing. Helm tracks every change to a release as a numbered revision, which is what makes rollback possible. Section 9 uses this.

### Step 6: Verify Everything Is Running

```bash
kubectl get pods -n monitoring
```

Expected output, with your own generated suffixes:

```
NAME                                                        READY   STATUS    RESTARTS   AGE
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          3m
kube-prometheus-stack-grafana-6c8d4f9b7d-x4k2p              3/3     Running   0          3m
kube-prometheus-stack-kube-state-metrics-7d9c6b5f4-mn8qt    1/1     Running   0          3m
kube-prometheus-stack-operator-5f7d8c964b-2wjr6             1/1     Running   0          3m
kube-prometheus-stack-prometheus-node-exporter-4vx9d        1/1     Running   0          3m
kube-prometheus-stack-prometheus-node-exporter-k7m2s        1/1     Running   0          3m
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          3m
```

Read the READY column carefully, because it tells you something real.

**node-exporter appears twice.** One pod per node, because it is a DaemonSet. Add a third node and a third pod appears automatically.

**Prometheus and Alertmanager show `2/2`.** Two containers each. The second one is `config-reloader`, the sidecar that watches for configuration changes and triggers a reload without restarting the pod. Section 6 covers exactly how that works.

**Grafana shows `3/3`.** Grafana itself plus two sidecars that watch for ConfigMaps containing dashboards and datasources, and load them without a restart.

Confirm the container names for yourself:

```bash
kubectl get pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring \
  -o jsonpath='{.spec.containers[*].name}'
echo
```

Then look at the services:

```bash
kubectl get svc -n monitoring
```

All `ClusterIP`. Nothing is exposed outside the cluster, which is why port forwarding is needed to reach any of it.

### Step 7: Confirm Storage Was Provisioned

```bash
kubectl get pvc -n monitoring
```

Every PVC must show `Bound`:

```
NAME                                                      STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
alertmanager-kube-prometheus-stack-alertmanager-db-...-0   Bound    pvc-9463   2Gi        RWO            gp3            4m
kube-prometheus-stack-grafana                             Bound    pvc-d3ca   5Gi        RWO            gp3            4m
prometheus-kube-prometheus-stack-prometheus-db-...-0       Bound    pvc-f3e4   20Gi       RWO            gp3            4m
```

`Bound` means the EBS CSI driver successfully created a real EBS volume in AWS and attached it. Anything showing `Pending` here means storage is broken, and the pods will never start. See Troubleshooting below.

### Step 8: Open the Prometheus UI

```bash
kubectl port-forward --address 0.0.0.0 \
  svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

This command blocks. Leave it running and open a second terminal for anything else.

Get the jump box public IP from the other terminal:

```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4
echo
```

Open in your browser:

```
http://<jump-box-public-ip>:9090
```

Run a query in the expression box:

```
up
```

Press Execute.

In Section 3, that query returned one row. Look at how many rows it returns now.

### Step 9: The Targets Page

Navigate to **Status**, then **Target health**.

This is the moment the whole module has been building towards.

You will see targets grouped by job, all discovered automatically:

- `serviceMonitor/monitoring/kube-prometheus-stack-apiserver` - the Kubernetes API server
- `serviceMonitor/monitoring/kube-prometheus-stack-kubelet` - one per node
- `serviceMonitor/monitoring/kube-prometheus-stack-coredns`
- `serviceMonitor/monitoring/kube-prometheus-stack-kube-state-metrics`
- `serviceMonitor/monitoring/kube-prometheus-stack-prometheus-node-exporter` - one per node
- `serviceMonitor/monitoring/kube-prometheus-stack-grafana`
- and more

Dozens of targets, in state UP.

Now compare that against Section 3. Same software. Same web interface. One target then, dozens now.

The difference is that you did not configure a single one of these. Prometheus asked the Kubernetes API what exists, and started scraping.

There is a second thing to notice here, and it is easy to miss. Some of these targets are Kubernetes control plane components: the API server, the kubelet, CoreDNS. Nobody installed an exporter for them. Kubernetes components expose Prometheus format metrics natively, which is a large part of why Prometheus became the standard on Kubernetes rather than some other tool.

Stop the port-forward with Ctrl+C when you are done.

---

## What Just Happened

One command produced roughly 60 Kubernetes objects. Worth seeing the scale of it:

```bash
kubectl get all -n monitoring
```

And the CRDs the operator installed:

```bash
kubectl get crds | grep monitoring.coreos.com
```

Those CRDs are the subject of Section 5, and they are what makes this installation fundamentally different from the one in Section 3. In Section 3, configuration was a file you edited on one machine. Here, configuration is Kubernetes objects you apply with kubectl and store in git.

Map it back to what we covered earlier:

| Concept from Sections 1 and 2 | Now running as |
|---|---|
| The collector | `prometheus-kube-prometheus-stack-prometheus-0` |
| Time-series storage | The 20Gi PVC bound to that pod |
| Service discovery | The operator, watching the Kubernetes API |
| Exporters | node-exporter DaemonSet, kube-state-metrics |
| Visualization | Grafana |
| Notification | Alertmanager |

Every actor from the generic architecture is now a real object you can point at.

---

## Troubleshooting

**PVC stuck in Pending, pods stuck in Pending**

The most common failure. Diagnose it properly rather than guessing:

```bash
kubectl describe pvc -n monitoring | grep -A 10 Events
```

Look at the Events section.

First, check the STORAGECLASS column in `kubectl get pvc -n monitoring`.

**If it is empty**, no StorageClass was assigned, and the PVC can never bind. This means there is no default StorageClass on the cluster. Create the gp3 StorageClass from CLUSTER-SETUP.md, then uninstall and reinstall, because a PVC's `storageClassName` is immutable and existing Pending claims will never recover:

```bash
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete pvc --all -n monitoring
```

Then install again.

**If a class is named**, read the Events instead:

- `waiting for first consumer to be created` alone is normal and temporary, because `WaitForFirstConsumer` delays the volume until a pod needs it.
- `UnauthorizedOperation` or an IAM error means the EBS CSI driver lacks permissions. Verify the pod identity association exists:

```bash
aws eks list-pod-identity-associations \
  --cluster-name observability-demo --region ap-south-1 --output json
```

You want an entry for service account `ebs-csi-controller-sa` in namespace `kube-system`.

- No events at all, and no CSI controller pods present, means the addon was never installed:

```bash
aws eks create-addon --cluster-name observability-demo \
  --addon-name aws-ebs-csi-driver --region ap-south-1
```

**Pods stuck in Pending with `Insufficient memory` or `Insufficient cpu`**

Not enough room on the nodes. Check what is actually free:

```bash
kubectl describe nodes | grep -A 6 "Allocated resources"
```

Two t3.large nodes are sufficient for this stack. A single t3.medium is not, and it usually fails here rather than at install time.

**`Error: INSTALLATION FAILED: context deadline exceeded`**

The `--wait` timed out. The install is often still progressing. Check before doing anything drastic:

```bash
kubectl get pods -n monitoring
```

If pods are still coming up, wait. If something is genuinely stuck, uninstall and retry after fixing the cause:

```bash
helm uninstall kube-prometheus-stack -n monitoring
```

**`cannot re-use a name that is still in use`**

A previous release exists, possibly failed. Inspect it:

```bash
helm list -n monitoring --all
```

Then remove it before reinstalling.

**Browser times out on port 9090**

Three possible causes, in the order worth checking:

1. `--address 0.0.0.0` missing from the port-forward command
2. Port 9090 not open to your IP in the jump box security group
3. The port-forward process died. It runs in the foreground and stops when the terminal closes.

A timeout points at the firewall or the missing address flag. A refused connection points at the port-forward not running.

**Prometheus pod restarting, OOMKilled**

Memory limit reached. On a large cluster this usually means high cardinality from a metric with unbounded labels. Section 2 covered why that happens. For this lab, raising the memory request in the values file and running `helm upgrade` is enough.

---

## Key Takeaways

- `kube-prometheus-stack` installs the operator, Prometheus, Alertmanager, Grafana, node-exporter and kube-state-metrics as one tested release.
- Chart version and app version are different things. The chart is the packaging, the app version is the Prometheus Operator release.
- Storage needs two things on EKS: the EBS CSI driver addon, and a default StorageClass using the `ebs.csi.aws.com` provisioner. The built-in `gp2` class uses a provisioner removed in Kubernetes 1.31 and is not marked default.
- An empty STORAGECLASS column in `kubectl get pvc` means no default StorageClass exists. That PVC will never bind, and it cannot be repaired in place because `storageClassName` is immutable.
- Without working storage, Helm reports success while every pod with a PVC sits Pending.
- `serviceMonitorSelectorNilUsesHelmValues: false` makes Prometheus watch all namespaces. Without it, ServiceMonitors you create later are silently ignored.
- Without `storageSpec`, Prometheus stores metrics in `emptyDir` and loses all history on every restart.
- Prometheus and Alertmanager run two containers. The second is `config-reloader`.
- Targets are discovered from the Kubernetes API. Nothing on the Targets page was configured by hand.
- Kubernetes control plane components expose Prometheus format metrics natively, with no exporter required.

---

## Interview Questions

**1. What is the difference between chart version and app version in a Helm chart?**

The chart version tracks the packaging: templates, default values, and chart dependencies. The app version tracks the software being deployed, in this case the Prometheus Operator. They move independently, so a chart version bump does not necessarily mean an application upgrade.

**2. You installed kube-prometheus-stack and Helm reported success, but the Prometheus pod is stuck in Pending. What do you check first?**

The PVC. `kubectl get pvc -n monitoring` will show it Pending, and `kubectl describe pvc` gives the reason in its Events. On EKS the usual cause is the EBS CSI driver not being installed, since EKS ships a default StorageClass but not the driver that fulfils it. Helm reports success because it created the objects correctly; the failure is in provisioning.

**3. Why does the Prometheus pod have two containers?**

The second is `config-reloader`. It watches the mounted ConfigMaps and Secrets containing scrape configuration and rules, and triggers a reload through the Prometheus HTTP API when they change. This allows configuration updates without restarting the pod or losing the in-memory state.

**4. What does `serviceMonitorSelectorNilUsesHelmValues: false` do, and why would you set it?**

By default the chart restricts Prometheus to ServiceMonitors labelled with the Helm release name. Setting it false makes Prometheus consider all ServiceMonitors in all namespaces. Without it, a ServiceMonitor created without the correct release label is silently ignored, which is difficult to diagnose because the object exists and no error is produced anywhere.

**5. Why is node-exporter a DaemonSet while kube-state-metrics is a Deployment?**

node-exporter reads metrics from the host it runs on, so it needs one instance on every node. kube-state-metrics reads from the Kubernetes API, which is a single cluster-wide source, so one replica is sufficient.

**6. What happens to your metrics if you do not configure storageSpec?**

Prometheus falls back to `emptyDir`, which is tied to the pod lifecycle. All historical data is lost whenever the pod restarts, including on every Helm upgrade.

**7. Why does Prometheus scrape the Kubernetes API server and kubelet without any exporter being installed for them?**

Kubernetes control plane components expose metrics in Prometheus exposition format natively. No translation layer is needed. This native support is a significant reason Prometheus became the default monitoring system on Kubernetes.

---

## What's Next

You now have a running stack, and you have seen that Prometheus discovered dozens of targets on its own.

The next question is how. What told Prometheus to scrape the kubelet? Nobody edited a configuration file. There is no `static_configs` anywhere.

The answer is Custom Resource Definitions, and they are the reason this installation is fundamentally different from the one in Section 3.

[Section 5: Custom Resource Definitions](./05-custom-resource-definitions.md)
