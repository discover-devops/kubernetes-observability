# Topic 3 – Installation & First Login


## Context

So far, we understand what Grafana is and the five core concepts.

Now we need to actually run Grafana.

Since our previous PromQL session already has a **K3s Kubernetes cluster**, we'll use that same cluster.

The three installation options:

1. **Helm — Kubernetes**
2. **Docker — Local Lab**
3. **apt — Ubuntu/Debian VMs**

For our live session, we'll focus on **Helm**, because we're running Grafana on Kubernetes.

The other two options are useful to know, but we don't need to perform all three installations during the live class.

---

# Concept 1 – Why Helm?

The document recommends Helm for Kubernetes.

Instead of manually creating:

* Deployment
* Service
* ConfigMaps
* PersistentVolumeClaim
* Configuration

we can use the Grafana Helm chart.

The Helm chart packages the Kubernetes resources and configuration needed to deploy Grafana.

So our flow is:

```text
Helm
  ↓
Grafana Helm Chart
  ↓
Kubernetes Resources
  ↓
Grafana Pod
  ↓
Grafana Service
```

The important point:

> Helm is the deployment mechanism. Grafana is the application being deployed.

---

# Lab 1 – Add the Grafana Helm Repository

The first command from the document is:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
```

### What does this do?

We're telling Helm:

> "Add Grafana's Helm chart repository and give it the local name `grafana`."

Now Helm knows where to find Grafana's chart.

Next:

```bash
helm repo update
```

This refreshes the information about the charts available in the repositories we've configured.

So:

```bash
helm repo add
```

means **add the repository**.

And:

```bash
helm repo update
```

means **refresh the chart information**.

---

# Lab 2 – Create the Namespace

The document uses:

```bash
kubectl create namespace monitoring
```

Why?

We don't want Grafana resources mixed with resources from other applications.

We'll put our monitoring components inside:

```text
monitoring
```

namespace.

So now our Kubernetes environment looks conceptually like:

```text
K3s Cluster
│
└── monitoring namespace
       │
       └── Grafana
```

---

# Concept 2 – Grafana Configuration Using `values.yaml`

Now comes an important Helm concept.

The document creates:

```bash
grafana-values.yaml
```

This file contains the configuration that we want to give to the Grafana Helm chart.

For example:

```yaml
adminPassword: "StrongPassword123!"
```

We're defining the initial Grafana administrator password.

Then:

```yaml
persistence:
  enabled: true
  size: 5Gi
```

This is important.

### What does persistence mean?

Grafana stores things such as its configuration and dashboards.

If we enable persistence:

```yaml
persistence:
  enabled: true
```

we are asking Helm/Grafana to use persistent storage rather than relying only on the container's temporary filesystem.

The document specifies:

```yaml
size: 5Gi
```

So the persistent storage requested is **5 GiB**.

---

# Concept 3 – Grafana Service

The document has:

```yaml
service:
  type: ClusterIP
```

A Kubernetes `ClusterIP` service makes Grafana accessible **inside the Kubernetes cluster**.

It does not expose Grafana directly to the Internet.

That's why the document later uses:

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

We'll come back to that.

The document also comments:

```yaml
# Change to LoadBalancer on cloud
```

So on a cloud Kubernetes environment, you could use:

```yaml
service:
  type: LoadBalancer
```

But **we don't need that for our K3s lab**.

We'll stay with:

```yaml
ClusterIP
```

exactly as the document shows.

---

# Concept 4 – Automatic Prometheus Data Source

Now we reach an important part of the document.

Inside `grafana-values.yaml`:

```yaml
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
```

This tells Grafana:

> "When Grafana starts, automatically configure Prometheus as a data source."

So we don't have to manually go into the Grafana UI and add Prometheus later.

That's called **provisioning**.

We'll study provisioning properly in the Data Sources section.

For now, we only need to understand:

```text
values.yaml
      ↓
Helm
      ↓
Grafana configuration
      ↓
Prometheus automatically configured
```

---

# Important: What is `prometheus-operated:9090`?

This line may generate a  question:

```yaml
url: http://prometheus-operated:9090
```

This is the URL Grafana will use to reach Prometheus **inside Kubernetes**.

`prometheus-operated` is expected to be the Kubernetes Service name for the Prometheus installation used in the document.

So Grafana is communicating with Prometheus through the Kubernetes network.

Conceptually:

```text
Grafana Pod
    │
    │ HTTP
    ▼
prometheus-operated:9090
    │
    ▼
Prometheus
```

For **our lab**, we'll verify that the Prometheus service from our previous setup actually has this name before installing Grafana.

We should not blindly assume the service name.

---

# Lab 3 – Create the Values File

The document uses:

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

We don't need to explain every line of `grafana.ini` deeply here.

The important teaching points are:

* `adminPassword` → initial admin password
* `persistence.enabled` → enable persistent storage
* `size: 5Gi` → storage size
* `service.type` → Kubernetes service type
* `datasources` → automatically configure Prometheus
* `isDefault: true` → make Prometheus the default data source
* `access: proxy` → Grafana backend communicates with Prometheus
* `editable: true` → allow the data source to be edited through Grafana

---

# Lab 4 – Install Grafana

Now we install it:

```bash
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml \
  --wait
```

Let's understand this command.

### `helm install`

We're asking Helm to install something.

### First `grafana`

```bash
grafana
```

This is the **release name**.

### Second `grafana/grafana`

```bash
grafana/grafana
```

This means:

```text
Repository = grafana
Chart      = grafana
```

### `--namespace monitoring`

Install the release in our monitoring namespace.

### `--values grafana-values.yaml`

Use our custom configuration.

### `--wait`

Tell Helm to wait until the resources are ready before considering the installation complete.

---

# Lab 5 – Verify the Installation

The document gives:

```bash
kubectl get pods -n monitoring | grep grafana
```

We want to see the Grafana Pod.

Then:

```bash
kubectl get svc -n monitoring | grep grafana
```

We want to see the Grafana Service.

Conceptually:

```text
Pod
 ↓
Grafana application

Service
 ↓
Network endpoint for Grafana
```

---

# Lab 6 – Access Grafana

Because our Service is:

```yaml
type: ClusterIP
```

we'll use port-forwarding.

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

This creates a temporary connection:

```text
Your Laptop
localhost:3000
      │
      │ port-forward
      ▼
Kubernetes Service
grafana:80
      │
      ▼
Grafana Pod
```

Now open:

```text
http://localhost:3000
```

---

# First Login

The document specifies:

```text
Username: admin
Password: StrongPassword123!
```

We log in with those credentials.

Grafana may then ask us to change the admin password.

The document says this can be skipped in a lab environment, but in production the password should always be changed.

### Teaching point

Make the distinction clear:

**Lab:**

We can use the predefined password for simplicity.

**Production:**

Never leave a known/default password.

---

# What About Docker and apt?

The document also provides two alternatives.

### Docker

```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  -v grafana-storage:/var/lib/grafana \
  -e GF_SECURITY_ADMIN_PASSWORD=StrongPassword123! \
  grafana/grafana:latest
```

This is useful when you want Grafana running locally without Kubernetes.

### apt

The document also provides an Ubuntu/Debian VM installation using the Grafana package repository.

We **don't need to perform these during our live Kubernetes class**.

Note:

> "Grafana can be installed through Helm, Docker, or OS packages. For our Kubernetes environment, we're using Helm."

---

# Final Recap

Before moving to Data Sources, ask them to remember these points:

**1. How are we installing Grafana?**

→ Helm.

**2. Where are we installing it?**

→ `monitoring` namespace in our existing K3s cluster.

**3. What configuration file are we using?**

→ `grafana-values.yaml`.

**4. Why enable persistence?**

→ To persist Grafana data/configuration beyond the lifetime of the Pod.

**5. What Service type are we using?**

→ `ClusterIP`.

**6. How do we access it?**

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

**7. What URL do we open?**

```text
http://localhost:3000
```

**8. What is our initial username?**

```text
admin
```

**9. What is Grafana's data source in this class?**

→ Prometheus.

---

### One important live-session check

Before running the Helm installation, I would do this **one quick command** on your existing K3s cluster:

```bash
kubectl get svc -n monitoring
```

We want to confirm the exact Prometheus Service name from your previous PromQL setup. If it is `prometheus-operated`, we can use the document's values **without modification**. If your previous installation created a different Service name, we'll change only that URL so the lab actually works.
