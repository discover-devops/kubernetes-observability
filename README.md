# Kubernetes Observability - Prometheus and Grafana

A hands-on course covering observability on Kubernetes, from first principles through production-grade dashboards and alerting.

Every lab runs on Amazon EKS. Each module is self-contained - you can start at any module without having completed the previous one, and each ends with a cleanup section that returns the cluster to a reusable state.

---

## Who This Is For

Engineers who can already run `kubectl` commands and understand Pods, Deployments, and Services. No prior Prometheus, Grafana, or PromQL experience is assumed.

---

## Course Map

| Module | Title | What You Build |
|---|---|---|
| 01 | [Introduction to Observability: Prometheus and Grafana Setup](./01-introduction-to-observability/) | kube-prometheus-stack on EKS via Helm, Grafana reachable, first dashboard |
| 02 | [Prometheus Monitoring Configuration](./02-prometheus-configuration/) | ServiceMonitors, scrape configuration, relabelling, a custom instrumented app |
| 03 | [Advanced Monitoring Techniques](./03-advanced-monitoring/) | PromQL in depth, recording rules, alerting rules, Alertmanager routing |
| 04 | [Getting Started with Grafana](./04-grafana-basics/) | Panels, queries, transformations, dashboard fundamentals |
| 05 | [Variables, Data Sources, and Persistent Dashboards](./05-grafana-variables-datasources/) | Template variables, multiple data sources, dashboards as code |
| 06 | [Scaling Grafana](./06-scaling-grafana/) | High availability, external database, performance tuning, real-world patterns |
| 07 | [Deploying Dashboards on Kubernetes](./07-dashboards-on-kubernetes/) | GitOps dashboards, ConfigMap sidecar, provisioning at scale |
| 08 | [Advanced Observability with New Relic](./08-newrelic-observability/) | Managed APM, distributed tracing, comparison with the open-source stack |

---

## Repository Layout

```
kubernetes-observability/
|
+-- README.md                        This file
+-- PREREQUISITES.md                 Tools, AWS access, cost expectations
+-- CLUSTER-SETUP.md                 Shared EKS cluster used across all modules
+-- TROUBLESHOOTING.md               Cross-module issue index
+-- LICENSE
|
+-- 01-introduction-to-observability/
|   +-- README.md                    Module overview, objectives, time estimate
|   +-- 01-what-is-observability.md
|   +-- 02-prometheus-architecture.md
|   +-- 03-apt-installation.md
|   +-- 04-helm-installation.md
|   +-- 05-custom-resource-definitions.md
|   +-- 06-auto-reload.md
|   +-- 07-grafana-setup-and-access.md
|   +-- 08-alertmanager.md
|   +-- 09-upgrading-the-stack.md
|   +-- 10-architecture-recap.md
|   +-- 99-cleanup.md
|   +-- RUNBOOK.md                   Every command start to finish, no prose
|   +-- manifests/
|   |   +-- cluster.yaml
|   |   +-- values.yaml
|   +-- images/
|   |   +-- 01-three-pillars.png
|   +-- excalidraw/
|       +-- 01-three-pillars.excalidraw
|
+-- 02-prometheus-configuration/      Same structure
+-- 03-advanced-monitoring/
+-- 04-grafana-basics/
+-- 05-grafana-variables-datasources/
+-- 06-scaling-grafana/
+-- 07-dashboards-on-kubernetes/
+-- 08-newrelic-observability/
```

### Why This Layout

**Numbered files, kebab-case.** They sort correctly in the GitHub file browser and read as a sequence.

**A RUNBOOK.md per module.** The teaching files explain the concepts. The runbook is pure copy-paste with no prose between commands. During a live session, or when repeating the lab later, commands without explanation are what you actually want open. Both come from the same source, so they do not drift apart.

**excalidraw/ alongside images/.** The `.excalidraw` source stays in the repository so diagrams remain editable. The exported PNG is what renders in GitHub. Anyone can open the source file at excalidraw.com and adapt it.

**manifests/ separate from prose.** Learners can fetch a YAML file directly rather than copying out of a code fence and inheriting broken indentation.

**99-cleanup.md in every module.** Two digits keeps it last in sort order, and it is the file people look for in a hurry when AWS charges appear.

---

## Getting Started

1. Read [PREREQUISITES.md](./PREREQUISITES.md) for tools, AWS access, and expected cost
2. Build the cluster with [CLUSTER-SETUP.md](./CLUSTER-SETUP.md)
3. Begin [Module 01](./01-introduction-to-observability/)

---

## Cost Warning

These labs run real AWS infrastructure. An EKS control plane costs approximately USD 0.10 per hour and bills whether or not you use it, plus EC2 and EBS charges for the worker nodes.

Delete your cluster when you finish a session. Every module cleanup file has the commands. Cleanup ordering matters - delete Kubernetes Service and Ingress resources before deleting the cluster, or orphaned load balancers will keep billing in the background.

---

## License

MIT. Use it, fork it, teach with it.
