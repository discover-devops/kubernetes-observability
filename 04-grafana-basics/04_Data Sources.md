# Topic 4 – Data Sources

## Context

We know that Grafana does not collect or store metrics.

So naturally, the next question is:

> **Where does Grafana get its data from?**

The answer is: **Data Sources**.

A Data Source is the connection between Grafana and the backend system that contains the data.

For our exmple:

```text
Grafana
   ↓
Prometheus Data Source
   ↓
Prometheus
   ↓
Metrics
```

Without a data source, Grafana has nothing to visualize.

---

# Concept 1 – What is a Data Source?

A **Data Source** tells Grafana:

> "Where is my data, and how should I communicate with that system?"

For example:

| Data Source   | Data             |
| ------------- | ---------------- |
| Prometheus    | Metrics          |
| Loki          | Logs             |
| MySQL         | Relational data  |
| PostgreSQL    | Relational data  |
| CloudWatch    | AWS metrics      |
| Elasticsearch | Logs/search      |
| InfluxDB      | Time-series data |

So Grafana itself doesn't need to understand how every backend stores its data.

Instead, Grafana uses a **Data Source plugin**.

---

# Concept 2 – How Grafana Talks to Prometheus

This is the most important diagram in this section.

Suppose our Grafana panel contains:

```promql
rate(http_requests_total[5m])
```

What happens?

```text
┌──────────────────────────────┐
│           Grafana            │
│                              │
│  Panel Query                 │
│  rate(http_requests_total)   │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Prometheus Data Source       │
│ Plugin                       │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│       Prometheus             │
│                              │
│      Executes PromQL         │
└──────────────┬───────────────┘
               │
               │ JSON response
               ▼
┌──────────────────────────────┐
│           Grafana            │
│                              │
│      Renders the graph       │
└──────────────────────────────┘
```

This is the pipeline you should remember:

> **Panel → Data Source → Backend → Result → Grafana visualization**

---

# Concept 3 – What Does the Data Source Plugin Do?

The Prometheus Data Source plugin acts as the communication layer between Grafana and Prometheus.

For example:

```text
Grafana
   │
   │ PromQL
   ▼
Prometheus Data Source Plugin
   │
   │ HTTP API request
   ▼
Prometheus
   │
   │ JSON response
   ▼
Grafana
   │
   ▼
Graph
```

The document shows an example of the HTTP API communication:

```text
GET /api/v1/query_range?query=...
```

The important concept is:

> Grafana sends the query to the configured data source, the data source communicates with Prometheus, and Grafana receives the result.

---

# Concept 4 – Every Panel Has a Query

This is another important statement from the document:

> **Every panel in Grafana has a query.**

For example:

### CPU panel

```promql
rate(node_cpu_seconds_total[5m])
```

### Memory panel

```promql
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
```

### Pod panel

```promql
count(kube_pod_info)
```

The query tells Grafana **what data we want**.

The visualization tells Grafana **how we want to display it**.

For example:

```text
Query
  ↓
CPU data
  ↓
Time Series visualization
  ↓
CPU graph
```

---

# Lab 1 – Add Prometheus Manually

Now let's actually configure the Data Source through the Grafana UI.

From the Grafana UI:

```text
Configuration
      ↓
Data Sources
      ↓
Add data source
      ↓
Prometheus
```

We'll now provide the Prometheus connection details.

### Name

```text
Prometheus
```

### URL

For our Kubernetes setup:

```text
http://prometheus-operated:9090
```

The document also mentions:

```text
http://localhost:9090
```

for a local Prometheus installation.

But because we're running Prometheus inside Kubernetes, we'll use the Kubernetes Service URL.

---

# Important Question: Why Don't We Use `localhost:9090`?

This is a very good student question.

Suppose Grafana is running inside Kubernetes.

Inside the Grafana container:

```text
localhost
```

means:

> **the Grafana container itself**

It does **not** mean your laptop and it does not mean the Prometheus Pod.

Therefore:

```text
localhost:9090
```

would only work if Prometheus were actually running on the same network endpoint as Grafana.

In Kubernetes, we normally communicate using the Kubernetes Service:

```text
prometheus-operated:9090
```

So:

```text
Grafana Pod
     │
     ▼
prometheus-operated:9090
     │
     ▼
Prometheus
```

---

# Save & Test

After entering the URL:

```text
http://prometheus-operated:9090
```

click:

**Save & Test**

Grafana should show:

> **Data source is working**

That confirms that Grafana can communicate with Prometheus.

---

# Concept 5 – Manual Configuration vs Provisioning

Now the document introduces an important production concept.

We just configured Prometheus through the UI.

That's perfectly fine for learning.

But imagine a production environment where you have:

* 20 Grafana instances
* multiple Kubernetes clusters
* several environments
* GitOps practices

Would you manually configure every Grafana instance?

No.

Instead, we can configure the data source as code.

This is called **provisioning**.

---

# Provisioning – GitOps Approach

The document gives us a file called:

```text
datasources.yaml
```

Example:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus-main
    url: http://prometheus-operated:9090
    isDefault: true
    access: proxy
    editable: false
```

Instead of:

```text
Human
  ↓
Grafana UI
  ↓
Click buttons
```

we have:

```text
Git / Configuration
        ↓
datasources.yaml
        ↓
Grafana
        ↓
Prometheus configured
```

This is much more suitable for automated environments.

---

# Concept 6 – Understanding the Important Fields

Let's go through the fields from the document.

### `name`

```yaml
name: Prometheus
```

This is the name displayed inside Grafana.

---

### `type`

```yaml
type: prometheus
```

This tells Grafana which Data Source plugin should be used.

---

### `uid`

```yaml
uid: prometheus-main
```

This is important.

The UID is a **stable identifier** for the data source.

Why do we care?

Imagine we create a dashboard that references:

```text
Prometheus
```

and then move that dashboard to another Grafana instance.

If the data source identity changes, the dashboard may not know which Prometheus data source it should use.

A fixed UID helps make the dashboard configuration portable.

So the key teaching point is:

> **Use a stable Data Source UID when provisioning so dashboards can reliably reference the same data source across environments.**

---

### `url`

```yaml
url: http://prometheus-operated:9090
```

This tells Grafana where Prometheus is located.

---

### `isDefault`

```yaml
isDefault: true
```

This makes Prometheus the default data source.

So when we're creating a new panel, Grafana can automatically select Prometheus.

---

### `access`

```yaml
access: proxy
```

This means Grafana's backend communicates with Prometheus.

Conceptually:

```text
Browser
   ↓
Grafana
   ↓
Prometheus
```

rather than the browser directly communicating with Prometheus.

---

### `editable`

```yaml
editable: false
```

This is a production-oriented setting.

It means the provisioned data source shouldn't be modified through the Grafana UI.

Why?

Because configuration is supposed to be managed through the configuration file/GitOps process rather than someone manually changing it in the UI.

---

# `jsonData`

The document also shows:

```yaml
jsonData:
  timeInterval: "30s"
  queryTimeout: "60s"
  httpMethod: POST
```

We should understand what these mean at a high level.

### `timeInterval`

```yaml
timeInterval: "30s"
```

This tells Grafana the expected data/query interval.

The document says to match it with the Prometheus scrape interval.

---

### `queryTimeout`

```yaml
queryTimeout: "60s"
```

This specifies how long Grafana should wait for a query before timing out.

---

### `httpMethod`

```yaml
httpMethod: POST
```

The document notes that POST is useful for larger queries.

We don't need to go deeper into HTTP methods in this session.

---

# Loki Example

The document also shows that Grafana isn't limited to Prometheus.

For example:

```yaml
- name: Loki
  type: loki
  uid: loki-main
  url: http://loki:3100
  access: proxy
  editable: false
```

So one Grafana installation could have:

```text
                 Grafana
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
   Prometheus      Loki       MySQL
    Metrics        Logs       SQL Data
```

This is one of Grafana's major strengths.

---

# Lab 2 – Provisioning with ConfigMap

The document shows how the configuration can be placed into Kubernetes.

First:

```bash
kubectl create configmap grafana-datasources \
  --from-file=datasources.yaml \
  -n monitoring
```

This creates a Kubernetes ConfigMap containing our:

```text
datasources.yaml
```

The document then says that this configuration should be mounted into:

```text
/etc/grafana/provisioning/datasources/datasources.yaml
```

We don't need to build the complete ConfigMap + Deployment volume-mount setup in this class unless the assignment specifically asks for it.

The important concept is:

> **Grafana provisioning allows configuration to be managed as code instead of manually through the UI.**

---

# Available Data Sources

The document gives us this list:

| Data Source        | Use Case             |
| ------------------ | -------------------- |
| Prometheus         | Metrics              |
| Loki               | Logs                 |
| Tempo / Jaeger     | Distributed traces   |
| MySQL / PostgreSQL | Relational databases |
| Elasticsearch      | Logs and search      |
| CloudWatch         | AWS metrics          |
| InfluxDB           | Time series          |
| TestData           | Learning and demos   |



Remember:

> "The Grafana mental model doesn't change. Connect the data source, use the query language supported by that source, and Grafana visualizes the result."

For this course:

**Prometheus is our focus.**

---

# Lab 3 – Explore the Data Source

Now we're going to test our Prometheus connection before creating a dashboard.

From Grafana:

```text
Left Sidebar
    ↓
Explore
    ↓
Select Prometheus
```

This is where we can experiment with queries.

---

## Query 1 – `up`

Start with:

```promql
up
```

This is a very good first query because it gives us a simple result.

The result tells us whether the monitored targets are currently reachable.

The important Grafana concept is:

```text
Query
  ↓
Prometheus
  ↓
Result
  ↓
Grafana visualization
```

---

## Query 2 – CPU

The document gives:

```promql
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

This gives us the rate of idle CPU time over the last five minutes.

Don't worry about deeply explaining the PromQL again here—we already covered PromQL.

Our focus in this section is:

> Grafana sends this PromQL query to Prometheus and displays the returned data.

---

## Query 3 – All Metrics

The document also gives:

```promql
{__name__=~".+"}
```

This can be used to discover metrics.

But the document explicitly gives a warning:

> **This can be slow on large clusters.**

So mention that to students.

For our small K3s lab, it's okay as a demonstration.

---

# Final Mental Model

At the end of this section, draw this:

```text
                 GRAFANA
                    │
             ┌──────┴──────┐
             │              │
        Dashboard        Explore
             │              │
             └──────┬───────┘
                    │
                  Query
                    │
                    ▼
             Data Source
              Prometheus
                    │
                    ▼
              Prometheus
                    │
                    ▼
               Query Result
                    │
                    ▼
                 Grafana
                    │
                    ▼
             Graph / Gauge /
             Table / Stat
```

## Live Recap

**Q: What is a Data Source?**

→ A connection between Grafana and a backend containing data.

**Q: Is Prometheus mandatory for Grafana?**

→ No. Grafana supports many data sources.

**Q: What are we using in this class?**

→ Prometheus.

**Q: What does every Grafana panel contain?**

→ A query and visualization settings.

**Q: Why use provisioning?**

→ To configure data sources as code and avoid manual UI configuration.

**Q: Why is a fixed UID useful?**

→ It gives the data source a stable identity, helping dashboards remain portable across Grafana instances.

**Q: What is Explore used for?**

→ To test and investigate queries before building dashboards.

That completes **Topic 4 – Data Sources**. Next is **Topic 5 – Exploring the Data Source**, where we'll keep it short and practical, then move directly into building the first dashboard.
