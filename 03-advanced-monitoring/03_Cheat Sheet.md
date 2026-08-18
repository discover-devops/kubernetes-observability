# PromQL Cheat Sheet

Quick reference for every query used across the PromQL Masterclass (`01` and `02`). Keep this open in a separate tab while practicing.

## Environment

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl get nodes
kubectl get pods -n monitoring
kubectl get pods -n promql-lab
kubectl get svc -n monitoring
kubectl get svc -n promql-lab
kubectl get servicemonitor -n monitoring
```

| Service | Port |
|---|---|
| Grafana | 30080 |
| Prometheus | 30090 |
| Alertmanager | 30093 |

## Basic Queries

```promql
demo_http_requests_total                          # Counter — all requests
demo_queue_depth                                   # Gauge — current queue depth
demo_http_request_duration_seconds_bucket          # Histogram buckets
count(demo_http_requests_total)                    # Number of Time Series
```

## Selectors

```promql
demo_http_requests_total{status_code="200"}
demo_http_requests_total{status_code!="200"}
demo_http_requests_total{status_code=~"2.."}
demo_http_requests_total{status_code!~"2.."}
```

## Range Vectors & Rate Functions

```promql
demo_http_requests_total[5m]                       # Range vector (not graphable directly)
rate(demo_http_requests_total[5m])                  # Per-second rate, smoothed
irate(demo_http_requests_total[5m])                 # Per-second rate, last 2 points
increase(demo_http_requests_total[5m])              # Total increase over 5 minutes
```

## Aggregation

```promql
sum(rate(demo_http_requests_total[5m]))
sum(rate(demo_http_requests_total[5m])) by (exported_endpoint)
avg(rate(demo_http_requests_total[5m]))
max(demo_queue_depth)
```

## Error Rate

```promql
# Failed = Total - Success (treats all non-2xx as failure)
(
  sum(rate(demo_http_requests_total[5m]))
  -
  sum(rate(demo_http_requests_total{status_code=~"2.."}[5m]))
)
/
sum(rate(demo_http_requests_total[5m]))
* 100

# Explicit 5xx server error rate (preferred for production dashboards)
sum(rate(demo_http_requests_total{status_code=~"5.."}[5m]))
```

## Vector Matching

```promql
# ignoring() - exclude a label from matching
rate(demo_http_requests_total{status_code="500"}[5m])
/
ignoring(status_code)
rate(demo_http_requests_total[5m])

# on() - match using only the given label
... on(exported_endpoint)

# group_left - one-to-many matching
... on(exported_endpoint) group_left
```

## Histograms & Percentiles

```promql
histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket[5m])) by (le))
histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket[5m])) by (le, exported_endpoint))
```

## Time Functions

```promql
avg_over_time(demo_queue_depth[5m])
max_over_time(demo_queue_depth[5m])
min_over_time(demo_queue_depth[5m])
rate(demo_http_requests_total[5m]) offset 1h
predict_linear(demo_queue_depth[1h], 3600)
```

## Metric Type Reference

| Type | Example | Behavior | Typical function |
|---|---|---|---|
| Counter | `demo_http_requests_total` | Only increases | `rate()` |
| Gauge | `demo_queue_depth` | Goes up and down | Direct read |
| Histogram | `demo_http_request_duration_seconds_bucket` | Bucketed observations | `histogram_quantile()` |
| Summary | Payload statistics | Pre-calculated stats | `_sum`, `_count` |
