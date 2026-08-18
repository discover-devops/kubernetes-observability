# PromQL — Part 2: Querying & Functions

This is the second part of the PromQL reference material. It continues directly from `01-PromQL-Masterclass-Fundamentals.md` and assumes the same lab environment (Prometheus, Grafana, Alertmanager, and the demo application) is already running.

---

## Table of Contents

6. [Selectors and Label Matchers](#6-selectors-and-label-matchers)
7. [Instant Vectors vs Range Vectors](#7-instant-vectors-vs-range-vectors)
8. [Rate Functions — rate(), irate(), increase()](#8-rate-functions--rate-irate-increase)
9. [Aggregation Operators](#9-aggregation-operators)
10. [Operators and Vector Matching](#10-operators-and-vector-matching)
11. [Histograms and Percentiles](#11-histograms-and-percentiles)
12. [Useful Functions and Time Modifiers](#12-useful-functions-and-time-modifiers)
13. [Common Questions](#13-common-questions)

---

## 6. Selectors and Label Matchers

### Context

A metric name alone often returns dozens of Time Series. Label matchers let you filter down to exactly the series you care about — this is the equivalent of a `WHERE` clause for metrics.

### Concept

There are four label matcher operators:

| Operator | Meaning | Example |
|---|---|---|
| `=` | Exact match | `status_code="200"` |
| `!=` | Not equal | `status_code!="200"` |
| `=~` | Regex match | `status_code=~"2.."` |
| `!~` | Regex non-match | `status_code!~"2.."` |

Matchers are combined inside curly braces `{}` after the metric name, separated by commas (which act as AND).

### Lab

Only successful requests to the fast endpoint:

```promql
demo_http_requests_total{exported_endpoint="fast", status_code="200"}
```

Any request that is **not** a 2xx response:

```promql
demo_http_requests_total{status_code!~"2.."}
```

Every 5xx server error, regardless of endpoint:

```promql
demo_http_requests_total{status_code=~"5.."}
```

---

## 7. Instant Vectors vs Range Vectors

### Context

Some PromQL functions need a single current value, while others need a window of history to calculate a rate or trend. Knowing which type of vector a query produces determines which functions can legally be applied to it.

### Concept

**Instant vector** — one value per Time Series, at a single point in time.

```promql
demo_http_requests_total
```

**Range vector** — a window of historical samples per Time Series, produced by adding a time range in square brackets.

```promql
demo_http_requests_total[5m]
```

A range vector cannot be graphed directly — it exists to feed into functions like `rate()`, `increase()`, or `avg_over_time()`, which convert it back into a usable instant vector.

### Lab

Run this directly — it will return a graphable value:

```promql
demo_http_requests_total
```

Run this — Prometheus will refuse to graph it directly, because it is raw range data, not a single value:

```promql
demo_http_requests_total[5m]
```

Now wrap it in a function so it becomes graphable again:

```promql
rate(demo_http_requests_total[5m])
```

---

## 8. Rate Functions — `rate()`, `irate()`, `increase()`

### Context

Counters only ever go up, so their raw value (like "8,42,193 total requests") is not useful on its own. What matters is the *speed* at which they are increasing — requests per second, errors per second, and so on. This is what rate functions calculate.

### Concept

| Function | Calculates | Best for |
|---|---|---|
| `rate()` | Average per-second rate over the given time window | Smooth trends, dashboards, alerting |
| `irate()` | Per-second rate using only the last two data points | Fast-moving, spiky graphs |
| `increase()` | Total increase over the given time window (not per-second) | "How many requests happened in the last 5 minutes" |

**Why does `rate()` require a range like `[5m]`?**

`rate()` needs historical samples to calculate a rate — a single instant value has no "speed" on its own. `[5m]` tells Prometheus to look at the last five minutes of samples before calculating requests per second.

### Lab

Requests per second, averaged over the last 5 minutes:

```promql
rate(demo_http_requests_total[5m])
```

Total number of requests in the last 5 minutes:

```promql
increase(demo_http_requests_total[5m])
```

Fast-reacting rate using only the two most recent points:

```promql
irate(demo_http_requests_total[5m])
```

---

## 9. Aggregation Operators

### Context

A single query often returns many Time Series — one per endpoint, per status code, per pod. Aggregation operators combine them into a smaller, more meaningful set, the same way `GROUP BY` and `SUM` work in SQL.

### Concept

| Operator | Purpose |
|---|---|
| `sum()` | Add values together |
| `avg()` | Average across series |
| `max()` / `min()` | Highest / lowest value across series |
| `count()` | Number of Time Series |
| `by (label)` | Group results by a specific label |
| `without (label)` | Group by everything except the given label |

### Lab

Total request rate across all endpoints, combined into one number:

```promql
sum(rate(demo_http_requests_total[5m]))
```

Request rate broken down per endpoint:

```promql
sum(rate(demo_http_requests_total[5m])) by (exported_endpoint)
```

Number of distinct Time Series currently reporting:

```promql
count(demo_http_requests_total)
```

---

## 10. Operators and Vector Matching

### Context

Dividing one metric by another (for example, calculating an error percentage) sometimes fails or produces unexpected empty results. This happens because Prometheus tries to match Time Series **by their labels**, not just by their metric name — and this section explains how to control that matching.

### Concept

**Calculating an error percentage**

```
Failed = Total − Success
```

```promql
(
  sum(rate(demo_http_requests_total[5m]))
  -
  sum(rate(demo_http_requests_total{status_code=~"2.."}[5m]))
)
/
sum(rate(demo_http_requests_total[5m]))
* 100
```

**An important caveat:** this formula treats *anything that isn't a 2xx response* as a failure — including `404` and `301`, which are not always genuine application failures.

| Approach | When to use it |
|---|---|
| `Failed = Total − Success` | When "success" is clearly and narrowly defined, and everything else should count as a failure |
| `status_code=~"5.."` (explicit) | When you specifically want the server error rate — this is the more common choice on production SRE dashboards |

The explicit version, counting only server errors directly, is usually clearer:

```promql
sum(rate(demo_http_requests_total{status_code=~"5.."}[5m]))
```

**Why does dividing two queries sometimes break?**

```promql
rate(demo_http_requests_total{status_code="500"}[5m])
/
rate(demo_http_requests_total[5m])
```

This can produce no result, because the left side has a `status_code="500"` label and the right side has many different `status_code` values — Prometheus cannot automatically match series whose label sets don't line up.

**`ignoring()`** — exclude a specific label from the matching process:

```promql
rate(demo_http_requests_total{status_code="500"}[5m])
/
ignoring(status_code)
rate(demo_http_requests_total[5m])
```

**`on()`** — match using only the specified label(s):

```promql
... on(exported_endpoint)
```

**`group_left`** — used when the left side of the operation has more Time Series than the right side (a one-to-many relationship):

```promql
... on(exported_endpoint) group_left
```

### Lab

Run the broken version first to see the empty result, then apply `ignoring()` and compare:

```promql
rate(demo_http_requests_total{status_code="500"}[5m])
/
ignoring(status_code)
rate(demo_http_requests_total[5m])
```

---

## 11. Histograms and Percentiles

### Context

Averages hide outliers. If 95% of requests are fast but 5% are very slow, an average latency number won't show that. Histograms and percentiles solve this by showing the *distribution* of values, not just a single average.

### Concept

The bucket metric for request latency in this lab is:

```
demo_http_request_duration_seconds_bucket
```

Each bucket has a label `le` (meaning "less than or equal to") and a cumulative count:

```
le="0.05"
le="0.1"
le="0.25"
```

Instead of storing every individual request duration, Prometheus stores how many requests fell at or below each bucket boundary. This is far more storage-efficient than tracking every raw value, while still allowing percentile calculations.

To calculate an actual percentile (for example, the 95th percentile latency), wrap the bucket metric in `histogram_quantile()`:

```promql
histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket[5m])) by (le))
```

### Lab

View the raw buckets:

```promql
demo_http_request_duration_seconds_bucket
```

Calculate the 95th percentile latency across all requests:

```promql
histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket[5m])) by (le))
```

Calculate it per endpoint instead:

```promql
histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket[5m])) by (le, exported_endpoint))
```

---

## 12. Useful Functions and Time Modifiers

### Context

Beyond rate and aggregation, a few additional functions come up regularly once you start building real dashboards and alerts.

### Concept

| Function / Modifier | Purpose |
|---|---|
| `avg_over_time(metric[5m])` | Average of a Gauge's value over a time window |
| `max_over_time(metric[5m])` | Highest value of a Gauge over a time window |
| `min_over_time(metric[5m])` | Lowest value of a Gauge over a time window |
| `metric offset 1h` | Value of the metric exactly one hour ago |
| `predict_linear(metric[1h], 3600)` | Predicts the value 1 hour into the future based on the last hour's trend |

### Lab

Average queue depth over the last 5 minutes:

```promql
avg_over_time(demo_queue_depth[5m])
```

Compare the current request rate to the same metric one hour ago:

```promql
rate(demo_http_requests_total[5m]) offset 1h
```

---

## 13. Common Questions

**Q: Are endpoints the same thing as URLs?**

Yes. In this lab, an "endpoint" refers to a specific URL path the application serves, such as `/api/fast`, `/api/slow`, `/metrics`, or `/healthz`. Each endpoint has a distinct purpose — some are meant for users, some for Prometheus, and some for Kubernetes health checks.

**Q: Where is a metric like `demo_queue_depth` created, and who creates it?**

It is created entirely inside the application's own code, using the Prometheus client library — Prometheus never creates metrics itself. In this lab, `demo_queue_depth` is defined as a Gauge and updated by a background thread every two seconds, simulating a queue that doesn't actually exist. See Part 1, Section 2 for the full code walkthrough.

**Q: Why does a single metric query return multiple rows?**

Because each unique combination of label values forms a separate Time Series, even though they share the same metric name.

| Endpoint | Status | Series |
|---|---|---|
| fast | 200 | A |
| slow | 200 | B |
| work | 500 | C |

These three rows are three distinct Time Series, not three instances of the same one.

**Q: Why does `rate()` need a time range like `[5m]`?**

Because `rate()` calculates a per-second speed, and speed can only be calculated from a window of historical samples — not from a single point-in-time value. `[5m]` tells Prometheus how far back to look before calculating that rate.

**Q: Should a `404` count as a failure when calculating an error rate?**

It depends on how your team defines a Service Level Indicator (SLI). If "success" is defined narrowly as only 2xx responses, then anything else — including `404` and `301` — is technically counted as a failure by the `Total − Success` formula. Most production dashboards instead filter explicitly for `5xx` status codes, since those represent genuine server-side errors rather than client requests for resources that don't exist.

---

*This completes the PromQL Masterclass. See `03-PromQL-Cheat-Sheet.md` for a condensed quick-reference version of every query in this document.*
