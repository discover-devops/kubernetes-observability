# Section 7: Grafana Setup and Access

**Module:** 01 - Introduction to Observability: Prometheus and Grafana Setup
**Duration:** approximately 10 minutes
**Hands-on:** Yes. Runs on the EKS jump box.
**Prerequisites:** Section 4. Port 3000 open to your IP on the jump box security group.

> **Running short on time?** Labs 1 and 2 are essential. Lab 4 (Explore and PromQL) can be shortened, since Module 04 covers Grafana properly.

---

## Table of Contents

- [Why Grafana](#why-grafana)
- [Lab 1: Access Grafana](#lab-1-access-grafana)
- [Lab 2: The Default Dashboards](#lab-2-the-default-dashboards)
- [Lab 3: Verify the Data Source](#lab-3-verify-the-data-source)
- [How the Dashboards Got There](#how-the-dashboards-got-there)
- [Lab 4: Explore and PromQL](#lab-4-explore-and-promql)
- [A Note on Exposing Grafana](#a-note-on-exposing-grafana)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Interview Questions](#interview-questions)
- [What's Next](#whats-next)

---

## Why Grafana

Everything so far has been the Prometheus web interface. It works, and it is the right tool when you are debugging a query or checking whether a target is up.

It is not something you put on a wall or hand to a team. There is no way to arrange several graphs together, no way to save a view, no way to share one with a colleague.

That is the gap Grafana fills.

If Prometheus is the engine and the sensor array in a car, quietly collecting telemetry, Grafana is the instrument cluster behind the steering wheel. It measures nothing itself. It turns numbers into something a person can read at a glance while doing something else.

The important thing to hold onto:

> **Grafana stores no metrics. It sends PromQL queries to Prometheus and draws the answers.**

Every number on a Grafana dashboard was fetched from Prometheus at the moment the page loaded. Delete Grafana and you lose dashboards, not data.

---

## Lab 1: Access Grafana

Find the pod and the service:

```bash
kubectl get pods -n monitoring | grep grafana
kubectl get svc kube-prometheus-stack-grafana -n monitoring
```

Note the service listens on port **80**, not 3000. Grafana inside the container listens on 3000, and the Service maps 80 to it. Your port-forward has to account for that.

```bash
kubectl port-forward --address 0.0.0.0 \
  svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

Read that mapping carefully: `3000:80` means local port 3000 forwards to service port 80. Reversing it is a common mistake and produces a connection error that looks like Grafana is broken.

This command blocks. Leave it running and use a second terminal for anything else.

Open in your browser:

```
http://<jump-box-public-ip>:3000
```

Log in:

- **Username:** `admin`
- **Password:** the value of `adminPassword` from `prometheus-values.yaml`

If you did not set one, or cannot remember it, the chart stored it in a Secret:

```bash
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

---

## Lab 2: The Default Dashboards

Click **Dashboards** in the left menu.

You have roughly 30 dashboards that you did not create, covering the cluster, its nodes, its workloads, and the monitoring stack itself. Names vary slightly between chart versions, so browse rather than looking for exact matches.

Four worth opening now:

**Kubernetes / Compute Resources / Cluster**

Overall cluster health. CPU and memory utilisation, requests versus limits versus actual usage across every namespace.

The gap between *requests* and *usage* is the most useful thing on this page. Large gaps mean workloads reserving capacity they never touch, which is where cloud spend quietly goes.

**Kubernetes / Compute Resources / Namespace (Pods)**

The same view scoped to one namespace. Select `monitoring` from the dropdown at the top and you are looking at the resource consumption of the stack you just installed.

Prometheus is usually the largest consumer. Worth seeing, because it explains why a t3.medium was not enough back in Section 4.

**Node Exporter / Nodes**

Per-node operating system metrics. CPU by mode, memory breakdown, disk I/O, network throughput, filesystem usage.

This data comes from the node-exporter DaemonSet. Use the node selector at the top to switch between your two nodes.

**Prometheus / Overview**

Prometheus monitoring itself. Samples ingested per second, active time series, memory in use, scrape duration.

The **active series count** on this dashboard is the number to watch in production. It is the direct measure of the cardinality problem from Section 2, and the number that predicts an out-of-memory event before it happens.

---

## Lab 3: Verify the Data Source

Go to **Connections**, then **Data sources**. In older Grafana versions this lives under **Configuration**.

Prometheus is already there, marked as default. Click it and look at the URL:

```
http://kube-prometheus-stack-prometheus.monitoring:9090
```

That is a Kubernetes DNS name: service name, then namespace. Grafana reaches Prometheus over the cluster network. Neither is exposed outside the cluster, which is exactly why you needed a port-forward to see any of this.

Scroll to the bottom and click **Save & test**. You want a green confirmation that the data source is working.

You configured none of this. No URL entered, no connection tested, no credentials supplied.

---

## How the Dashboards Got There

Look at the Grafana pod again:

```bash
kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].spec.containers[*].name}'
echo
```

```
grafana grafana-sc-dashboard grafana-sc-datasources
```

Three containers. Grafana plus two sidecars, and the pattern is the same one from Section 6.

`grafana-sc-datasources` watches for ConfigMaps labelled as datasources and writes them into Grafana's provisioning directory. That is where the Prometheus connection came from.

`grafana-sc-dashboard` does the same for dashboards. Every one of those 30 dashboards is a ConfigMap in the cluster:

```bash
kubectl get configmap -n monitoring -l grafana_dashboard=1 | head -15
```

```bash
kubectl get configmap -n monitoring -l grafana_dashboard=1 --no-headers | wc -l
```

Each ConfigMap holds a dashboard's JSON definition. The sidecar notices them and loads them without restarting Grafana.

This matters beyond trivia. It means **dashboards can be managed as code**. Create a ConfigMap with the right label and your dashboard appears. Store it in git, review it in a pull request, deploy it with your application.

That is the subject of Module 07.

---

## Lab 4: Explore and PromQL

Dashboards answer questions somebody anticipated. **Explore** is for the questions you did not.

Click **Explore** in the left menu and confirm Prometheus is selected as the data source.

Try these, one at a time.

**CPU usage percentage per node**

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Memory usage percentage per node**

```
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
/ node_memory_MemTotal_bytes * 100
```

**Running pods per namespace**

```
count by (namespace) (kube_pod_status_phase{phase="Running"} == 1)
```

This one comes from kube-state-metrics rather than node-exporter. It is Kubernetes object state, not machine state, which is the distinction from Section 2.

**Pod restarts in the last hour**

```
increase(kube_pod_container_status_restarts_total[1h]) > 0
```

An empty result is good news. It means nothing has crashed.

**Current active time series**

```
prometheus_tsdb_head_series
```

Prometheus reporting on itself. Watch this number in production.

Switch between **Table** and **Graph** at the top. Table is better for instant values, Graph for anything over time.

---

## A Note on Exposing Grafana

We used `port-forward` because it needs no cluster changes and works everywhere. It is a debugging tool, not a way to run Grafana.

In production you would use an **Ingress** with TLS and an authentication layer in front, or a **LoadBalancer** Service if the cluster sits inside a private network.

Whichever you choose, two things matter. Change the admin password from anything that appeared in a values file, and put real authentication in front of it. Grafana supports OAuth, SAML and LDAP. A dashboard showing your entire infrastructure is not something to leave open.

Module 06 covers production Grafana properly, including high availability and an external database.

Stop the port-forward with Ctrl+C when you are done.

---

## Troubleshooting

**Browser times out**

Three causes, in the order worth checking:

1. `--address 0.0.0.0` missing from the port-forward command
2. Port 3000 not open to your IP in the jump box security group
3. The port-forward process died, since it runs in the foreground

A timeout points at the firewall or the missing address flag. A refused connection points at the port-forward not running.

**Connection refused immediately after port-forward starts**

Usually the ports are reversed. It is `3000:80`, not `80:3000`. The service listens on 80.

**Invalid username or password**

Retrieve it from the Secret using the command in Lab 1. If you changed `adminPassword` in the values file and ran `helm upgrade`, note that Grafana stores the password in its database on first start and does not update it on subsequent upgrades.

**Dashboards show No data**

Check the data source first, under Connections then Data sources, then Save & test.

If the data source is healthy, check the time range in the top right. A default of "last 6 hours" on a cluster built 20 minutes ago shows mostly empty space. Narrow it to 15 minutes.

If it is still empty, the metric may genuinely not exist yet. Test the underlying query in Explore, and remember from Section 5 that a metric never observed is absent rather than zero.

**A dashboard is missing entirely**

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=30
```

The sidecar logs which ConfigMaps it loaded and which it rejected.

---

## Key Takeaways

- Grafana stores no metrics. It queries Prometheus with PromQL and renders the results.
- The Grafana Service listens on port 80 and maps to 3000 in the container, so the port-forward is `3000:80`.
- The chart ships roughly 30 dashboards and pre-configures the Prometheus data source. You configure neither.
- Grafana runs three containers: itself plus dashboard and datasource sidecars, the same pattern as `config-reloader`.
- Every default dashboard is a ConfigMap labelled `grafana_dashboard=1`, which is what makes dashboards-as-code possible.
- The data source URL is a Kubernetes DNS name, so Grafana reaches Prometheus over the cluster network.
- Explore is for ad-hoc questions. Dashboards are for questions somebody already anticipated.
- `port-forward` is for labs. Production needs an Ingress with TLS and real authentication.

---

## Interview Questions

**1. Does Grafana store metrics?**

No. Grafana holds dashboards, users and data source definitions in its own database, but no time series data. Every panel issues a query to the backing data source when the page loads.

**2. How does Grafana know where Prometheus is in this setup?**

The chart creates a ConfigMap containing a data source definition, and the `grafana-sc-datasources` sidecar writes it into Grafana's provisioning directory. The URL is the Kubernetes DNS name of the Prometheus Service.

**3. Why does the Grafana pod run three containers?**

Grafana itself, plus two sidecars. One watches for ConfigMaps containing dashboards, the other for data sources, and both load their contents without restarting Grafana. It is the same sidecar pattern as `config-reloader` on the Prometheus pod.

**4. How would you add a dashboard without using the Grafana UI?**

Create a ConfigMap containing the dashboard JSON, labelled `grafana_dashboard: "1"`. The sidecar picks it up automatically. This is what allows dashboards to be version-controlled and deployed alongside applications.

**5. Your dashboard shows No data but Prometheus has the metrics. What do you check?**

The data source connection first, then the dashboard's time range, then the query itself in Explore. Also confirm any template variables at the top of the dashboard are resolving, since an unmatched namespace or pod selection produces empty panels.

**6. Why is port-forward unsuitable for production access?**

It is a single foreground process on one machine, with no high availability, no TLS, and no authentication in front of it. It exists for debugging. Production access needs an Ingress or LoadBalancer with proper authentication.

---

## What's Next

You have metrics being collected, stored and visualised.

But dashboards only help when somebody is looking at them, and at 2 AM nobody is. Prometheus can already evaluate alerting rules, as you saw in Section 5 when an alert moved from Pending to Firing.

What happens to an alert after it fires? Who receives it, how are duplicates handled, and what stops fifty related alerts from becoming fifty separate messages?

[Section 8: Alertmanager](./08-alertmanager.md)
