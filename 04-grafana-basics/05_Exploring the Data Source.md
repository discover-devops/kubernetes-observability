
# Topic 5 – Exploring the Data Source

## Context

We have now connected Grafana to Prometheus.

Before we start creating dashboards, we need a place where we can **test our queries**.

That's what **Explore** is for.

The important distinction is:

> **Explore is where we investigate and test data. A Dashboard is where we build a reusable visualization.**

So our workflow is:

```text
Prometheus
    ↓
Explore
    ↓
Test the query
    ↓
Understand the result
    ↓
Create Dashboard Panel
```

---

# Concept 1 – What is Explore?

**Explore** is Grafana's interactive area for querying a data source.

Instead of immediately creating a dashboard panel, we can first ask:

> "Does my query return the data I expect?"

This is useful when we're developing or troubleshooting queries.

For our class, we'll use **Prometheus** as the data source.

---

# Lab 1 – Open Explore

From the Grafana UI:

```text
Left Sidebar
     ↓
Explore
     ↓
Select Data Source
     ↓
Prometheus
```

Now Grafana gives us an interface where we can enter PromQL queries.

---

# Lab 2 – Run `up`

Start with the simplest query:

```promql
up
```

Click **Run query**.

We should get results from Prometheus.

The important thing isn't the graph itself.

The important thing is understanding the flow:

```text
You write PromQL
       ↓
Grafana
       ↓
Prometheus Data Source
       ↓
Prometheus
       ↓
Result
       ↓
Grafana displays it
```

This proves that our Grafana → Prometheus connection is working.

---

# Concept 2 – Why Start with `up`?

`up` is a very useful first query because it is simple.

We don't have to worry about:

* complicated PromQL
* aggregations
* functions
* multiple labels

We're simply checking whether Prometheus has data available for its targets.

So when troubleshooting a new Grafana/Prometheus connection, a simple query like:

```promql
up
```

is a good starting point.

---

# Lab 3 – CPU Query

Now let's try the CPU query:

```promql
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

This asks Prometheus for the rate of idle CPU time over the last five minutes.

Grafana sends this query to Prometheus and displays the returned time-series data.

Again, notice:

> **Grafana is not executing PromQL itself. Prometheus executes the PromQL query.**

Grafana is the interface through which we send the query and visualize the result.

---

# Lab 4 – Discover Available Metrics

The document gives another query:

```promql
{__name__=~".+"}
```

This can be used to see available metrics.

But there is an important warning in the document:

> **This can be slow on large clusters.**

Why?

Because we're effectively asking Prometheus to return a very broad set of metrics.

So for our small lab environment, we can demonstrate it, but students should understand:

```text
Broad query
    ↓
Potentially large result
    ↓
More work for Prometheus
    ↓
Can become slow on large environments
```

---

# Concept 3 – Explore vs Dashboard

This distinction is worth emphasizing before we move on.

### Explore

Used primarily for:

* Testing queries
* Investigating data
* Troubleshooting
* Experimenting with PromQL

### Dashboard

Used primarily for:

* Reusable visualizations
* Operational monitoring
* Multiple panels
* Sharing a monitoring view

So:

```text
Explore
   ↓
"Let me test this query."

Dashboard
   ↓
"Let me save this visualization for continuous use."
```

---

# Quick Live Exercise

Ask students to do these three queries themselves:

### Query 1

```promql
up
```

### Query 2

```promql
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

### Query 3

```promql
{__name__=~".+"}
```

For Query 3, remind them:

> "Don't use this kind of broad query repeatedly on a large production Prometheus."

---

# Final Recap

Ask students:

**Q: What is Explore?**

→ An interactive place to query and investigate a data source.

**Q: Who executes the PromQL query?**

→ Prometheus.

**Q: What does Grafana do with the result?**

→ It visualizes the result.

**Q: Why use Explore before creating a dashboard?**

→ To verify that the query returns the expected data.

**Q: What's the difference between Explore and Dashboard?**

→ Explore is primarily for investigation and testing; dashboards are for reusable visualization.

---

## Transition to the Main Lab

Now we have completed the entire data flow:

```text
Prometheus
    ↓
Data Source
    ↓
Grafana
    ↓
Explore
    ↓
PromQL Query
    ↓
Result
```

Now we are ready for the most hands-on part:

# Topic 6 – Building Your First Dashboard

We'll create the **Node Overview** dashboard from the document and build the five panels one by one:

1. CPU Usage — Time Series
2. Memory Usage — Gauge
3. Running Pods by Namespace — Bar Chart
4. Pod Restarts — Stat
5. HTTP 5xx Error Rate — Time Series

We'll also cover the exact **units, thresholds, legends, titles, and display settings** .
