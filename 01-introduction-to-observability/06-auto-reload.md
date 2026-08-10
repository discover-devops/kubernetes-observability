# Section 6: Auto-Reload

**Module:** 01 - Introduction to Observability: Prometheus and Grafana Setup
**Duration:** approximately 6 minutes
**Hands-on:** Yes. Runs on the EKS jump box.
**Prerequisites:** Section 5.

> **Running short on time?** The essential part is Lab 1 and the flow diagram. Lab 2 (triggering a reload manually) can be skipped and read later.

---

## Table of Contents

- [The Thing You Already Saw](#the-thing-you-already-saw)
- [The Second Container](#the-second-container)
- [Lab 1: Look at the Sidecar](#lab-1-look-at-the-sidecar)
- [What Actually Happens](#what-actually-happens)
- [Lab 2: Trigger a Reload Yourself](#lab-2-trigger-a-reload-yourself)
- [Why Not Just Restart the Pod?](#why-not-just-restart-the-pod)
- [Reload Strategies](#reload-strategies)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Interview Questions](#interview-questions)
- [What's Next](#whats-next)

---

## The Thing You Already Saw

In Section 5 you applied a ServiceMonitor and a target appeared within 30 seconds. You applied a PrometheusRule and it showed up under Status, Rules. You deleted both and they disappeared.

Throughout all of it, the Prometheus pod never restarted. Its AGE kept climbing and RESTARTS stayed at 0.

A running process picked up new configuration without stopping. Something specific is doing that, and you have already seen it without noticing.

---

## The Second Container

Back in Section 4, the pod list showed `2/2` for Prometheus.

```
prometheus-kube-prometheus-stack-prometheus-0    2/2    Running    0    3m
```

Two containers in one pod. Confirm which:

```bash
kubectl get pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring \
  -o jsonpath='{.spec.containers[*].name}'
echo
```

```
prometheus config-reloader
```

The first is Prometheus itself. The second is a **sidecar** whose only job is to notice when configuration changes and tell Prometheus to re-read it.

This is a standard Kubernetes pattern. Two containers sharing a network namespace and volumes, one doing the work and one supporting it. Because they share `localhost`, the sidecar can reach Prometheus on port 9090 without any network configuration at all.

---

## Lab 1: Look at the Sidecar

Read the sidecar's own arguments. They describe exactly what it does:

```bash
kubectl get pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring \
  -o jsonpath='{.spec.containers[1].args}' | tr ',' '\n'
```

Among the output you will see, in some form:

```
--listen-address=:8080
--reload-url=http://127.0.0.1:9090/-/reload
--config-file=/etc/prometheus/config/prometheus.yaml.gz
--config-envsubst-file=/etc/prometheus/config_out/prometheus.env.yaml
--watched-dir=/etc/prometheus/rules/prometheus-...-rulefiles-0
```

Three of these tell the whole story.

**`--config-file`** is the gzipped configuration the operator generates. This is the Secret you decompressed in Section 5.

**`--watched-dir`** is where rule files land, mounted from the ConfigMaps the operator builds out of your PrometheusRule objects.

**`--reload-url`** is the endpoint the sidecar calls when either of those changes. Note the address: `127.0.0.1`. It is talking to Prometheus over localhost inside the same pod.

Now look at what it has actually been doing:

```bash
kubectl logs prometheus-kube-prometheus-stack-prometheus-0 \
  -n monitoring -c config-reloader --tail=20
```

You will see entries recording reload triggers. If you did Section 5 recently, the ServiceMonitor and PrometheusRule changes are in there.

And from the other side, Prometheus logging that it re-read its configuration:

```bash
kubectl logs prometheus-kube-prometheus-stack-prometheus-0 \
  -n monitoring -c prometheus --tail=50 | grep -i "reload\|Loading configuration"
```

Two containers, two halves of the same event.

---

## What Actually Happens

The full sequence, from your `kubectl apply` to Prometheus scraping a new target:

```
   1.  You apply a ServiceMonitor
              |
              v
   2.  Operator sees the new object via the Kubernetes API
              |
              v
   3.  Operator regenerates prometheus.yaml.gz
       and writes it into the Secret
              |
              v
   4.  Kubelet syncs the updated Secret into the
       pod's mounted volume
              |
              v
   5.  config-reloader notices the file changed
              |
              v
   6.  config-reloader sends POST to
       http://127.0.0.1:9090/-/reload
              |
              v
   7.  Prometheus re-reads its config and applies
       the new target list. No restart.
```

Step 4 is the one people forget, and it explains the delay.

Kubernetes does not push Secret updates into pods instantly. The kubelet syncs mounted Secrets and ConfigMaps on a periodic cycle, typically around a minute. So the gap between your `kubectl apply` and the target appearing is mostly the kubelet, not Prometheus being slow.

That is why "it takes up to a minute" is the honest answer rather than "it is instant."

---

## Lab 2: Trigger a Reload Yourself

The reload endpoint is an ordinary HTTP endpoint. You can call it.

Start a port-forward:

```bash
kubectl port-forward --address 0.0.0.0 \
  svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

In a second terminal on the jump box:

```bash
curl -X POST http://localhost:9090/-/reload -w "\nHTTP %{http_code}\n"
```

`HTTP 200` means the reload was accepted.

> **Note:** running `curl` inside the Prometheus container with `kubectl exec` does not work. The Prometheus image is built on a minimal base and does not include curl or wget. Use the port-forward as above.

Confirm Prometheus acted on it:

```bash
kubectl logs prometheus-kube-prometheus-stack-prometheus-0 \
  -n monitoring -c prometheus --tail=20 | grep -i "Loading configuration"
```

A fresh timestamp appears.

This endpoint only exists because the operator starts Prometheus with `--web.enable-lifecycle`. Without that flag the endpoint returns 404, which is the default for a plain Prometheus install. It is disabled by default because an unauthenticated reload endpoint is something an attacker could abuse.

Stop the port-forward with Ctrl+C.

---

## Why Not Just Restart the Pod?

A reasonable question. Deleting the pod would also pick up new configuration, and Kubernetes would recreate it.

Four reasons that is worse.

**You lose in-memory data.** Prometheus buffers recent samples in memory before writing them to disk. A restart discards anything not yet flushed, leaving a gap in your metrics.

**Startup is not instant.** Prometheus replays its write-ahead log on start. On a large TSDB that takes minutes, during which nothing is being scraped and nothing can be queried.

**You are blind exactly when you may need to see.** Configuration changes often happen during an incident. A restart means no monitoring during the window you care about most.

**It does not scale.** Configuration changes constantly in an active cluster. Every application team shipping a ServiceMonitor would restart your monitoring stack.

Reloading rereads the configuration file and adjusts the target list in place. The process, its memory, and its open TSDB are untouched.

---

## Reload Strategies

The operator supports two mechanisms, set by the `reloadStrategy` field on the Prometheus resource.

**HTTP** sends a POST to `/-/reload`. This is the default and what your cluster uses.

**ProcessSignal** sends `SIGHUP` to the Prometheus process instead, which avoids exposing a lifecycle endpoint at all.

Check yours:

```bash
kubectl get prometheus -n monitoring \
  -o jsonpath='{.items[0].spec.reloadStrategy}'
echo
```

Empty output means the field is unset and the operator default, HTTP, is in effect. That is why the `curl` in Lab 2 worked.

> **A note if you are following older material:** you may see `reloadStrategyType` used in values files found online. That key does not exist in this chart. Helm silently ignores unknown values keys, so it produces no error and does nothing at all. The correct field is `reloadStrategy` on the Prometheus spec.

---

## Troubleshooting

**Applied a ServiceMonitor and nothing happened after several minutes**

Check in order. First the operator, which is what regenerates the config:

```bash
kubectl logs -n monitoring deploy/kube-prometheus-stack-operator --tail=30
```

Then the sidecar, which is what triggers the reload:

```bash
kubectl logs prometheus-kube-prometheus-stack-prometheus-0 \
  -n monitoring -c config-reloader --tail=30
```

If the operator logs show nothing about your object, it was rejected before the config was ever regenerated. That is a Section 5 problem, usually a selector or label mismatch, not a reload problem.

**Reload endpoint returns 404**

`--web.enable-lifecycle` is not set, meaning the reload strategy is ProcessSignal rather than HTTP. Confirm with the `reloadStrategy` command above.

**Prometheus logs an error during reload**

The generated configuration is invalid. Prometheus rejects it and keeps running on the previous valid config, which is the correct behaviour. Read the error, then check the resource that triggered the regeneration. A malformed PromQL expression in a PrometheusRule is the usual cause.

---

## Key Takeaways

- The Prometheus pod runs two containers. The second, `config-reloader`, watches for configuration changes.
- Sidecar and main container share localhost, so the reload call goes to `127.0.0.1:9090` with no networking involved.
- The chain is: operator regenerates the Secret, kubelet syncs it into the pod, sidecar notices, sidecar POSTs to `/-/reload`.
- The delay is mostly the kubelet's Secret sync interval, not Prometheus.
- Reloading preserves in-memory samples and avoids a WAL replay. Restarting loses both.
- `/-/reload` exists only because the operator passes `--web.enable-lifecycle`. It is off by default in plain Prometheus.
- The field is `reloadStrategy`, not `reloadStrategyType`.

---

## Interview Questions

**1. How does Prometheus pick up configuration changes without restarting?**

A `config-reloader` sidecar in the same pod watches the mounted configuration file and rule directories. When they change it sends a POST to `/-/reload` over localhost, and Prometheus re-reads its configuration in place.

**2. Why use a sidecar rather than having Prometheus watch its own files?**

Separation of concerns, and it keeps Prometheus itself simpler. It also means the same reloader component is reused for Alertmanager, and the reload mechanism can be changed without touching Prometheus.

**3. Why is reloading preferable to restarting the pod?**

A restart loses in-memory samples not yet flushed to disk and triggers a write-ahead log replay that can take minutes on a large TSDB, during which nothing is scraped or queryable. Reloading leaves the process and its open database untouched.

**4. There is a delay between applying a ServiceMonitor and the target appearing. Where does it come from?**

Mostly the kubelet, which syncs mounted Secrets and ConfigMaps into pods on a periodic cycle rather than instantly. The operator regenerates the config quickly, and the reload itself is fast. The propagation into the pod is the slow step.

**5. What happens if the regenerated configuration is invalid?**

Prometheus rejects it, logs an error, and continues running on the last valid configuration. A bad rule cannot take monitoring down.

---

## What's Next

You now have Prometheus scraping dozens of targets and reloading its own configuration.

But everything so far has been the Prometheus web interface, which is a debugging tool rather than something you would put in front of a team. Nobody watches a raw expression browser all day.

The stack already installed Grafana, pre-wired to Prometheus, with around 30 dashboards ready to use.

[Section 7: Grafana Setup and Access](./07-grafana-setup-and-access.md)
