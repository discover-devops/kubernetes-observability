## Section 1: What is Grafana? 

### 1. Context (Why this exists)

Before tools like Grafana existed, system administrators monitored servers by SSHing into boxes, writing ad-hoc scripts, and running commands like `top` or `vmstat`. As systems grew to dozens or hundreds of servers, reading raw numerical output or raw logs directly became impossible.

Even when time-series databases like Prometheus arrived, staring at the raw PromQL HTTP API response or raw matrix tables did not allow engineers to make instant decisions during an outage.

* **Pain Point:** You cannot detect an anomalous spike across 50 microservices by reading text-based numerical metrics.
* **Real Production Scenario:** An e-commerce service experiences intermittent latency. The database CPU is at $85\%$, the payment service error rate is $2\%$, and worker node memory is near exhaustion. Without a single pane of glass aggregating these distinct systems, finding the root cause requires checking three different tools, leading to extended downtime (MTTR).

---

### 2. Concept (How it works)

Grafana is an open-source analytics and interactive visualization web application. It acts as a universal dashboard manager that queries data from specific databases and displays it through panels.

The defining characteristic of Grafana is its **read-only nature regarding metrics**: Grafana does not collect metrics, run agent daemons, or store time-series data. It is exclusively an analytics layer that queries external databases.

> ** Analogy:** Think of Prometheus as the engine and complex electrical sensors hidden under the hood of a racecar, continuously generating raw data. Grafana is the digital display cluster on the dashboard behind the steering wheel. The display cluster does not generate speed or burn fuel; it simply reads the sensors and turns raw numbers into an actionable speedometer and fuel gauge.

#### What Grafana Is NOT

* It is **not** a metric collection agent (like Telegraf or Datadog Agent).
* It is **not** a database (like Prometheus, InfluxDB, or MySQL).
* It is **not** an ingestion engine.

---

### 3. Internal Working

Grafana uses a modular backend plugin system. When a dashboard is loaded in a browser:

```
┌──────────────────────────────────────────────────────────────┐
│                   BROWSER / CLIENT UI                        │
│   Renders charts, reads mouse hovers, manages user inputs    │
└──────────────────────────────┬───────────────────────────────┘
                               │ HTTP / WebSocket
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    GRAFANA BACKEND SERVER                    │
│  - Query Engine                                              │
│  - Access Control (RBAC)                                     │
│  - Provisioning Engine                                       │
│  - Plugin Translator (Datasource Adapter)                    │
└──────────────────────────────┬───────────────────────────────┘
                               │
            Reads from ▼ (Never writes metrics)
┌──────────────┬──────────────┬───────────────┬────────────────┐
│  Prometheus  │     Loki     │ PostgreSQL/TS │   CloudWatch   │
│  (Metrics)   │    (Logs)    │ (Relational)  │     (AWS)      │
└──────────────┴──────────────┴───────────────┴────────────────┘

```

1. **Query Dispatch:** The browser client requests data for a visual panel.
2. **Backend Proxy:** The request hits the Grafana backend server (written in Go).
3. **Data Source Plugin Translation:** The backend passes the request to the specific data source plugin. The plugin translates Grafana's internal query structure into the native database query language (e.g., PromQL, LogQL, SQL).
4. **Upstream Execution:** The query runs against the upstream database API.
5. **JSON Struct Parsing:** The database returns raw time-series matrices or tabular rows as JSON. Grafana transforms this response into an internal data frame array and sends it back to the client browser to draw canvas charts.

---

### 4. Architecture Before Commands

Understanding the mental model of Grafana's core objects before touching configuration files:

```
[ Data Source Connection ]  ──►  [ Dashboard Container ]
                                         │
                                         ├──► [ Panel 1: PromQL Query ] ──► Data Frame Rendering
                                         └──► [ Panel 2: SQL Query ]    ──► Data Frame Rendering

```

* **Data Source:** The authentication and network configuration path pointing to a database backend.
* **Panel:** The individual query container responsible for executing a query and rendering a single visualization (e.g., Time Series, Heatmap, Stat).
* **Dashboard:** A grid layout file (saved internally as a JSON model) that organizes panels, global variables, time ranges, and refresh intervals.

---

### 5. Student Interaction & Doubts

* **Student Doubt:** *"If Grafana doesn't store metrics, what happens if my Grafana server crashes? Do I lose my historical metrics?"*
* **Instructor Answer:** No. Your metrics live inside Prometheus or your database backend. If Grafana crashes, you only lose dashboard configurations if you haven't persisted Grafana's internal database or used GitOps provisioning. Your historical metrics remain safe in Prometheus.


* **Student Doubt:** *"Is Prometheus mandatory to run Grafana?"*
* **Instructor Answer:** No. Grafana is database-agnostic. You can run Grafana attached strictly to MySQL, PostgreSQL, AWS CloudWatch, or Elasticsearch without Prometheus.



---

## Section 2: Installation & First Login (10 Minutes)

### 1. Context (Why this exists)

To run Grafana in production, it must persist its own operational data (users, dashboards, permissions, and data source metadata). While Grafana is stateless regarding *monitored metrics*, it relies on its internal database (SQLite by default, or PostgreSQL/MySQL for high availability) to store dashboard definitions.

---

### 2. Concept (How it works)

Grafana can be deployed as a standalone Linux binary, a Docker container, or via Helm on Kubernetes.

In production Kubernetes environments, we avoid managing Grafana manually. We deploy it using the official Helm chart and configure initial state declaratively through configuration files (`grafana.ini` and sidecar provisioners).

---

### 3. Internal Working (Helm / Kubernetes Stateful Deployment)

```
┌─────────────────────────────────────────────────────────────┐
│                   KUBERNETES POD                            │
│                                                             │
│   ┌──────────────────────────┐  ┌────────────────────────┐  │
│   │  Grafana Container       │  │ ConfigMap Volume       │  │
│   │  (Port 3000)             │◄─┼─ (grafana.ini)         │  │
│   └────────────┬─────────────┘  └────────────────────────┘  │
│                │                                            │
│                ▼ Storage Mount                              │
│   ┌──────────────────────────────────────────────────────┐  │
│   │ PersistentVolumeClaim (/var/lib/grafana)            │  │
│   │ (Stores internal SQLite DB: users, sessions, panels) │  │
│   └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

```

When Grafana boots:

1. It reads system settings from `/etc/grafana/grafana.ini`.
2. It initializes or updates its internal schema inside `/var/lib/grafana/grafana.db` (SQLite).
3. It scans `/etc/grafana/provisioning/` for declarative datasources and dashboards.

---

### 4. Hands-on Lab: Deployment Options

#### Option A: Production-Grade Helm Deployment (Kubernetes - Recommended)

Create a deployment configuration file:

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

Deploy via Helm:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
kubectl create namespace monitoring

helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml \
  --wait

```

Verify deployment and set up local port forwarding:

```bash
# Check pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# grafana-67c4c7b89-x8q2l   1/1     Running   0          45s

# Expose locally for UI access
kubectl port-forward svc/grafana 3000:80 -n monitoring

```

#### Option B: Quick Local Docker Container Lab

```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  -v grafana-storage:/var/lib/grafana \
  -e GF_SECURITY_ADMIN_PASSWORD=StrongPassword123! \
  grafana/grafana:latest

```

#### First Login Verification

1. Open browser to `http://localhost:3000`
2. Credentials: User = `admin`, Password = `StrongPassword123!`

---

### 5. Debugging & Common Mistakes

* **Mistake:** Pod enters `CrashLoopBackOff` when `persistence.enabled` is set to `true`.
* **Cause:** The underlying storage class is missing or permissions on `/var/lib/grafana` are restricted (ID 472 for default Grafana user).
* **Fix:** Check logs via `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana` and verify storage provisioner permissions.



---

## Section 3: Data Sources (15 Minutes)

### 1. Context (Why this exists)

Connecting dashboards directly to database credentials typed into a web form works for hobby projects, but breaks down in engineering teams.

If a pod restarts or moves nodes, UI-configured settings can be lost. To maintain infrastructure as code, Grafana provides **Declarative Data Source Provisioning**, allowing data source connections to be defined in YAML files managed via Git repositories.

---

### 2. Concept (How it works)

A **Data Source** is an abstraction layer inside Grafana that standardizes database connectivity parameters:

* Network Location (URL/Endpoint)
* Authentication Details (TLS, Basic Auth, Bearer Tokens)
* Access Mode (`proxy` vs `direct`)
* Operational Parameters (Scrape Interval, Timeout limits)

#### Access Modes Explained

* **Server Access (`proxy`) [RECOMMENDED]:** The browser sends requests to the Grafana backend, and Grafana proxies the request to the target data source. This keeps the database hidden behind Grafana's network boundaries.
* **Browser Access (`direct`):** The browser directly makes HTTP calls to the database URL. This requires exposure of the database directly to end-user browser clients (generally insecure and prohibited in production).

---

### 3. Internal Working: GitOps Provisioning Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                        │
│                                                              │
│  ┌─────────────────────────┐      ┌──────────────────────┐   │
│  │ ConfigMap:              │      │ Grafana Pod          │   │
│  │ grafana-datasources     │ Mount│ /etc/grafana/        │   │
│  │ (datasources.yaml)      ├─────►│ provisioning/        │   │
│  └─────────────────────────┘      │ datasources/         │   │
│                                   └──────────┬───────────┘   │
│                                              │ Internal Boot │
│                                              ▼ File Scan     │
│                                   ┌──────────────────────┐   │
│                                   │ Synchronizes to      │   │
│                                   │ Memory / DB (Read    │   │
│                                   │ Only in UI)          │   │
│                                   └──────────────────────┘   │
└──────────────────────────────────────────────────────────────┘

```

When Grafana starts up, its internal provisioning engine checks `/etc/grafana/provisioning/datasources/`. Any valid YAML configurations parsed there automatically override UI settings and lock those data sources as `editable: false` to prevent drift.

---

### 4. Hands-on Lab: GitOps Data Source Configuration

Create a declarative data source file:

```yaml
cat > datasources.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    # Fixed UID ensures dashboard JSON files remain fully portable across environments
    uid: prometheus-main
    url: http://prometheus-operated.monitoring.svc.cluster.local:9090
    isDefault: true
    access: proxy
    editable: false
    jsonData:
      timeInterval: "30s"
      queryTimeout: "60s"
      httpMethod: POST
EOF

```

>  ** Note on the UID Parameter:** Emphasize to students that `uid: prometheus-main` is crucial. Grafana dashboards reference data sources using these UIDs in their raw JSON definitions. If you import a dashboard without matching UIDs, every panel breaks until manually re-linked.

Apply to Kubernetes as a mounted ConfigMap:

```bash
kubectl create configmap grafana-datasources \
  --from-file=datasources.yaml \
  -n monitoring

```

---

### 5. Student Interaction & Doubts

* **Student Doubt:** *"Why set `httpMethod: POST` for Prometheus?"*
* **Instructor Answer:** By default, Prometheus queries use `GET`. However, complex PromQL queries with large label-set arrays exceed the standard maximum HTTP URL length limits (typically 2048 to 8192 bytes). Using `POST` encodes query parameters into the request body, preventing `414 Request-URI Too Large` errors during heavy dashboards.



---

## Section 4: Building Production Dashboards

### 1. Context (Why this exists)

Creating visual panels without structure leads to "dashboard clutter"—monolithic, unreadable displays filled with arbitrary charts that don't help during incident response.

Production monitoring demands intentional visualization choices: matching specific metric types (counters, gauges) to appropriate visualization models (Time Series, Stat, Gauge, Bar Chart) with precise unit normalization and alerting thresholds.

---

### 2. Concept (How it works)

A **Panel** executes a target data query, applies transformation rules, and maps the output to a visualization canvas.

```
┌──────────────────────────────────────────────────────────────┐
│                        PANEL PIPELINE                        │
│                                                              │
│  ┌──────────────┐     ┌───────────────┐     ┌─────────────┐  │
│  │ Data Source  │────►│ Transformation│────►│ Canvas      │  │
│  │ Query        │     │ Engine        │     │ Rendering   │  │
│  └──────────────┘     └───────────────┘     └─────────────┘  │
│  (PromQL Matrix)      (Unit conversion,     (Gauge, Chart,│  │
│                       Value mapping)        Table Output) │  │
└──────────────────────────────────────────────────────────────┘

```

#### Core Panel Types & Use Cases

* **Time Series:** Displays metrics over time. Essential for trends, rate spikes, and historical performance analysis.
* **Gauge:** Shows current value against defined absolute operational limits (e.g., Memory Usage % vs maximum capacity).
* **Stat:** Displays a single aggregate value prominently, often with dynamic background coloring based on warning thresholds.
* **Bar Chart:** Best for discrete categorizations (e.g., total pods per namespace).

---

### 3. Internal Working: Dashboard Portability (JSON Model)

Every Grafana dashboard is stored as a structured JSON object.

When you make changes in the visual interface, Grafana compiles those choices into a single declarative JSON tree containing panel placement coordinates, operational thresholds, query definitions, and system UIDs.

```
{
  "title": "Node Overview",
  "uid": "node-overview-prod",
  "panels": [
    {
      "id": 1,
      "title": "CPU Usage %",
      "type": "timeseries",
      "datasource": { "type": "prometheus", "uid": "prometheus-main" },
      "targets": [
        { "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)" }
      ]
    }
  ]
}

```

---

### 4. Hands-on Lab: Constructing a Production Infrastructure Dashboard

Navigate to **Dashboards → New Dashboard → Add Visualization**, select **Prometheus**, and build out the following 5 panels:

#### Panel 1: Node CPU Usage

* **Query (PromQL):**
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

```


* **Panel Configuration:**
* **Visualization:** Time series
* **Title:** Node CPU Usage %
* **Standard options → Unit:** `Percent (0-100)`
* **Thresholds:** `80` (Yellow), `90` (Red)



#### Panel 2: Memory Usage Gauge

* **Query (PromQL):**
```promql
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

```


* **Panel Configuration:**
* **Visualization:** Gauge
* **Title:** Memory Utilization %
* **Standard options → Unit:** `Percent (0-100)`
* **Min/Max:** `0` / `100`
* **Thresholds:** `70` (Yellow), `85` (Red)



#### Panel 3: Running Pods per Namespace

* **Query (PromQL):**
```promql
count by (namespace) (kube_pod_info{phase="Running"})

```


* **Panel Configuration:**
* **Visualization:** Bar chart
* **Title:** Active Running Pods by Namespace
* **X-axis:** `namespace`



#### Panel 4: Pod Restart Rate

* **Query (PromQL):**
```promql
sum(increase(kube_pod_container_status_restarts_total[1h]))

```


* **Panel Configuration:**
* **Visualization:** Stat
* **Title:** Pod Restarts (Last 1 Hour)
* **Value Options → Color Mode:** Background
* **Thresholds:** `0` (Green), `1` (Yellow), `5` (Red)



#### Panel 5: HTTP Error Rate Trend

* **Query (PromQL):**
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service) * 100

```


* **Panel Configuration:**
* **Visualization:** Time series
* **Title:** HTTP 5xx Error Rate
* **Standard Options → Unit:** `Percent (0-100)`
* **Graph Styles → Fill Opacity:** `10`



---

### Exporting & Importing Dashboard Code (GitOps Flow)

To make this dashboard portable across dev, staging, and production clusters:

#### Exporting:

1. Click the **Share** button in the top navigation bar.
2. Select the **Export** tab.
3. Toggle on **Export for sharing externally** (this replaces site-specific UIDs with generic variable placeholders).
4. Click **Save to file** to generate the JSON template.

#### Importing:

1. In a destination Grafana instance, navigate to **Dashboards → New → Import**.
2. Upload the saved JSON file or paste its raw contents directly into the text panel.
3. Select your target target data source (`prometheus-main`) from the mapped dropdown.
4. Click **Import**.

---

### 5. Troubleshooting & Debugging Common Panel Issues

#### Issue: Panel displays "No Data"

* **Diagnosis Sequence:**
1. Verify the selected data source in the panel header is non-empty.
2. Copy the PromQL string into Prometheus native UI (`http://prometheus-url:9090`) to verify the underlying metrics exist.
3. Expand the Dashboard Time Range in the upper right (e.g., change `Last 5 minutes` to `Last 3 hours`).



#### Issue: Time Series graphs show unrealistic values (e.g., $10,000\%$)

* **Diagnosis:** Missing unit definitions or missing mathematical normalization. Raw metric rates evaluate as a ratio from $0.0$ to $1.0$. If you set the Unit to `Percent (0-100)` without multiplying the expression by $100$ in your PromQL, or if you apply `Percent (0.0-1.0)` inappropriately, scaling calculations will display incorrectly.

---

### 6. Summary Checkup & Follow-Up Questions

To close out Part 1 of this live module, check student understanding with these core questions:

1. *Why should we explicitly define custom, deterministic UIDs in data source configuration files rather than letting Grafana generate random strings on deployment?*
2. *If your production Kubernetes node memory query shows $90\%$ memory utilization, but your Grafana Stat panel remains green, what operational panel configuration did you miss?*
