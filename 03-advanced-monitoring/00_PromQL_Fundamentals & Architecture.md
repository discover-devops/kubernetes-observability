# PromQL — Part 1: Fundamentals & Architecture

This document is the reference material for the PromQL Masterclass. It covers how Prometheus collects metrics from a Kubernetes application, how those metrics are structured, and how to start querying them.

The lab environment referenced in this document is a Kubernetes monitoring stack running on a single EC2 node, with Prometheus, Grafana, Alertmanager, and a demo application already deployed.

---

## Table of Contents

**Part 1 — Fundamentals & Architecture** *(this file)*
1. [Lab Environment Recap](#1-lab-environment-recap)
2. [How Metrics Flow From an Application to Prometheus](#2-how-metrics-flow-from-an-application-to-prometheus)
3. [Accessing Prometheus Over the Internet (NodePort Networking)](#3-accessing-prometheus-over-the-internet-nodeport-networking)
4. [The Prometheus Data Model](#4-the-prometheus-data-model)
5. [The Four Metric Types](#5-the-four-metric-types)

**Part 2 — Querying & Functions** *(separate file: `02-PromQL-Masterclass-Querying-and-Functions.md`)*
6. Selectors and Label Matchers
7. Instant Vectors vs Range Vectors
8. Rate Functions — `rate()`, `irate()`, `increase()`
9. Aggregation Operators
10. Operators and Vector Matching
11. Histograms and Percentiles
12. Useful Functions and Time Modifiers
13. Common Questions

**Quick Reference** *(separate file: `03-PromQL-Cheat-Sheet.md`)*

---

## 1. Lab Environment Recap

### Context

Before writing any PromQL query, it helps to know what is actually running in the cluster and where each piece of data comes from. A query is only meaningful once you understand the system generating the numbers behind it.

### Concept

The lab environment is a complete Kubernetes monitoring stack. Each component has a specific job:

| Component | Purpose |
|---|---|
| k3s | Single-node Kubernetes cluster |
| Prometheus | Collects and stores metrics |
| Grafana | Visualizes metrics |
| Alertmanager | Handles alerts |
| Prometheus Operator | Manages the Prometheus deployment and configuration |
| ServiceMonitor | Tells Prometheus which applications to scrape |
| Demo App | A sample application that generates metrics |
| Load Generator | Sends continuous traffic to the demo app so metrics keep changing |

**Running services and ports:**

| Service | NodePort |
|---|---|
| Grafana | 30080 |
| Prometheus | 30090 |
| Alertmanager | 30093 |

Each of these is reachable at:

```
http://<PUBLIC-IP>:30080   # Grafana
http://<PUBLIC-IP>:30090   # Prometheus
http://<PUBLIC-IP>:30093   # Alertmanager
```

### Lab

Verify the environment is healthy before running any queries.

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl get nodes
kubectl get pods -n monitoring
kubectl get pods -n promql-lab
kubectl get servicemonitor -n monitoring
```

All pods should be in `Running` state, and the `demo-app` ServiceMonitor should be listed under the `monitoring` namespace.

---

## 2. How Metrics Flow From an Application to Prometheus

### Context

A common misconception is that Prometheus somehow "creates" or "knows about" application metrics automatically. It does not. Understanding who creates a metric — versus who collects it — is the foundation for everything else in this course.

### Concept

**The application creates the metric. Prometheus only collects it.**

The flow works like this:

1. The application generates metrics inside its own code (using a Prometheus client library).
2. Those metrics are exposed on an HTTP endpoint, typically `/metrics`.
3. A **ServiceMonitor** object tells Prometheus where that endpoint lives.
4. Prometheus scrapes (sends an HTTP GET request to) that endpoint on a fixed interval — in this lab, every 15 seconds.
5. Each scraped value is stored as a **Time Series**.
6. Grafana reads those Time Series to draw dashboards.

The demo application exposes multiple endpoints, each with a different purpose:

| Endpoint | Purpose |
|---|---|
| `/api/fast` | Fast API — used to generate low-latency traffic |
| `/api/slow` | Slow API — used to generate high-latency traffic |
| `/api/work` | Work API — used to simulate CPU-heavy work |
| `/metrics` | Exposes metrics in Prometheus format |
| `/healthz` | Health check used by Kubernetes |

These endpoints are just URLs served by the application. `/api/*` is meant for users, `/metrics` is meant for Prometheus, and `/healthz` is meant for Kubernetes.

**Important:** Prometheus does not ask an application for JSON. It asks for plain text in a specific format called the **Prometheus Exposition Format**.

### Lab

Port-forward the demo application and look at its raw metrics page directly.

```bash
kubectl port-forward svc/demo-app 8080:8080 -n promql-lab
```

Open in a browser:

```
http://localhost:8080/metrics
```

You will see hundreds of plain-text lines. One example line looks like this:

```
demo_http_requests_total{exported_endpoint="fast",method="GET",status_code="200"} 842
```

This is the raw, unprocessed data that Prometheus scrapes.

Next, check how Prometheus knows this endpoint exists:

```bash
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor demo-app -n monitoring
```

Look at the output for the namespace, the service it targets, the `/metrics` path, and the scrape interval (`15s`). A ServiceMonitor works like an address book entry — it tells Prometheus exactly where to find the metrics.

Finally, confirm the scrape is actually happening:

```
http://<PUBLIC-IP>:30090/targets
```

The `demo-app` target should show as **UP**, along with the last scrape time and interval.

**Where do specific metrics come from?**

| Metric | Created by |
|---|---|
| `demo_http_requests_total` | The application code |
| `demo_queue_depth` | The application code |
| `demo_http_request_duration_seconds_bucket` | The application code |
| `demo_payload_bytes_sum` | The application code |
| `pod`, `namespace`, `service` labels | Kubernetes / Prometheus (added automatically) |
| `node_cpu_seconds_total` | Node Exporter |
| `kube_pod_info` | kube-state-metrics |

The application is responsible for business-level metrics. Kubernetes contributes context labels. Prometheus is responsible for collecting and storing everything as Time Series.

**Where does a value like `demo_queue_depth` actually come from?**

In the demo app's code, it is defined as a Gauge:

```python
QUEUE = Gauge(
    "demo_queue_depth",
    "Simulated background queue depth.",
    registry=registry,
)
```

A background thread updates it continuously:

```python
def _queue_wiggler():
    depth = 5.0
    while True:
        depth = max(0.0, depth + random.uniform(-1.0, 1.2))
        QUEUE.set(depth)
        time.sleep(2)
```

This is a **simulated** queue — there is no real message broker (like RabbitMQ or Kafka) behind it. The value is intentionally randomized every two seconds so you can watch a Gauge move up and down in real time. Run the query `demo_queue_depth` in Prometheus and refresh it a couple of times to see this happen.

---

## 3. Accessing Prometheus Over the Internet (NodePort Networking)

### Context

Opening `http://<PUBLIC-IP>:30090` in a browser works, but it is worth understanding *why* it works. This connects Kubernetes Services, AWS networking, and `kube-proxy` into a single, complete picture — knowledge that is directly useful when you deploy your own applications later.

### Concept

A request to `<PUBLIC-IP>:30090` passes through five layers before it reaches the Prometheus process:

**Layer 1 — Browser sends a request**
The browser sends a request to the EC2 instance's public IP on port `30090`.

**Layer 2 — AWS Security Group**
The Security Group must explicitly allow inbound traffic on port `30090` (along with `30080` and `30093`). Without this rule, the request never reaches the server at all.

**Layer 3 — EC2 receives the packet**
The packet arrives at the Ubuntu server. Prometheus itself is **not** listening directly on port `30090` — it is running inside a Kubernetes Pod.

**Layer 4 — Kubernetes NodePort**
Run:

```bash
kubectl get svc -n monitoring
```

Output includes something like:

```
NAME                              TYPE       PORT(S)
kube-prometheus-stack-prometheus  NodePort   9090:30090/TCP
```

| Number | Meaning |
|---|---|
| `9090` | Prometheus container port |
| `30090` | NodePort exposed on the Kubernetes node |

Traffic arriving on the node's port `30090` is forwarded to the Prometheus Service on port `9090`.

**Layer 5 — kube-proxy forwards the traffic**
`kube-proxy` watches for traffic on `30090`, forwards it to the Prometheus Service, and the Service forwards it to the Prometheus Pod.

**NodePort vs. `kubectl port-forward`**

These solve different problems:

| | NodePort | `kubectl port-forward` |
|---|---|---|
| Nature | Opens a real, permanent port on every node | Creates a temporary tunnel from your local machine |
| Accessible from | Anyone who can reach the node IP (subject to Security Group rules) | Only your local machine, only while the command is running |
| Typical use | Exposing a UI like Prometheus or Grafana | Quick, one-off debugging |

**NodePort vs. ClusterIP**

```bash
kubectl get svc -n promql-lab
```

The `demo-app` Service is of type `ClusterIP`, not `NodePort`:

| | NodePort | ClusterIP |
|---|---|---|
| Accessible from | The internet (via node IP + Security Group) | Internal to the cluster only |
| Opens a node port | Yes | No |
| Used here for | The Prometheus, Grafana, and Alertmanager UIs | The demo application |

This is why the demo app is not reachable directly from a browser the way Prometheus is — it was never meant to be public. It is only meant to be scraped by Prometheus from inside the cluster.

### Lab

```bash
kubectl get svc -n monitoring
kubectl get svc -n promql-lab
```

Compare the `TYPE` column between the two outputs and confirm which services are `NodePort` and which are `ClusterIP`.

---

## 4. The Prometheus Data Model

### Context

Every PromQL query operates on the same underlying structure. Understanding this structure makes every query afterward far easier to reason about — instead of memorizing syntax, you'll be able to predict what a query does.

### Concept

Prometheus stores everything as a **Time Series**. A Time Series is defined as:

```
Metric + Labels = One Time Series
```

Each scrape adds a new **sample** — a timestamp and a value — to that series:

| Timestamp | Value |
|---|---|
| 10:00 | 120 |
| 10:15 | 125 |
| 10:30 | 131 |
| 10:45 | 138 |

**Breaking down a metric name**

Take `demo_http_requests_total`:

| Part | Meaning |
|---|---|
| `demo` | The application it belongs to |
| `http` | The subsystem (HTTP traffic) |
| `requests` | What is being measured (request count) |
| `total` | Signals this is a Counter |

**Labels**

Labels attach extra dimensions to a metric and uniquely identify a specific Time Series. Common labels in this lab include:

- `exported_endpoint`
- `method`
- `status_code`
- `pod`
- `namespace`
- `service`

**Changing even one label value creates a brand-new, separate Time Series.**

| Endpoint | Status | Series |
|---|---|---|
| fast | 200 | A |
| slow | 200 | B |
| work | 500 | C |

These are three distinct Time Series, even though they share the same metric name.

### Lab

Run this query in the Prometheus UI (`http://<PUBLIC-IP>:30090`):

```promql
demo_http_requests_total
```

Switch to **Table View**. You will see multiple rows, each with a different label combination, such as:

```
demo_http_requests_total{
  exported_endpoint="fast",
  method="GET",
  status_code="200"
}
```

Now count how many distinct Time Series exist for this metric:

```promql
count(demo_http_requests_total)
```

Note that this counts the number of Time Series — **not** the number of requests.

---

## 5. The Four Metric Types

### Context

Prometheus supports exactly four metric types. Each one behaves differently and is queried differently, so recognizing which type you're looking at is the first step before writing any query against it.

### Concept

| Type | Example in this lab | Typical function used with it |
|---|---|---|
| Counter | `demo_http_requests_total` | `rate()` |
| Gauge | `demo_queue_depth` | Direct read |
| Histogram | `demo_http_request_duration_seconds_bucket` | `histogram_quantile()` |
| Summary | Payload statistics | `_sum` and `_count` |

**Counter**

A Counter only ever increases (it resets to zero only if the process restarts). It is used for things that accumulate, such as:

- HTTP requests
- Login attempts
- Orders processed

Analogy: a car's **odometer** — it only goes up.

**Gauge**

A Gauge can go up or down. It represents a value at a point in time, such as:

- Queue depth
- Memory usage
- Number of active connections

Analogy: a **fuel gauge** — it moves in both directions depending on current state.

**Histogram**

A Histogram stores observations (like request durations) inside predefined buckets, so you can later calculate percentiles and averages without storing every individual value.

**Summary**

A Summary provides pre-calculated statistics on the client side, typically exposed as a running `_sum` and `_count`, which together let you calculate an average.

### Lab

**Counter:**
```promql
demo_http_requests_total
```
This value only increases over time.

**Gauge:**
```promql
demo_queue_depth
```
Refresh the query panel a few times. Notice the value goes up and down — this is the background thread in the application updating it every two seconds.

**Histogram:**
```promql
demo_http_request_duration_seconds_bucket
```
This returns multiple series, one per bucket boundary (covered in detail in Part 2, Section 11).

---

*Continue to Part 2 — `02-PromQL-Masterclass-Querying-and-Functions.md` — for selectors, vectors, rate functions, aggregations, vector matching, histograms, time functions, and common questions.*
