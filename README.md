# Kubernetes Observability — Prometheus & Grafana

A hands-on course covering observability on Kubernetes, from first principles to production-grade dashboards and alerting.

Every lab runs on **Amazon EKS** and is **self-contained** — you can start at any module without having completed the previous one. Each module ends with a cleanup section that returns the cluster to a reusable state.

---

## Who This Is For

Engineers who can already run `kubectl` commands and understand Pods, Deployments, and Services. You do not need prior Prometheus, Grafana, or PromQL experience.

---

## Course Map

| # | Module | What You'll Build | Status |
|---|---|---|---|
| 01 | [Introduction to Observability: Prometheus & Grafana Setup](./01-introduction-to-observability/) | `kube-prometheus-stack` running on EKS via Helm, Grafana reachable, first dashboard | 🚧 |
| 02 | [Prometheus Monitoring Configuration](./02-prometheus-configuration/) | ServiceMonitors, scrape configs, relabelling, a custom instrumented app | 📋 |
| 03 | [Advanced Monitoring Techniques](./03-advanced-monitoring/) | PromQL depth, recording rules, alerting rules, Alertmanager routing | 📋 |
| 04 | [Getting Started with Grafana](./04-grafana-basics/) | Panels, queries, transformations, dashboard fundamentals | 📋 |
| 05 | [Variables, Data Sources & Persistent Dashboards](./05-grafana-variables-datasources/) | Template variables, multiple data sources, dashboards-as-code | 📋 |
| 06 | [Scaling Grafana](./06-scaling-grafana/) | HA setup, external database, performance tuning, real-world patterns | 📋 |
| 07 | [Deploying Dashboards on Kubernetes](./07-dashboards-on-kubernetes/) | GitOps dashboards, ConfigMap sidecar, provisioning at scale | 📋 |
| 08 | [Advanced Observability with New Relic](./08-newrelic-observability/) | Managed APM, distributed tracing, comparison with the open-source stack | 📋 |

🚧 In progress · 📋 Planned · ✅ Complete

---

## Repository Layout

```
.
├── README.md
├── PREREQUISITES.md                 # AWS account, tools, cost expectations
├── CLUSTER-SETUP.md                 # Shared eksctl cluster used across modules
├── TROUBLESHOOTING.md               # Cross-module issue index
│
├── 01-introduction-to-observability/
│   ├── README.md                    # Module overview, objectives, time estimate
│   ├── 01-what-is-observability.md
│   ├── 02-prometheus-architecture.md
│   ├── 03-apt-installation.md
│   ├── 04-helm-installation.md
│   ├── 05-custom-resource-definitions.md
│   ├── 06-auto-reload.md
│   ├── 07-grafana-setup-and-access.md
│   ├── 08-alertmanager.md
│   ├── 09-upgrading-the-stack.md
│   ├── 10-architecture-recap.md
│   ├── 99-cleanup.md
│   ├── RUNBOOK.md                   # Every command, start to finish, no prose
│   ├── manifests/
│   │   ├── cluster.yaml
│   │   └── values.yaml
│   ├── images/
│   │   ├── 01-three-pillars.png
│   │   └── ...
│   └── excalidraw/
│       ├── 01-three-pillars.excalidraw
│       └── ...
│
├── 02-prometheus-configuration/
│   └── (same structure)
│
└── ...
```

### Why This Layout

**Numbered files, kebab-case.** They sort correctly in GitHub's file browser and read as a sequence.

**`RUNBOOK.md` per module.** The teaching files explain; the runbook is pure copy-paste. During a live session or a rerun you want commands without prose between them. Both come from the same source of truth, so they never drift.

**`excalidraw/` alongside `images/`.** The `.excalidraw` source stays in the repo so diagrams stay editable. The exported PNG is what renders in GitHub. Anyone can open the source at [excalidraw.com](https://excalidraw.com) and adapt it.

**`manifests/` separate from prose.** Learners can `curl` a YAML file directly instead of copying out of a code fence and inheriting broken indentation.

**`99-cleanup.md` in every module.** Two digits keeps it last in sort order, and it is the file people look for in a hurry when AWS charges start showing up.

---

## Repository Name

Suggested: **`kubernetes-observability`**

It describes the subject rather than the tools. Modules 06–08 cover Grafana scaling and New Relic, so a name like `prometheus-grafana` would undersell the later half. `monitoring` alone is too broad and collides with hundreds of existing repos in search.

---

## Getting Started

1. Read [PREREQUISITES.md](./PREREQUISITES.md) — tools, AWS access, and expected cost
2. Build the cluster with [CLUSTER-SETUP.md](./CLUSTER-SETUP.md)
3. Start with [Module 01](./01-introduction-to-observability/)

---

## Cost Warning

These labs run real AWS infrastructure. An EKS control plane costs roughly **$0.10/hour** and keeps billing whether or not you use it, plus EC2 and EBS charges for the nodes.

**Delete your cluster when you finish a session.** Every module's cleanup file has the commands. Cleanup ordering matters — delete Kubernetes Service and Ingress resources *before* deleting the cluster, or you will leave orphaned load balancers billing in the background.

---

## License

MIT — use it, fork it, teach with it.
