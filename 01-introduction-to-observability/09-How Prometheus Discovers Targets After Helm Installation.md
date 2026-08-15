# How Prometheus Discovers Targets After Helm Installation

## Table of Contents

1.  Introduction
2.  What Happens After Helm Installation
3.  Every Component Created by kube-prometheus-stack
4.  Understanding the Prometheus Operator
5.  Why Prometheus Does Not Automatically Monitor Everything
6.  Custom Resource Definitions
7.  ServiceMonitor
8.  PodMonitor
9.  Prometheus CR
10. Alertmanager CR
11. PrometheusRule
12. Probe
13. ScrapeConfig
14. End-to-End Discovery Flow
15. Command Walkthrough
16. Resource Relationships
17. Complete Architecture
18. Summary

## Introduction

Many people install `kube-prometheus-stack` using Helm and immediately
see several Pods running. The next question is usually:

"How did Prometheus know what to monitor?"

The answer is that Prometheus itself is only the monitoring engine. The
intelligence for discovering applications comes from the Prometheus
Operator and several Kubernetes Custom Resources.

This document explains exactly what gets created, why it gets created,
and how every object connects together.

## What Happens After Helm Installation

We install the chart using Helm.

``` bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values.yaml
```

`values.yaml` describes what we want.

Helm renders Kubernetes manifests.

Kubernetes creates resources.

The Prometheus Operator then watches those resources and builds the
final Prometheus configuration.

The flow looks like this.

``` text
values.yaml
    ↓
Helm
    ↓
Rendered Kubernetes Manifests
    ↓
Kubernetes API
    ↓
Prometheus Operator
    ↓
Prometheus Configuration
    ↓
Prometheus starts scraping metrics
```

## Every Component Created by kube-prometheus-stack

In a two node cluster you may see something similar.

  Component             Purpose
  --------------------- ---------------------------------
  Prometheus            Stores metrics
  Grafana               Visualization
  Alertmanager          Handles alerts
  Prometheus Operator   Builds Prometheus configuration
  kube-state-metrics    Kubernetes object metrics
  node-exporter         Node operating system metrics
  CRDs                  Monitoring instructions

Example Pods.

``` bash
kubectl get pods -n monitoring
```

Example output.

``` text
NAME                                              READY   STATUS
prometheus-kube-prometheus-prometheus-0           2/2     Running
prometheus-grafana-xxxxxxxx                       3/3     Running
prometheus-kube-state-metrics-xxxxxxxx            1/1     Running
prometheus-node-exporter-abcde                    1/1     Running
prometheus-node-exporter-fghij                    1/1     Running
prometheus-operator-xxxxxxxx                      1/1     Running
alertmanager-prometheus-0                         2/2     Running
```

Notice that `node-exporter` is a DaemonSet.

A DaemonSet creates one Pod on every node.

Two nodes mean two `node-exporter` Pods.

## Understanding the Prometheus Operator

The Operator is the brain of the monitoring stack.

Without it, Prometheus would require manual editing of `prometheus.yml`
every time a new application appears.

Instead, the Operator continuously watches Kubernetes.

``` text
New ServiceMonitor Created
          ↓
Operator Detects It
          ↓
Updates Prometheus Configuration
          ↓
Prometheus Reloads Automatically
```

This removes manual configuration management.

## Why Prometheus Does Not Automatically Monitor Everything

Installing Prometheus does not mean monitoring every application.

Prometheus still needs answers to questions like:

-   Which application?
-   Which port?
-   Which endpoint?
-   How often?

Think of Prometheus as a security guard.

The guard is ready.

Someone still has to provide instructions.

Those instructions are stored inside Kubernetes Custom Resources.

## What Are Custom Resource Definitions

Kubernetes normally understands resources like:

-   Pod
-   Service
-   Deployment

The Prometheus Operator extends Kubernetes by adding new resource types.

Check them.

``` bash
kubectl get crds | grep monitoring.coreos.com
```

Example output.

``` text
alertmanagers.monitoring.coreos.com
podmonitors.monitoring.coreos.com
probes.monitoring.coreos.com
prometheuses.monitoring.coreos.com
prometheusrules.monitoring.coreos.com
scrapeconfigs.monitoring.coreos.com
servicemonitors.monitoring.coreos.com
```

Each one has a specific responsibility.

## ServiceMonitor

ServiceMonitor is the most commonly used monitoring object.

It tells Prometheus:

-   which Service to monitor
-   which port
-   which path
-   how often

Example.

``` yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: frontend-monitor

spec:
  selector:
    matchLabels:
      app: frontend

  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
```

This does not scrape metrics.

It simply stores monitoring instructions.

Flow.

``` text
Service
    ↓
ServiceMonitor
    ↓
Operator
    ↓
Prometheus Configuration
    ↓
Prometheus
    ↓
GET /metrics
```

View ServiceMonitors.

``` bash
kubectl get servicemonitor -A
```

Example.

``` text
NAMESPACE    NAME
monitoring   prometheus-grafana
monitoring   prometheus-kube-state-metrics
monitoring   prometheus-kubelet
```

## PodMonitor

Some workloads do not expose a Service.

Examples include:

-   Jobs
-   CronJobs
-   Standalone Pods

PodMonitor watches Pods directly.

Example.

``` yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: worker-monitor

spec:
  selector:
    matchLabels:
      app: worker

  podMetricsEndpoints:
  - port: metrics
    interval: 30s
```

Discovery flow.

``` text
Pod
   ↓
PodMonitor
   ↓
Operator
   ↓
Prometheus
```

View PodMonitors.

``` bash
kubectl get podmonitor -A
```

## Prometheus Custom Resource

This resource defines the Prometheus server itself.

Example.

``` bash
kubectl get prometheus -A
```

Example output.

``` text
NAMESPACE    NAME
monitoring   prometheus-kube-prometheus-prometheus
```

Describe it.

``` bash
kubectl describe prometheus prometheus-kube-prometheus-prometheus -n monitoring
```

Important fields include:

-   replica count
-   storage
-   ServiceMonitor selector
-   PodMonitor selector
-   retention

## Alertmanager Custom Resource

Alertmanager manages alerts after Prometheus fires them.

View it.

``` bash
kubectl get alertmanager -A
```

Flow.

``` text
Prometheus
     ↓
Alert Fired
     ↓
Alertmanager
     ↓
Email
Slack
PagerDuty
Webhook
```

## PrometheusRule

PrometheusRule stores alerting and recording rules.

Example.

``` yaml
groups:
- name: cpu-alerts

  rules:
  - alert: HighCPUUsage
    expr: node_cpu_seconds_total > 90
```

View rules.

``` bash
kubectl get prometheusrule -A
```

Flow.

``` text
Metrics
    ↓
PrometheusRule
    ↓
Prometheus Evaluates
    ↓
Alertmanager
```

## Probe

Probe is used for black box monitoring.

Instead of collecting application metrics, it tests availability.

Examples include:

-   HTTP
-   HTTPS
-   TCP
-   ICMP

Flow.

``` text
Probe
   ↓
Blackbox Exporter
   ↓
Website
```

View Probes.

``` bash
kubectl get probe -A
```

## ScrapeConfig

ScrapeConfig is a newer resource that allows advanced scrape
configuration.

Examples include:

-   static targets
-   custom authentication
-   external endpoints

View it.

``` bash
kubectl get scrapeconfig -A
```

## End-to-End Discovery Flow

Imagine a frontend application.

Step 1

Deployment creates Pods.

``` text
Frontend Pods
```

Step 2

A Service exposes those Pods.

``` text
Frontend Service
```

Step 3

A ServiceMonitor selects that Service.

``` text
ServiceMonitor
```

Step 4

The Operator notices the new ServiceMonitor.

Step 5

The Operator updates Prometheus.

Step 6

Prometheus starts scraping.

The complete flow.

``` text
Deployment
     ↓
Pods
     ↓
Service
     ↓
ServiceMonitor
     ↓
Operator
     ↓
Prometheus
     ↓
Metrics Database
     ↓
Grafana
```

## Command Walkthrough

Check Pods.

``` bash
kubectl get pods -n monitoring
```

Check Services.

``` bash
kubectl get svc -n monitoring
```

Check CRDs.

``` bash
kubectl get crds | grep monitoring.coreos.com
```

Check ServiceMonitors.

``` bash
kubectl get servicemonitor -A
```

Describe one.

``` bash
kubectl describe servicemonitor prometheus-kube-state-metrics -n monitoring
```

Check PodMonitors.

``` bash
kubectl get podmonitor -A
```

Check Prometheus.

``` bash
kubectl get prometheus -A
```

Check Alertmanager.

``` bash
kubectl get alertmanager -A
```

Check Rules.

``` bash
kubectl get prometheusrule -A
```

## Resource Relationships

  Resource              Role
  --------------------- -------------------------------
  Helm                  Installs everything
  Prometheus Operator   Watches monitoring resources
  Prometheus            Collects metrics
  Grafana               Displays dashboards
  Alertmanager          Sends alerts
  ServiceMonitor        Monitors Services
  PodMonitor            Monitors Pods
  PrometheusRule        Defines alerts
  Probe                 Performs black box monitoring
  ScrapeConfig          Advanced scraping

## Complete Architecture

``` text
                Helm Installation
                       ↓
          kube-prometheus-stack Chart
                       ↓
              Kubernetes Resources
                       ↓
             Prometheus Operator
                       ↓
     Watches Monitoring Custom Resources
                       ↓
  ServiceMonitor   PodMonitor   PrometheusRule
        ↓               ↓              ↓
     Discovers      Discovers      Alert Logic
      Services         Pods
           \            /
            \          /
             Prometheus
                 ↓
          Metrics Database
                 ↓
             Grafana
                 ↓
            Dashboards

        Alerts
          ↓
     Alertmanager
          ↓
Email Slack PagerDuty Webhook
```

## Summary

After installing `kube-prometheus-stack`, Kubernetes creates much more
than just Prometheus and Grafana.

The Prometheus Operator becomes responsible for discovering monitoring
instructions stored in Custom Resources.

ServiceMonitor discovers Services.

PodMonitor discovers Pods.

PrometheusRule defines alert logic.

Alertmanager handles notifications.

Probe performs availability testing.

ScrapeConfig provides advanced target configuration.

This design keeps monitoring completely declarative. Instead of manually
editing `prometheus.yml`, you simply create Kubernetes resources, and
the Operator automatically converts them into a working Prometheus
configuration.
