
## Module 2: Setting Up Prometheus & Grafana on a K3s Cluster

---

## Context

Before you can write a single PromQL query, you need a working observability stack — a Kubernetes cluster, a metrics database (Prometheus), and a visualization layer (Grafana) that can talk to it.

In production, teams run managed Kubernetes (EKS, AKS, GKE). For learning PromQL and dashboard design, that's overkill — you'd spend more time managing infrastructure than learning monitoring. **K3s** solves this: it's a lightweight, single-binary Kubernetes distribution that gives you a fully compliant cluster on one VM in about a minute, with `kubectl` and a working `kubeconfig` included out of the box.

This module builds the foundation the rest of the masterclass sits on. By the end, you'll have:
- A single-node K3s cluster running on an Azure Ubuntu VM
- Prometheus installed and scraping cluster metrics
- Grafana installed, pre-wired to Prometheus as a data source
- A verified connection, ready for dashboard building in Module 2

---

## Concept

**Why K3s instead of kubeadm or a cloud-managed cluster?**
K3s strips out legacy/alpha features and packages the control plane as a single process, making it fast to install and easy to reason about — ideal for a lab environment where the goal is to learn Kubernetes-native monitoring patterns, not cluster administration.

**Why Helm?**
Prometheus and Grafana each ship complex Kubernetes manifests — Deployments, Services, ConfigMaps, RBAC, PersistentVolumeClaims. Helm packages all of this into a single installable "chart" with configurable values, so you install and configure in one command instead of hand-writing YAML.

**Why does Grafana already know about Prometheus?**
Helm charts support **provisioning as code**. Instead of manually clicking through the Grafana UI to add a data source, you declare the data source inside `grafana-values.yaml`. Helm injects this configuration when the pod starts, so the data source exists automatically on first login. This is the production-standard approach — your monitoring configuration lives in version control, not in someone's browser session.

**What is a Headless Service, and why does `prometheus-operated` show `None`?**
A normal Kubernetes Service gets a virtual `ClusterIP` and load-balances traffic across the Pods behind it. A **Headless Service** (`clusterIP: None`) skips the virtual IP entirely — Kubernetes DNS returns the actual Pod IPs directly, and `kube-proxy` does no load-balancing. The Prometheus Operator creates its service this way so clients can resolve and talk to specific Prometheus Pods directly, rather than through a load-balanced abstraction. That's why `kubectl get svc` shows `None` in the `CLUSTER-IP` column for `prometheus-operated` — it's expected, not an error.

---

## Lab

### Step 1: Install K3s

```bash
curl -sfL https://get.k3s.io | sh -
```

This single command:
- Installs K3s (lightweight Kubernetes)
- Installs `kubectl`
- Creates a single-node Kubernetes cluster
- Starts the K3s service automatically

### Step 2: Verify the K3s Service

```bash
sudo systemctl status k3s --no-pager
```

Expected output: `Active: active (running)`

### Step 3: Verify the Cluster

K3s stores its kubeconfig under `/etc/rancher/k3s`. Before setting up `kubectl` for regular use, confirm the cluster is up using the K3s-provided command:

```bash
sudo k3s kubectl get nodes
```

### Step 4: Configure `kubectl` for Normal Use

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

kubectl get nodes
```

Set the `KUBECONFIG` environment variable so `kubectl` always points to the right config, and persist it across sessions:

```bash
export KUBECONFIG=$HOME/.kube/config
kubectl get nodes

echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

### Step 5: Create the Monitoring Namespace

```bash
kubectl config view
kubectl get ns
kubectl create namespace monitoring
```

### Step 6: Define Grafana Configuration as Code

Create `grafana-values.yaml`. This file sets the admin password, enables persistent storage, and — critically — pre-provisions the Prometheus data source:

```bash
cat > grafana-values.yaml << 'EOF'
adminPassword: "StrongPassword123!"

persistence:
  enabled: true
  size: 5Gi

service:
  type: ClusterIP

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-operated:9090
      isDefault: true
      access: proxy
      editable: true

grafana.ini:
  server:
    root_url: "%(protocol)s://%(domain)s/"
  analytics:
    check_for_updates: false
EOF
```

> **Note:** Use a strong, unique password for any non-lab environment. `StrongPassword123!` is for classroom use only.

### Step 7: Add the Grafana Helm Repository and Install

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml \
  --wait
```

### Step 8: Retrieve the Grafana Admin Password

```bash
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

This confirms the `adminPassword` set in `grafana-values.yaml` was applied correctly.

### Step 9: Access Grafana

```bash
kubectl port-forward --address 0.0.0.0 svc/grafana 3000:80 -n monitoring
```

Keep this terminal running, then open:

```
http://<your-vm-public-ip>:3000
```

Login:
- **Username:** `admin`
- **Password:** the value retrieved in Step 8

> **Network access:** On Azure, port 3000 must be opened via a **Network Security Group (NSG)** — the Azure equivalent of an AWS Security Group. NSGs attach to a NIC or a subnet rather than directly to the VM. Add an inbound rule allowing TCP 3000 from your IP. For lab use, opening it broadly is acceptable; for anything beyond a lab, restrict the source IP range.

### Step 10: Install Prometheus

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --wait
```

### Step 11: Inspect the Monitoring Services

```bash
kubectl get svc -n monitoring
```

Both Grafana and Prometheus are installed with default chart values, so both expose `ClusterIP` services — no `NodePort` is used or needed for this lab.

You'll notice:

```
prometheus-operated    ClusterIP   None   <none>   9090/TCP
```

`None` under `CLUSTER-IP` is expected — see the Headless Service explanation above. Grafana reaches it internally at `http://prometheus-operated:9090`.

### Step 12: Verify the Data Source in Grafana

Since the data source was provisioned via `grafana-values.yaml`, no manual setup is required — but verify the connection:

1. Left sidebar → **Connections** (or **Configuration**) → **Data Sources**
2. Click **Prometheus**
3. Confirm the settings:

| Setting | Value | Purpose |
|---|---|---|
| Prometheus Server URL | `http://prometheus-operated:9090` | Connects Grafana to Prometheus |
| Authentication | No Authentication | Internal Kubernetes cluster communication |
| HTTP Method | POST | Default/recommended |

4. Click **Save & Test** → expect **"Successfully queried the Prometheus API."**

This confirms Grafana can send PromQL queries to Prometheus and receive results. Every dashboard panel from this point forward depends on this connection.

---

## Knowledge Check

**Q1. What makes a Kubernetes Service "headless"?**
Setting `clusterIP: None` in the Service spec.

**Q2. Does a Headless Service get a virtual IP?**
No — Kubernetes DNS returns the actual Pod IPs directly.

**Q3. What does `kube-proxy` do for a Headless Service?**
Nothing — it performs no load-balancing for headless services.

**Q4. Why does `prometheus-operated` use a Headless Service?**
So clients (like Grafana) can resolve and connect to specific Prometheus Pod endpoints directly, rather than through a single load-balanced virtual IP.

**Q5. Why didn't we need to manually add the Prometheus data source in the Grafana UI?**
It was provisioned as code via the `datasources` block in `grafana-values.yaml`, and Grafana auto-created it on startup — the production-standard pattern for keeping monitoring configuration in version control.

**Q6. What is the AWS equivalent of an Azure Network Security Group (NSG)?**
A Security Group — though NSGs attach to a NIC or subnet, while AWS Security Groups attach directly to the instance/ENI.

---

**Next module:** Building your first Grafana dashboard — from empty canvas to your first PromQL-powered panel.
