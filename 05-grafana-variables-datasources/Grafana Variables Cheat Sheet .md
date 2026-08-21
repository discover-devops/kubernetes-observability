### Grafana Variables Cheat Sheet (Grafana 12)

> Dashboard: Shop Monitoring Dashboard

|
Variable

|

Purpose

|

Query Type

|
| --- | --- | --- |
|

`node`

|

Select Kubernetes Node

|

Label values

|
|

`namespace`

|

Filter Kubernetes Namespace

|

Label values

|
|

`interval`

|

Dynamic time window

|

Interval

|
|

`pod`

|

Filter Pods based on Namespace

|

Label values

|

### Variable 1 – Node (`$node`)

Purpose: Filter infrastructure panels by Kubernetes node.

### Settings

|
Field

|

Value

|
| --- | --- |
|

Variable Type

|

Query

|
|

Name

|

`node`

|
|

Label

|

`Node`

|
|

Data Source

|

Prometheus

|
|

Query Type

|

Label values

|
|

Metric

|

`node_cpu_seconds_total`

|
|

Label

|

`instance`

|
|

Refresh

|

On Dashboard Load

|
|

Multi-value

|

OFF

|
|

Include All

|

ON

|

![Grafana Dashboard Tutorial (Basic→Advanced) | MetricFire | MetricFire](https://images.openai.com/static-rsc-4/FBcpM8FA0asBpOodk9a0x4mI2398yyDZYdfBKilub6jzP7cM6WYuqwFGdvWLrMmaPsP1MEL15nAkzcHZulSk7186IlfG8OmjCBW_QyFv7NinAjWhO5qs7wXyKWZ11uRuKYGTRFrSZpwlU4eUwIIx6NDfbUgUKSFLELZsriLHcCE?purpose=inline)

### Used in Panel

Node CPU Usage

promql

100 * (1 - avg by (instance) (

rate(node_cpu_seconds_total{instance="$node", mode="idle"}[5m])

))

### Variable 2 – Namespace (`$namespace`)

Purpose: Filter workloads by Kubernetes namespace.

### Settings

|
Field

|

Value

|
| --- | --- |
|

Variable Type

|

Query

|
|

Name

|

`namespace`

|
|

Label

|

`Namespace`

|
|

Data Source

|

Prometheus

|
|

Query Type

|

Label values

|
|

Metric

|

`kube_pod_info`

|
|

Label

|

`namespace`

|
|

Refresh

|

On Dashboard Load

|
|

Multi-value

|

ON

|
|

Include All

|

ON

|

![How to fetch the pod status, container ready status in grafana dashboard for kubernetes cluster in a namespace - Stack Overflow](https://images.openai.com/static-rsc-4/4ChUW98SV_bHqqj8hqOg7AQZWoNC6GncPYG-gSDjdIVZrI07np0cQwdX5aJpP4ekVyREDAgt-dcew90bsyndULpFhjILGemLDuQ4mnAwTAtc5X1DN57jsz3PLKPp_9T9FcO3dBB13y49skuMqdVmHem4aZu1RnVqZ5so4TIvfwQ?purpose=inline)

### Used in Panel

Pod Count by Namespace

promql

count by (namespace) (

kube_pod_info{namespace=~"$namespace"}

)

### Why `=~`?

|
Operator

|

Meaning

|
| --- | --- |
|

`=`

|

Exact match

|
|

`=~`

|

Regex match (required for Multi-value)

|

Example:

shop|monitoring

matches both namespaces.

### Variable 3 – Interval (`$interval`)

Purpose: Make `rate()` queries automatically adapt to the dashboard time range.

### Settings

|
Field

|

Value

|
| --- | --- |
|

Variable Type

|

Interval

|
|

Name

|

`interval`

|
|

Label

|

`Interval`

|
|

Values

|

`1m,5m,15m,30m,1h`

|
|

Auto

|

Enabled

|
|

Auto Count

|

`30`

|
|

Auto Min

|

`1m`

|

![Tweaking the $\_\_interval variable - Dashboards - Grafana Labs Community Forums](https://images.openai.com/static-rsc-4/OIMvNq5q8MN5R0IyVXMrQaF-RCll7g0NhT3jerDkozNiB5jUUp8G0qvj6pX55Sxe-Jy3ZGvbmlq4YVv8A01kNW4239o8ZE9vWU6qsMYRPXU_BSiYqvZvnCAay3wJiD_GGmLYZ8SU3wT5Jgy07bRfL9EZ4VB-RrXxT0Ou9Y7Iipg?purpose=inline)

### Used in Panel

Replace:

promql

rate(http_requests_total[5m])

with

promql

rate(http_requests_total[$interval])

### Why?

|
Dashboard Range

|

Auto Interval

|
| --- | --- |
|

Last 15 min

|

1m

|
|

Last 24 hours

|

15m

|
|

Last 7 days

|

1h

|

Grafana automatically substitutes `$interval`.

### Variable 4 – Pod (`$pod`) – Chained Variable

Purpose: Show only pods belonging to the selected namespace.

### Settings

|
Field

|

Value

|
| --- | --- |
|

Variable Type

|

Query

|
|

Name

|

`pod`

|
|

Label

|

`Pod`

|
|

Data Source

|

Prometheus

|
|

Query Type

|

Label values

|
|

Metric

|

`kube_pod_info{namespace=~"$namespace"}`

|
|

Label

|

`pod`

|
|

Refresh

|

On Dashboard Load

|
|

Multi-value

|

ON

|
|

Include All

|

ON

|

![Keeping graphs of terminated Kubernetes pods in Prometheus/Grafana - DevOps Stack Exchange](https://images.openai.com/static-rsc-4/AfIIxXGan2EUgIe6GEawIoXmKFg2r-0aQC4gUITiXXhO6csboSJztCytvnQsRWi1sNIYRmijWz0gAugcYkYvrbSvTMAcKdcsJzJci9fqjWZAxO4oigUZC7rAFmTBjddTJrn_3HtL1O3uht26UdwCTZDpXYcHEDFcvrPC_eHRjxw?purpose=inline)

### Used in Panel

Example:

promql

rate(http_requests_total{pod=~"$pod"}[$interval])

### Chained Variable Flow

![](blob\:https://chatgpt.com/529c59ee-7301-4847-9733-f52cb9238716)

When `shop` is selected, the Pod dropdown automatically shows only the pods inside the `shop` namespace.

### Variable Summary

|
Variable

|

Dashboard Control

|

Panel Query

|
| --- | --- | --- |
|

`$node`

|

Node dropdown

|

`instance="$node"`

|
|

`$namespace`

|

Namespace dropdown

|

`namespace=~"$namespace"`

|
|

`$interval`

|

Time window

|

`[$interval]`

|
|

`$pod`

|

Pod dropdown

|

`pod=~"$pod"`

|

This single page becomes an excellent live-session reference because you can create every variable in under 5 minutes without switching back and forth between notes, and students get one consolidated reference they can reuse later.
