# Section 5: Custom Resource Definitions

**Module:** 01 - Introduction to Observability: Prometheus and Grafana Setup
**Duration:** approximately 15 minutes
**Hands-on:** Yes. Runs on the EKS jump box.
**Prerequisites:** Section 4 completed, with all pods Running in the `monitoring` namespace.

---

## Table of Contents

- [The Question From Section 4](#the-question-from-section-4)
- [You Already Know This Pattern](#you-already-know-this-pattern)
- [What the Operator Installed](#what-the-operator-installed)
- [Lab 1: Prove It With a Real Target](#lab-1-prove-it-with-a-real-target)
- [Lab 2: See the Generated Configuration](#lab-2-see-the-generated-configuration)
- [Lab 3: Alerts as Code with PrometheusRule](#lab-3-alerts-as-code-with-prometheusrule)
- [PodMonitor: When There Is No Service](#podmonitor-when-there-is-no-service)
- [AlertmanagerConfig](#alertmanagerconfig)
- [Old Way vs CRD Way](#old-way-vs-crd-way)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Interview Questions](#interview-questions)
- [What's Next](#whats-next)

---

## The Question From Section 4

At the end of Section 4 you opened the Targets page and saw dozens of targets. The API server, the kubelet on every node, CoreDNS, kube-state-metrics, node-exporter.

You configured none of them.

In Section 3 every target had to be typed into `prometheus.yml` by hand under `static_configs`. Here there is no such file to edit. So what told Prometheus to scrape the kubelet?

The answer is Custom Resource Definitions, and understanding them is what separates someone who can install this chart from someone who can operate it.

---

## You Already Know This Pattern

Before defining anything, look at something you do every day.

You never start a container directly. You write a Deployment: three replicas of this image. You hand that to the Kubernetes API and walk away.

Something else does the work. A controller notices the Deployment, compares desired state against actual state, and creates a ReplicaSet. Another controller creates Pods. If a pod dies, the gap between desired and actual reappears and the controller closes it again.

You declared **what you want**. A control loop made reality match.

```
   You write            Controller watches         Reality becomes
   -----------          ------------------         ----------------
   Deployment     ->    Deployment controller  ->  ReplicaSet, Pods
```

The Prometheus Operator applies exactly this pattern to monitoring configuration.

```
   You write            Operator watches           Reality becomes
   -----------          ------------------         ----------------
   ServiceMonitor  ->   Prometheus Operator   ->   scrape config in prometheus.yml
```

That is all a CRD is. Kubernetes lets you add new object types to the API, and a controller gives them meaning. `ServiceMonitor` is not built into Kubernetes. The operator installed it, and the operator is what makes it do something.

So the mental shift for this section is small but important:

> **You stop configuring Prometheus. You start declaring intent to Kubernetes, and let a controller configure Prometheus for you.**

---

## What the Operator Installed

```bash
kubectl get crds | grep monitoring.coreos.com
```

You will see something close to this. The exact list grows with chart versions, so yours may have more:

```
alertmanagerconfigs.monitoring.coreos.com
alertmanagers.monitoring.coreos.com
podmonitors.monitoring.coreos.com
probes.monitoring.coreos.com
prometheusagents.monitoring.coreos.com
prometheuses.monitoring.coreos.com
prometheusrules.monitoring.coreos.com
scrapeconfigs.monitoring.coreos.com
servicemonitors.monitoring.coreos.com
thanosrulers.monitoring.coreos.com
```

Four of these matter for daily work:

| CRD | Purpose |
|---|---|
| **ServiceMonitor** | Scrape the pods behind a Service |
| **PodMonitor** | Scrape pods directly, no Service required |
| **PrometheusRule** | Define recording and alerting rules |
| **AlertmanagerConfig** | Route alerts to receivers |

The others are for less common cases: `Probe` for blackbox checks, `ScrapeConfig` for targets outside the cluster, `ThanosRuler` for long-term storage setups, `PrometheusAgent` for remote-write-only deployments.

And note that `Prometheus` and `Alertmanager` are themselves CRDs. The running Prometheus in your cluster is an object you can inspect:

```bash
kubectl get prometheus -n monitoring
kubectl get alertmanager -n monitoring
```

The operator watches those too. The StatefulSet you saw in Section 4 was created by the operator from that `Prometheus` object, not by Helm directly.

---

## Lab 1: Prove It With a Real Target

Rather than writing a ServiceMonitor for an application that does not exist, deploy something real and watch Prometheus find it.

### Step 1: Deploy an application that exposes metrics

```bash
cat > example-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
  namespace: default
  labels:
    app: example-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: example-app
  template:
    metadata:
      labels:
        app: example-app
    spec:
      containers:
        - name: example-app
          image: quay.io/brancz/prometheus-example-app:v0.3.0
          ports:
            - name: web
              containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: example-app
  namespace: default
  labels:
    app: example-app
spec:
  selector:
    app: example-app
  ports:
    - name: web
      port: 8080
      targetPort: web
EOF

kubectl apply -f example-app.yaml
kubectl get pods -n default -l app=example-app
```

Wait until both pods are `Running`.

This is a small application that exposes Prometheus format metrics on port 8080 at `/metrics`. Confirm that for yourself before going further:

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s http://example-app.default.svc.cluster.local:8080/metrics | head -20
```

You should see output including `http_requests_total`. That is the endpoint Prometheus is going to scrape.

Note the port is **named** `web` on both the Deployment and the Service. That name is what the ServiceMonitor will reference, and getting it wrong is the most common mistake in this section.

### Step 2: Confirm Prometheus is not scraping it yet

Port-forward the Prometheus UI:

```bash
kubectl port-forward --address 0.0.0.0 \
  svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

In your browser at `http://<jump-box-ip>:9090`, run this query:

```
http_requests_total
```

Empty result. The application is running and exposing metrics, and Prometheus has no idea it exists.

Leave the port-forward running in this terminal. Use a second terminal for what follows.

### Step 3: Create the ServiceMonitor

```bash
cat > example-app-servicemonitor.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: example-app
  namespace: monitoring
spec:
  # Which Services to target, by label
  selector:
    matchLabels:
      app: example-app

  # Which namespaces to look in
  namespaceSelector:
    matchNames:
      - default

  # How to scrape them
  endpoints:
    - port: web
      interval: 15s
      path: /metrics
EOF

kubectl apply -f example-app-servicemonitor.yaml
kubectl get servicemonitor -n monitoring
```

Three fields, and each answers a different question.

**`selector.matchLabels`** answers *which Service*. It matches labels on the Service object, not on the pods. This is the field people get wrong most often.

**`namespaceSelector`** answers *where to look*. Our ServiceMonitor lives in `monitoring` but the Service lives in `default`, so we have to say so. Omit this and it only looks in its own namespace.

**`endpoints.port`** answers *which port*. It refers to the port **name** on the Service, not the number. This is why we named it `web`.

Notice what is missing: no IP addresses, no pod names, no hostnames. You described a shape, not a location. When the deployment scales from two replicas to ten, Prometheus picks up all ten without anything being changed.

### Step 4: Watch it get discovered

Go back to the browser. Refresh the Targets page under **Status**, then **Target health**.

Within about 30 seconds, a new target group appears: `serviceMonitor/monitoring/example-app`. Two endpoints, both UP, one per pod.

Now run the query again:

```
http_requests_total
```

Data. Two series, one per pod, each with `pod`, `namespace`, `service` and `instance` labels attached automatically.

Nothing restarted. No pod was recreated. Check for yourself:

```bash
kubectl get pods -n monitoring
```

The Prometheus pod's AGE is unchanged and RESTARTS is still 0. Configuration changed underneath a running process. Section 6 explains the mechanism.

### Step 5: Prove the dynamic part

Scale the application:

```bash
kubectl scale deployment example-app -n default --replicas=4
kubectl get pods -n default -l app=example-app
```

Wait for all four to be Running, then refresh the Targets page.

Four endpoints. You did not touch the ServiceMonitor, Prometheus, or any configuration file. Two new pods appeared with addresses nobody could have predicted, and they are being scraped.

This is the thing that was impossible in Section 3.

Scale back down:

```bash
kubectl scale deployment example-app -n default --replicas=2
```

Refresh again. Two targets. The removed ones disappear on their own.

---

## Lab 2: See the Generated Configuration

Here is the part that makes the whole concept click.

`static_configs` did not vanish. Prometheus still reads a configuration file, exactly like the one in Section 3. The difference is that a controller writes it now instead of you.

The operator stores that generated file in a Secret, gzipped:

```bash
kubectl get secret prometheus-kube-prometheus-stack-prometheus \
  -n monitoring -o jsonpath='{.data.prometheus\.yaml\.gz}' \
  | base64 -d | gunzip | head -60
```

That is a real `prometheus.yml`. Same format you looked at in Section 3.

Now find your ServiceMonitor in it:

```bash
kubectl get secret prometheus-kube-prometheus-stack-prometheus \
  -n monitoring -o jsonpath='{.data.prometheus\.yaml\.gz}' \
  | base64 -d | gunzip | grep -A 25 "serviceMonitor/monitoring/example-app"
```

You will see a `kubernetes_sd_configs` block with a long list of `relabel_configs`. That is the machine-generated equivalent of the twelve lines you wrote.

Look at how much of it there is. Then look at your ServiceMonitor again. That difference is the value the operator provides: you wrote intent, it wrote implementation.

Count the jobs in the file:

```bash
kubectl get secret prometheus-kube-prometheus-stack-prometheus \
  -n monitoring -o jsonpath='{.data.prometheus\.yaml\.gz}' \
  | base64 -d | gunzip | grep -c "job_name"
```

Every one of those came from a ServiceMonitor, and every one was generated for you.

---

## Lab 3: Alerts as Code with PrometheusRule

Alerting rules work the same way. Instead of editing a rules file, you create an object.

```bash
cat > example-app-rules.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: example-app-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: example-app.rules
      rules:
        - alert: ExampleAppDown
          expr: up{job="example-app"} == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Example app target is down"
            description: "Target {{ $labels.instance }} has been unreachable for more than 1 minute."

        - alert: ExampleAppHighErrorRate
          expr: |
            sum(rate(http_requests_total{job="example-app",code=~"5.."}[5m]))
            /
            sum(rate(http_requests_total{job="example-app"}[5m])) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Error rate above 5 percent"
            description: "More than 5 percent of requests are returning 5xx responses."
EOF

kubectl apply -f example-app-rules.yaml
kubectl get prometheusrule -n monitoring
```

Note the label on this one:

```yaml
labels:
  release: kube-prometheus-stack
```

The ServiceMonitor did not need this because we set `serviceMonitorSelectorNilUsesHelmValues: false` in Section 4. PrometheusRules are selected separately, and the chart still filters them by release label. Without this label, the rule is created successfully, appears in `kubectl get prometheusrule`, and Prometheus never loads it.

That silent-failure pattern is worth internalising. In this system, an object existing does not mean it is being used.

### Verify Prometheus loaded it

In the browser, go to **Status**, then **Rules**. Search for `example-app.rules`. Both rules should be listed.

Then go to the **Alerts** tab. `ExampleAppDown` will be in state `Inactive`, which is correct: the app is up, so the condition is false.

### Make it fire

Break it deliberately:

```bash
kubectl scale deployment example-app -n default --replicas=0
```

Watch the Alerts tab. The sequence is worth watching in real time:

1. Within ~30 seconds the target disappears and `up` stops returning 1
2. The rule condition becomes true, and the alert moves to **Pending**
3. After the `for: 1m` duration, it moves to **Firing**

That `for` clause is why alerting systems are not just threshold checks. A brief blip does not page anybody. The condition has to hold.

Bring it back:

```bash
kubectl scale deployment example-app -n default --replicas=2
```

The alert returns to Inactive within a minute.

---

## PodMonitor: When There Is No Service

A ServiceMonitor discovers pods through a Service. Sometimes there is no Service to go through.

A batch job. A DaemonSet where you want every pod individually rather than one load-balanced endpoint. A StatefulSet where each pod matters separately. A pod exposing a metrics port that is deliberately not part of any Service.

PodMonitor selects pods directly:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: example-app-pods
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: example-app
  namespaceSelector:
    matchNames:
      - default
  podMetricsEndpoints:
    - port: web
      interval: 30s
```

Two differences from ServiceMonitor: `podMetricsEndpoints` instead of `endpoints`, and the selector matches labels on **pods** rather than on a Service.

Which should you use? Prefer ServiceMonitor when a Service exists. It is the more common pattern, and going through the Service means the metadata Prometheus attaches lines up with how the rest of your cluster refers to that workload.

---

## AlertmanagerConfig

The fourth CRD routes alerts to receivers, so that different alerts reach different places.

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: example-routing
  namespace: monitoring
spec:
  route:
    receiver: 'team-slack'
    groupBy: ['alertname', 'severity']
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 12h
  receivers:
    - name: 'team-slack'
      slackConfigs:
        - apiURL:
            name: slack-webhook-secret
            key: url
          channel: '#alerts'
```

Two things to note. The API version is `v1alpha1`, not `v1`, so its schema can still change between releases. And the Slack webhook URL comes from a Secret reference rather than being written inline, which is how credentials should always be handled.

We are not applying this now. Section 8 covers Alertmanager routing properly, including grouping, inhibition and silencing.

---

## Old Way vs CRD Way

| | Section 3 approach | Operator approach |
|---|---|---|
| Add a target | Edit `prometheus.yml` on the server | `kubectl apply -f servicemonitor.yaml` |
| Apply the change | Restart or reload the service | Automatic within ~30 seconds |
| Downtime | Restart drops in-memory state | None |
| Where config lives | A file on one machine | Kubernetes objects, storable in git |
| Who can change it | Anyone with SSH to that box | Controlled by RBAC |
| New pod appears | Nobody knows, edit the file | Discovered automatically |
| Review process | None | Pull request, like any other code |

The last two rows matter more than they look.

Because these are ordinary Kubernetes objects, monitoring configuration goes into version control with everything else. Changes get reviewed. An application team can ship a ServiceMonitor alongside their Deployment in the same manifest, and their service is monitored from the moment it is deployed, without filing a ticket with a monitoring team.

That is the real shift. Not the syntax, the ownership.

---

## Cleanup

Remove what this section created. The monitoring stack itself stays for Section 6.

```bash
kubectl delete -f example-app-servicemonitor.yaml
kubectl delete -f example-app-rules.yaml
kubectl delete -f example-app.yaml
rm example-app.yaml example-app-servicemonitor.yaml example-app-rules.yaml
```

Confirm the targets disappear:

```bash
kubectl get servicemonitor -n monitoring
kubectl get prometheusrule -n monitoring | grep example-app
kubectl get pods -n default -l app=example-app
```

The `example-app` target group vanishes from the Targets page within about 30 seconds. Again, with no restart.

Stop the port-forward with Ctrl+C.

---

## Troubleshooting

**ServiceMonitor applied, but no target appears**

The most common problem in this section, and it never produces an error. Work through it in this order.

First, does the selector actually match the Service? Check the Service's labels:

```bash
kubectl get svc example-app -n default --show-labels
```

The ServiceMonitor's `selector.matchLabels` must match labels on the **Service**, not on the pods.

Second, is the namespace right? If the ServiceMonitor and Service are in different namespaces, `namespaceSelector.matchNames` is required.

Third, does the port name match? The `endpoints.port` value refers to the port **name** on the Service. If your Service defines a port without a name, there is nothing to reference.

```bash
kubectl get svc example-app -n default -o jsonpath='{.spec.ports[*].name}'
echo
```

Fourth, is Prometheus even looking at this ServiceMonitor?

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A 5 serviceMonitorSelector
```

If it shows a `matchLabels` requirement, your ServiceMonitor needs that label. This is what `serviceMonitorSelectorNilUsesHelmValues: false` prevents.

Finally, read the operator's own logs. It reports rejected resources:

```bash
kubectl logs -n monitoring deploy/kube-prometheus-stack-operator --tail=50
```

**Target appears but shows DOWN**

Different problem. DOWN means Prometheus found the target and the scrape failed. Missing means it was never discovered.

Hover over the error text on the Targets page. Common causes are connection refused (wrong port), 404 (wrong path), or a NetworkPolicy blocking traffic from the monitoring namespace.

**PrometheusRule created but not visible under Status, Rules**

Almost always the missing `release: kube-prometheus-stack` label. Check what Prometheus is selecting on:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A 5 ruleSelector
```

**Alert stuck in Pending and never fires**

That is the `for` duration doing its job. `for: 1m` means the condition must hold continuously for a full minute. Check the Alerts page for how long it has been pending.

---

## Key Takeaways

- A CRD extends the Kubernetes API with a new object type. A controller gives that type meaning.
- The Prometheus Operator applies the same control loop pattern you already use with Deployments, but to monitoring configuration.
- ServiceMonitor describes a shape to scrape, not a location. Pods matching it are discovered as they appear and dropped as they go.
- `prometheus.yml` still exists. It is generated by the operator and stored gzipped in a Secret, and you can read it.
- PrometheusRules need the `release: kube-prometheus-stack` label or Prometheus silently ignores them.
- An object existing is not the same as an object being used. Always verify in the Prometheus UI, not just with `kubectl get`.
- Use ServiceMonitor when a Service exists, PodMonitor when it does not.
- Because configuration is now Kubernetes objects, it lives in git, goes through review, and can be owned by the application team.

---

## Interview Questions

**1. What is a Custom Resource Definition, and what does it do on its own?**

A CRD registers a new object type with the Kubernetes API server, so instances of it can be created, stored and retrieved like any built-in resource. On its own it does nothing. A controller has to watch for those objects and act on them. The CRD is the schema; the controller is the behaviour.

**2. How does a ServiceMonitor cause Prometheus to scrape something?**

The Prometheus Operator watches ServiceMonitor objects. When one is created or changed, the operator regenerates the Prometheus configuration file, including a Kubernetes service discovery block with relabelling rules derived from the ServiceMonitor. That file is stored in a Secret mounted into the Prometheus pod, and a sidecar triggers a reload.

**3. What is the difference between ServiceMonitor and PodMonitor?**

ServiceMonitor discovers pods through a Service, selecting on the Service's labels. PodMonitor selects pods directly and needs no Service. Use PodMonitor when no Service exists, such as for batch jobs, or when you need each pod individually rather than a load-balanced endpoint.

**4. You applied a ServiceMonitor and no target appeared, with no error anywhere. How do you debug it?**

Check in order: whether the selector matches labels on the Service rather than on the pods; whether `namespaceSelector` covers the Service's namespace; whether `endpoints.port` matches a named port on the Service; and whether Prometheus's own `serviceMonitorSelector` restricts which ServiceMonitors it will accept. The operator logs report rejected resources.

**5. Where does Prometheus's actual configuration file live in an operator-managed setup?**

In a Secret in the same namespace, gzipped, mounted into the Prometheus pod. It is generated by the operator and should never be edited directly, because the operator will overwrite any manual change on its next reconciliation.

**6. What does the `for` clause do in an alerting rule?**

It requires the condition to hold continuously for that duration before the alert fires. The alert sits in Pending during that window. This suppresses brief transient spikes, which is the difference between an alerting system and a simple threshold check.

**7. Why would a PrometheusRule be created successfully and still not take effect?**

The chart configures Prometheus to select PrometheusRules by label, typically `release: kube-prometheus-stack`. A rule without that label is a valid object that Prometheus never loads. Nothing errors, which makes it hard to spot.

---

## What's Next

Something in this section deserves a second look.

You applied a ServiceMonitor and Prometheus picked it up within 30 seconds. You applied a PrometheusRule and it appeared under Status, Rules. You deleted both and the targets disappeared.

The Prometheus pod never restarted. Its AGE kept climbing and RESTARTS stayed at 0 throughout.

A running process picked up new configuration without being restarted. That is not automatic, and it is not magic. There is a specific component doing it, and you already saw it in the `2/2` READY column in Section 4.

[Section 6: Auto-Reload](./06-auto-reload.md)
