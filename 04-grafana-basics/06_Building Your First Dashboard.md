# Topic 6 – Building Your First Dashboard

---

## Context

We've already verified that:

* Grafana is running.
* Prometheus is connected.
* PromQL queries work in Explore.

Now we want to turn those queries into a **reusable monitoring dashboard**.

The document defines a dashboard as:

> A collection of panels arranged on a grid.

So our goal is to build:

```text
Node Overview
├── CPU Usage
├── Memory Usage
├── Running Pods
├── Pod Restarts
└── HTTP Error Rate
```

Each of these will be a separate **Panel**.

---

# Step 1 – Create the Dashboard

From the Grafana UI:

```text
Left Sidebar
    ↓
Dashboards
    ↓
New Dashboard
    ↓
Add visualization
```

Grafana will ask us to select a data source.

Choose:

```text
Prometheus
```

Now we're ready to create our first panel.

---

# Panel 1 – Cluster CPU Usage

### Context

The first thing we want to monitor is **CPU utilization**.

We don't want idle CPU.

We want to know:

> "What percentage of CPU is actually being used?"

The document gives us this PromQL query.

### Query

```promql
100 - (
  avg by (instance) (
    rate(node_cpu_seconds_total{mode="idle"}[5m])
  ) * 100
)
```

Let's understand the logic.

First:

```promql
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

gives us the rate of **idle CPU time**.

Then:

```promql
* 100
```

converts it into a percentage.

Then:

```promql
100 - idle_percentage
```

gives us:

```text
CPU Usage %
```

So the basic relationship is:

```text
CPU Usage = 100 - CPU Idle
```

---

## Panel Configuration

Now configure the panel exactly as the document specifies.

### Visualization

```text
Time series
```

Why?

Because CPU usage changes over time, and a time-series graph allows us to see that trend.

### Title

```text
CPU Usage %
```

### Unit

```text
Percent (0-100)
```

This tells Grafana that the values represent percentages.

---

## Thresholds

The document specifies:

```text
80% → Warning
90% → Critical
```

So conceptually:

```text
CPU
│
│       Critical
│       90%
│──────────────
│
│       Warning
│       80%
│──────────────
│
└──────────────── Time
```

The purpose of thresholds is to make abnormal values visually obvious.

---

## Legend

The document says:

```text
Show as table
Last / Min / Max
```

This means the legend can show useful summary values alongside the graph.

For example:

```text
Instance     Last    Min    Max
node-1       62%     30%    91%
```

---

# Panel 1 Recap

Our first panel is:

```text
CPU Usage %
    ↓
Time Series
    ↓
PromQL
    ↓
Prometheus
```

And we have configured:

* Time Series
* Percent unit
* 80% warning
* 90% critical
* Legend with Last/Min/Max

---

# Panel 2 – Memory Usage

Now we want to monitor memory utilization.

## Query

The document gives:

```promql
(
  node_memory_MemTotal_bytes
  -
  node_memory_MemAvailable_bytes
)
/
node_memory_MemTotal_bytes
* 100
```

Let's understand it.

Total memory:

```promql
node_memory_MemTotal_bytes
```

Available memory:

```promql
node_memory_MemAvailable_bytes
```

Used memory is calculated as:

```text
Total Memory - Available Memory
```

Then:

```text
Used Memory
────────────── × 100
Total Memory
```

gives us:

```text
Memory Usage %
```

---

## Panel Configuration

### Visualization

```text
Gauge
```

Why a Gauge?

Because we're interested in the **current memory utilization level**.

### Title

```text
Memory Usage %
```

### Unit

```text
Percent (0-100)
```

### Range

```text
Min: 0
Max: 100
```

---

## Thresholds

The document specifies:

```text
70% → Yellow
85% → Red
```

So the gauge gives us an immediate indication of memory pressure.

Conceptually:

```text
0% ───────── 70% ───────── 85% ───── 100%
              │              │
            Warning        Critical
```

---

# Panel 2 Recap

We now have:

```text
Memory Usage %
      ↓
    Gauge
      ↓
Prometheus
```

The important difference from Panel 1 is the visualization.

CPU:

```text
Time Series
```

Memory:

```text
Gauge
```

We're using the visualization that makes sense for the type of information we're displaying.

---

# Panel 3 – Running Pods per Namespace

Now let's move from node-level metrics to Kubernetes workload information.

We want to answer:

> "How many Pods are currently running in each namespace?"

## Query

The document gives:

```promql
count by (namespace) (
  kube_pod_info{phase="Running"}
)
```

Let's break it down.

First:

```promql
kube_pod_info{phase="Running"}
```

selects Pods whose phase is `Running`.

Then:

```promql
count by (namespace)
```

counts those Pods separately for each namespace.

So the result could conceptually look like:

```text
Namespace       Running Pods
----------------------------
default              5
monitoring           8
kube-system          7
```

---

## Panel Configuration

### Visualization

```text
Bar chart
```

### Title

```text
Running Pods by Namespace
```

### X-axis

```text
namespace
```

### Legend

```text
Hidden
```

Why a Bar Chart?

Because we're comparing values across categories:

```text
default       █████
monitoring    ████████
kube-system   ███████
```

The categories are namespaces.

---

# Panel 3 Recap

We have now introduced another visualization:

```text
CPU      → Time Series
Memory   → Gauge
Pods     → Bar Chart
```

This is an important dashboard design principle:

> Choose the visualization based on what you want the user to understand from the data.

---

# Panel 4 – Pod Restart Count

Now we want to monitor Pod/container restarts.

The question we're asking is:

> "How many container restarts happened during the last hour?"

## Query

```promql
sum(
  increase(
    kube_pod_container_status_restarts_total[1h]
  )
)
```

The important part is:

```promql
[1h]
```

We're looking at the **last one hour**.

And `increase()` calculates how much the restart counter increased during that period.

Then:

```promql
sum(...)
```

gives us the total.

---

## Panel Configuration

### Visualization

```text
Stat
```

### Title

```text
Pod Restarts (Last 1h)
```

### Color Mode

```text
Background
```

### Thresholds

```text
0 → Green
1 → Yellow
5 → Red
```

Conceptually:

```text
0 restarts
   ↓
Healthy

1+ restart
   ↓
Warning

5+ restarts
   ↓
Critical
```

The Stat panel is appropriate here because we're primarily interested in **one current number**.

---

# Panel 5 – HTTP Error Rate

This is our final panel.

Now we're moving from Kubernetes infrastructure metrics to an application-level metric.

We want to answer:

> "What percentage of HTTP requests are returning 5xx errors?"

## Query

The document gives:

```promql
sum(
  rate(http_requests_total{status=~"5.."}[5m])
) by (service)
/
sum(
  rate(http_requests_total[5m])
) by (service)
* 100
```

Let's understand the logic.

### Numerator

```promql
http_requests_total{status=~"5.."}
```

The regular expression:

```text
5..
```

matches HTTP status codes beginning with `5`.

Examples:

```text
500
501
502
503
504
```

So the numerator represents the rate of HTTP 5xx errors.

### Denominator

```promql
http_requests_total
```

represents the total HTTP request rate.

Therefore:

```text
5xx Error Rate
=
5xx Requests
─────────────── × 100
Total Requests
```

And:

```promql
by (service)
```

means we calculate the error rate separately for each service.

---

# Panel Configuration

### Visualization

```text
Time series
```

### Title

```text
HTTP 5xx Error Rate %
```

### Unit

```text
Percent (0-100)
```

### Fill opacity

```text
10
```

### Line width

```text
2
```

The result lets us observe how application error rates change over time.

---

# Our Dashboard So Far

We now have five panels:

| Panel                     | Visualization |
| ------------------------- | ------------- |
| CPU Usage %               | Time Series   |
| Memory Usage %            | Gauge         |
| Running Pods by Namespace | Bar Chart     |
| Pod Restarts (Last 1h)    | Stat          |
| HTTP 5xx Error Rate %     | Time Series   |

And notice how each panel answers a different operational question:

```text
CPU
→ Are nodes under CPU pressure?

Memory
→ Are nodes running out of memory?

Pods
→ How many workloads are running?

Restarts
→ Are workloads restarting?

HTTP Errors
→ Are applications returning errors?
```

That's the purpose of the dashboard.

---

# Important
.

At each panel, three-step relationship:

```text
1. PromQL Query
       ↓
2. Data returned by Prometheus
       ↓
3. Visualization in Grafana
```

For example:

```text
CPU Query
   ↓
CPU data
   ↓
Time Series
```

while:

```text
Memory Query
   ↓
Memory %
   ↓
Gauge
```

and:

```text
Pod Query
   ↓
Pods by namespace
   ↓
Bar Chart
```

This connects today's entire session together.

---

# Recap

**Q: What is a panel?**

→ A single visualization on a dashboard.

**Q: What does every panel need?**

→ A query, visualization type, and display settings.

**Q: Where does the data come from?**

→ Prometheus, through the Grafana data source.

**Q: Why is CPU a Time Series?**

→ Because we want to see CPU usage over time.

**Q: Why is memory a Gauge?**

→ Because we want an immediate view of current utilization.

**Q: Why is Pod count a Bar Chart?**

→ Because we're comparing values across namespaces.

**Q: Why is Pod restart count a Stat?**

→ Because we're primarily interested in the current total number.

---

## One Important Note Before We Save

The HTTP error-rate panel depends on the metric:

```promql
http_requests_total
```

being available in Prometheus.

Similarly, the Kubernetes panels depend on metrics such as:

```text
kube_pod_info
kube_pod_container_status_restarts_total
```
