### Grafana – Part 2

### Dynamic Dashboards, Dashboard-as-Code & Alerting

>  Environment: Ubuntu + K3s + Prometheus + Grafana

### Session Flow (TOC)

### 0. Quick Recap 

Goal: Connect today's session with what we already built.

* What we built in Part 1

* Prometheus → Grafana → Dashboard flow

* Four panels we created

* Why today's session matters

### 1. Variables – Build One Dashboard for Every Node (25 minutes)

> Theme: Stop creating multiple dashboards. Make one dashboard dynamic.

### 1.1 Why Variables Exist

* Real-world problem (50-node cluster)

* Google Maps analogy

* How Grafana substitutes variables

### 1.2 Lab – Create Node Variable

Live writing:

* Query Variable

* `label_values()`

* `$node`

* Verify dropdown

### 1.3 Lab – Create Namespace Variable

Live writing:

* Query Variable

* Multi-value

* Include All

* `$namespace`

### 1.4 Lab – Create Interval Variable

Live writing:

* `$interval`

* Dynamic `rate()` windows

### 1.5 Update Existing Panels

We'll rewrite existing PromQL together.

Instead of pasting, we'll build queries step by step.

### 1.6 Advanced Lab – Chained Variables

Build this flow:

`Namespace → Pod → Container`

We will see how production dashboards perform drill-down filtering.

### 1.7 Common Debugging

* `=` vs `=~`

* Why "No Data" happens

* Multi-value troubleshooting

### 2. Dashboard Persistence – Dashboard as Code (25 minutes)

> Theme: Never lose your dashboards again.

### 2.1 Why Dashboards Disappear

* SQLite

* Pod restart

* EmptyDir problem

### 2.2 Lab – Verify Current Storage

* Check PVC

* Understand Grafana storage

### 2.3 Lab – Enable Persistent Volume

Live writing of:

* `persistence`

* PVC

* StorageClass

* Verification

### 2.4 Lab – Export Dashboard

We will export their own dashboard.

### 2.5 Lab – Create ConfigMap

Live writing:

Bash

kubectl create configmap ...

Every line will be written during class.

### 2.6 Lab – Dashboard Provider

We'll build:

* Provider YAML

* Helm values

* Mount ConfigMap

* `helm upgrade`

### 2.7 GitOps Workflow

How production teams manage dashboards through Git.

### 3. Grafana Alerting vs Alertmanager (25 minutes)

> Theme: Two tools. Two different jobs.

### 3.1 Why Grafana Has Alerting

* Building security analogy

* Infrastructure vs Business alerts

### 3.2 Architecture Comparison

* Alertmanager responsibilities

* Grafana Alerting responsibilities

### 3.3 Lab – Create First Alert

We'll build together.

PromQL will be written line by line.

* Query

* Reduce

* Threshold

* Evaluation

* Labels

### 3.4 Contact Points

* Slack

* Notification Policy

* Alert routing

### 3.5 Grafana → Alertmanager

How enterprise teams combine both.

### 4. Production Architecture Wrap-Up (8 minutes)

We'll connect everything into one picture.

Final architecture:

* Prometheus

* Grafana

* Variables

* Dashboard-as-Code

* Alerting

* Alertmanager

### 5. Challenge (5 minutes)

WE will build one feature without copying.

### Challenge

* Create one new variable.

* Modify one panel.

* Save the dashboard.

* Export it.



