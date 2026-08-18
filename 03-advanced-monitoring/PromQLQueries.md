PromQL Masterclass – From Zero to Production Queries

Learn how to think like an SRE using PromQL.

In the previous session we built a complete monitoring stack with Prometheus, Grafana, Alertmanager, and a Kubernetes application exposing metrics. This document focuses on the next step: understanding those metrics and writing production-ready PromQL queries.

Table of Contents

Lab Environment Recap

How Prometheus Collects Metrics

Prometheus Data Model

The Four Metric Types

Selectors and Label Matchers

Instant Vectors vs Range Vectors

Rate Functions (rate, irate, increase)

Aggregation Operators

Operators and Vector Matching

Histograms and Percentiles

Useful Functions and Time Modifiers

PromQL Cheat Sheet

Common Student Questions

1. Lab Environment Recap

The lab environment contains a complete Kubernetes monitoring stack.

Architecture
Components

Component

	

Purpose




k3s

	

Single-node Kubernetes cluster




Prometheus

	

Collects and stores metrics




Grafana

	

Visualizes metrics




Alertmanager

	

Handles alerts




Prometheus Operator

	

Manages Prometheus




ServiceMonitor

	

Discovers applications




Demo App

	

Generates sample metrics




Load Generator

	

Creates continuous traffic

Running Services

Service

	

Port




Grafana

	

30080




Prometheus

	

30090




Alertmanager

	

30093

Example URLs:

http://<PUBLIC-IP>:30080
http://<PUBLIC-IP>:30090
http://<PUBLIC-IP>:30093
Verify the Environment
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml


kubectl get nodes
kubectl get pods -n monitoring
kubectl get pods -n promql-lab
kubectl get servicemonitor -n monitoring
2. How Prometheus Collects Metrics

One of the most important concepts is understanding that Prometheus does not create application metrics.

The application creates metrics.

Prometheus only collects them.

Step-by-Step Flow

Application generates metrics.

Metrics appear on /metrics.

ServiceMonitor tells Prometheus where to scrape.

Prometheus scrapes every 15 seconds.

Metrics become Time Series.

Grafana reads them.

Where does /metrics come from?

The demo application exposes several endpoints.

Endpoint

	

Purpose




/api/fast

	

Fast API




/api/slow

	

Slow API




/api/work

	

Work API




/metrics

	

Prometheus metrics




/healthz

	

Health check

Notice:

Users access /api/*

Prometheus accesses /metrics

Kubernetes uses /healthz

Viewing Raw Metrics

Port-forward the application.

kubectl port-forward svc/demo-app 8080:8080 -n promql-lab

Open:

http://localhost:8080/metrics

Example output:

demo_http_requests_total{exported_endpoint="fast",status_code="200"} 842

This plain-text format is called the Prometheus Exposition Format.

3. The Prometheus Data Model

Prometheus stores Time Series.

A Time Series is simply:

Metric+Labels=OneTimeSeries

Every scrape adds another sample.

Timestamp

	

Value




10:00

	

120




10:15

	

125




10:30

	

131




10:45

	

138

First Query
demo_http_requests_total

Switch to Table View.

Example:

demo_http_requests_total{
exported_endpoint="fast",
method="GET",
status_code="200"
}
Breaking the Metric Name

Part

	

Meaning




demo

	

Application




http

	

HTTP traffic




requests

	

Request count




total

	

Counter

Understanding Labels

Labels uniquely identify Time Series.

Example labels:

exported_endpoint

method

status_code

pod

namespace

service

Changing even one label creates a new Time Series.

Example:

Endpoint

	

Status

	

Series




fast

	

200

	

A




slow

	

200

	

B




work

	

500

	

C

Count Existing Time Series
count(demo_http_requests_total)

This counts Time Series, not requests.

4. The Four Metric Types

Prometheus has four metric types.

Type

	

Example

	

Typical Function




Counter

	

Requests

	

rate()




Gauge

	

Queue depth

	

Direct read




Histogram

	

Latency

	

histogram_quantile()




Summary

	

Payload statistics

	

_sum and _count

Counter

A Counter only increases.

Query:

demo_http_requests_total

Examples:

HTTP requests

Login attempts

Orders processed

Analogy:

Car odometer.

Gauge

A Gauge increases and decreases.

Query:

demo_queue_depth

Refresh several times.

The value changes.

Analogy:

Fuel gauge.

Histogram

Query:

demo_http_request_duration_seconds_bucket

A Histogram stores values inside buckets.

Example:

Bucket

	

Requests

|

Example:

(
sum(rate(demo_http_requests_total[5m]))
-
sum(rate(demo_http_requests_total{status_code=~"2.."}[5m]))
)
/
sum(rate(demo_http_requests_total[5m]))
*100

However, production dashboards usually prefer explicit 5xx filtering because 404 and 301 are not always considered application failures.

Why Vector Matching Exists

This query often produces unexpected results.

rate(demo_http_requests_total{status_code="500"}[5m])
/
rate(demo_http_requests_total[5m])

Why?

Because labels do not match.

ignoring()
rate(demo_http_requests_total{status_code="500"}[5m])
/
ignoring(status_code)
rate(demo_http_requests_total[5m])

Prometheus ignores the status_code label while matching.

on()

Example:

... on(exported_endpoint)

Match only using exported_endpoint.

group_left

Used when one side has fewer labels than the other.

Example:

... on(exported_endpoint) group_left

Useful for one-to-many matching.

10. Histograms and Percentiles

Histograms are the standard way to calculate application latency.

Bucket Metric
demo_http_request_duration_seconds_bucket

Notice labels like:

le="0.05"
le="0.1"
le="0.25"

le means less than or equal to.

Why Buckets Exist

Instead of storing every request individually,

Prometheus stores counts inside buckets.

Example:

Latency

	

Requests

| :30090



Flow:


1. Browser
2. EC2 Public IP
3. Security Group
4. Kubernetes NodePort
5. Service
6. Prometheus Pod


`30090` forwards to Prometheus's internal `9090` port.


---


## Why does `rate()` require `[5m]`?


Because `rate()` needs historical samples.


`[5m]` tells Prometheus to examine the last five minutes before calculating requests per second.


---


## Why did one metric return multiple rows?


Because each unique label combination creates a separate Time Series.


Example:


| Endpoint | Status |
|----------|--------|
| fast | 200 |
| slow | 200 |
| work | 500 |


Three different label combinations become three different Time Series.


---


# Final Takeaways


By completing this lab, you should be able to:


- Understand how Prometheus collects metrics.
- Explain the Prometheus Data Model.
- Identify Counter, Gauge, Histogram, and Summary metrics.
- Filter metrics using label matchers.
- Use Instant and Range Vectors correctly.
- Calculate requests per second with `rate()`.
- Aggregate metrics for dashboards.
- Compute application error percentage.
- Calculate P95 and P99 latency using Histograms.
- Use advanced functions like `offset` and `predict_linear`.


These concepts form the foundation of production monitoring and are used extensively in Kubernetes, cloud-native platforms, and SRE workflows with Prometheus and Grafana.
