# Section 8: Alertmanager

**Module:** 01 - Introduction to Observability: Prometheus and Grafana Setup
**Duration:** approximately 10 minutes
**Hands-on:** Yes. Runs on the EKS jump box.
**Prerequisites:** Section 4. Port 9093 open to your IP on the jump box security group.

> **Running short on time?** Labs 1 and 2 are essential. Lab 3 (Slack configuration) is optional and needs a real webhook URL.

---

## Table of Contents

- [Why a Separate Component](#why-a-separate-component)
- [The Four Jobs](#the-four-jobs)
- [Lab 1: Access Alertmanager](#lab-1-access-alertmanager)
- [Lab 2: Read the Current Configuration](#lab-2-read-the-current-configuration)
- [Understanding the Route Tree](#understanding-the-route-tree)
- [Lab 3: Configure Slack (Optional)](#lab-3-configure-slack-optional)
- [Silencing](#silencing)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Interview Questions](#interview-questions)
- [What's Next](#whats-next)

---

## Why a Separate Component

In Section 5 you watched an alert move from Inactive to Pending to Firing. Prometheus evaluated the rule and decided the condition was true.

Then what?

Prometheus does not send emails. It does not know your on-call rota, that Diwali is a holiday, or that a database outage will trigger fourteen other alerts you do not need to see separately. It hands the firing alert to Alertmanager and stops caring.

> **Prometheus decides whether to alert. Alertmanager decides who to tell, and whether to tell them at all.**

The split is deliberate. Prometheus knows about data. Alertmanager knows about people and schedules. They change for entirely different reasons: you edit alert thresholds when your system changes, and you edit routing when your team changes.

There is a practical benefit too. Multiple Prometheus servers can send to one Alertmanager, so a single routing policy covers your whole estate rather than being duplicated in every Prometheus configuration.

---

## The Four Jobs

Imagine a CDN region fails during a live match. Fifty edge servers go unreachable at the same instant, plus the health checks watching them, plus the latency alerts for every service behind them.

Two hundred alerts fire within ten seconds.

Without Alertmanager, that is two hundred separate messages to your phone at 2 AM, and the one that matters is buried somewhere in the middle.

Alertmanager does four things about that.

**Grouping.** Alerts sharing labels are bundled into one notification. Fifty edge servers in the same region become one message listing fifty instances.

**Inhibition.** A more severe alert suppresses less severe ones that are its consequence. If the region is down, do not also page about individual server latency. You already know.

**Silencing.** Mute alerts matching a pattern for a set duration. Planned maintenance on Saturday means nobody gets paged for the thing you are deliberately doing.

**Routing.** Different alerts go to different places. Critical to PagerDuty, warnings to Slack, and the database team's alerts to the database team.

Grouping and inhibition are the two most people underestimate. They are the difference between an alerting system people trust and one they mute.

---

## Lab 1: Access Alertmanager

```bash
kubectl get pods -n monitoring | grep alertmanager
kubectl get svc kube-prometheus-stack-alertmanager -n monitoring
```

The pod shows `2/2`. Same pattern as Prometheus: Alertmanager plus a `config-reloader` sidecar, so configuration changes apply without a restart.

```bash
kubectl port-forward --address 0.0.0.0 \
  svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
```

Open in your browser:

```
http://<jump-box-public-ip>:9093
```

Three tabs at the top.

**Alerts** shows what is currently firing and has reached Alertmanager. You will almost certainly see one called `Watchdog`.

That alert is meant to be firing. It is a deliberate heartbeat: a rule whose condition is always true, so it fires constantly and forever. If your notification pipeline is working, something receives Watchdog on a schedule.

The point is what happens when it *stops*. Silence from your alerting system is ambiguous, exactly like silence from a cell tower in Section 2. Watchdog turns "no alerts" into a positive signal: if you stop receiving it, the monitoring itself has failed. External services exist solely to watch for the absence of this alert.

**Silences** is empty for now.

**Status** shows the running configuration, which is the same content Lab 2 reads from the command line.

---

## Lab 2: Read the Current Configuration

The chart stores Alertmanager's configuration in a Secret:

```bash
kubectl get secret alertmanager-kube-prometheus-stack-alertmanager \
  -n monitoring -o jsonpath='{.data.alertmanager\.yaml\.gz}' \
  | base64 -d | gunzip
```

If that returns nothing, the chart version you have stores it uncompressed. Try:

```bash
kubectl get secret alertmanager-kube-prometheus-stack-alertmanager \
  -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

The default configuration looks roughly like this:

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'null'
  routes:
    - matchers:
        - alertname = "Watchdog"
      receiver: 'null'

receivers:
  - name: 'null'
```

Note the receiver named `null`. It has no configuration at all, which means alerts routed to it go nowhere.

Out of the box, this stack detects everything and notifies nobody. That is the correct default, because the chart cannot know your Slack workspace or your PagerDuty key. Making it useful is your job, and it is Lab 3.

---

## Understanding the Route Tree

Four timing fields control notification behaviour, and mixing them up is the most common source of confusion.

**`group_by`** decides which alerts belong in the same bundle. Grouping by `namespace` means all alerts from one namespace arrive together.

**`group_wait: 30s`** is how long to wait after the first alert in a new group before sending, so related alerts firing seconds apart travel together. Fifty servers failing at once produce one message rather than fifty.

**`group_interval: 5m`** is how long to wait before sending an update about a group that already notified, when new alerts join it.

**`repeat_interval: 12h`** is how long before re-sending a notification for an alert still firing and unchanged. This is the nagging interval.

Get these wrong in the obvious direction and you get alert fatigue: `group_wait: 0s` and `repeat_interval: 5m` means every alert arrives individually and repeats twelve times an hour. People mute the channel, and then the alerting system may as well not exist.

The `routes` list is evaluated in order, and the first match wins unless `continue: true` is set. This is why the Watchdog route sits first: catch it, send it to `null`, and stop.

---

## Lab 3: Configure Slack (Optional)

Skip this if you do not have a Slack workspace with an incoming webhook. The concepts above matter more than the mechanics here.

### Store the webhook as a Secret

Never put a webhook URL in a values file. It is a credential, and anyone holding it can post to your channel.

```bash
kubectl create secret generic alertmanager-slack \
  --from-literal=url='https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  -n monitoring
```

### Write the routing configuration

```bash
cat > alertmanager-slack-values.yaml << 'EOF'
alertmanager:
  config:
    global:
      resolve_timeout: 5m

    route:
      group_by: ['alertname', 'namespace', 'severity']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'null'
      routes:
        - matchers:
            - alertname = "Watchdog"
          receiver: 'null'
        - matchers:
            - severity = "critical"
          receiver: 'slack-critical'
        - matchers:
            - severity = "warning"
          receiver: 'slack-warnings'

    receivers:
      - name: 'null'

      - name: 'slack-critical'
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/alertmanager-slack/url
            channel: '#alerts-critical'
            send_resolved: true
            title: 'CRITICAL: {{ .GroupLabels.alertname }}'
            text: |
              {{ range .Alerts }}
              *Summary:* {{ .Annotations.summary }}
              *Description:* {{ .Annotations.description }}
              *Namespace:* {{ .Labels.namespace }}
              {{ end }}

      - name: 'slack-warnings'
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/alertmanager-slack/url
            channel: '#alerts-warnings'
            send_resolved: true
            title: 'WARNING: {{ .GroupLabels.alertname }}'
            text: '{{ .CommonAnnotations.summary }}'

    inhibit_rules:
      - source_matchers:
          - severity = "critical"
        target_matchers:
          - severity = "warning"
        equal: ['alertname', 'namespace']

  alertmanagerSpec:
    secrets:
      - alertmanager-slack
EOF
```

Three things worth reading carefully.

**`alertmanagerSpec.secrets`** mounts the Secret into the pod at `/etc/alertmanager/secrets/<secret-name>/`. Without this line the file referenced by `api_url_file` does not exist and Alertmanager fails to start.

**`send_resolved: true`** sends a follow-up when the alert clears. Without it, you learn that things broke and never that they recovered.

**The `inhibit_rules` block** is grouping's more useful sibling. When a critical alert fires, warnings sharing the same `alertname` and `namespace` are suppressed. You get told the important thing once instead of the same event twice at two severities.

### Apply it

```bash
helm upgrade kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --values alertmanager-slack-values.yaml
```

Both values files are passed. Helm merges them in order, so the second overrides the first where they overlap. Omit the first and every setting from Section 4 reverts to chart defaults, including your storage configuration.

Verify the new config was loaded:

```bash
kubectl logs -n monitoring \
  alertmanager-kube-prometheus-stack-alertmanager-0 \
  -c alertmanager --tail=20 | grep -i "reload\|completed"
```

---

## Silencing

Silences are created in the UI rather than in configuration, because they are temporary and situational.

In the Alertmanager web interface, click **Silences**, then **New Silence**. Set a matcher such as `namespace = default`, choose a duration, add a comment explaining why, and create it.

Matching alerts stop notifying until it expires. They still fire in Prometheus and still appear in the UI. Only the notification is suppressed.

Always write a real comment. A silence with no explanation is one nobody dares remove, and forgotten silences are how real outages go unnoticed.

Stop the port-forward with Ctrl+C when you are done.

---

## Troubleshooting

**Alertmanager UI shows no alerts at all**

Check that Prometheus knows where to send them:

```bash
kubectl port-forward --address 0.0.0.0 \
  svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

Then in the Prometheus UI, go to **Status**, then **Runtime and build information**, and confirm Alertmanager endpoints are listed. If none appear, Prometheus has no route to send alerts and nothing will ever arrive.

**Alert is firing in Prometheus but never appears in Alertmanager**

Confirm it is genuinely Firing and not still Pending. The `for` duration must elapse first, as you saw in Section 5.

**Alertmanager pod will not start after a config change**

Usually a bad configuration or a missing mounted Secret:

```bash
kubectl logs -n monitoring \
  alertmanager-kube-prometheus-stack-alertmanager-0 \
  -c alertmanager --tail=40
```

If it reports a missing file under `/etc/alertmanager/secrets/`, the `alertmanagerSpec.secrets` entry is missing or the Secret name does not match.

**Notifications reaching Slack but with empty fields**

The template references annotations the alert does not define. `{{ .Annotations.description }}` renders empty if the PrometheusRule has no description. Check the rule.

---

## Key Takeaways

- Prometheus decides whether to alert. Alertmanager decides who to tell, and whether to tell them.
- Alertmanager does four things: grouping, inhibition, silencing and routing.
- The chart ships with a receiver named `null`, so out of the box nothing is notified. That is intentional.
- Watchdog is an alert designed to fire permanently. Its absence, not its presence, is the signal.
- `group_wait`, `group_interval` and `repeat_interval` control notification timing. Setting them too aggressively causes alert fatigue.
- Routes are evaluated in order and the first match wins unless `continue: true` is set.
- Webhook URLs belong in Secrets, mounted through `alertmanagerSpec.secrets`, never in a values file.
- Always pass every values file to `helm upgrade`, or omitted settings revert to chart defaults.

---

## Interview Questions

**1. Why are Prometheus and Alertmanager separate components?**

They solve different problems and change for different reasons. Prometheus evaluates rules against time series data. Alertmanager handles grouping, inhibition, silencing and delivery, which depend on team structure and schedules rather than on metrics. Separating them also lets several Prometheus servers share one routing policy.

**2. What is the Watchdog alert for?**

It is a deliberately always-firing alert used to prove the notification pipeline works end to end. Because it fires constantly, its absence indicates that Prometheus or Alertmanager has failed. External dead-man's-switch services watch for it stopping.

**3. What is the difference between grouping and inhibition?**

Grouping bundles alerts sharing labels into a single notification, so fifty related alerts arrive as one message. Inhibition suppresses lower-severity alerts entirely when a higher-severity alert covering the same situation is already firing.

**4. Explain group_wait, group_interval and repeat_interval.**

`group_wait` is the delay before sending the first notification for a new group, so related alerts arrive together. `group_interval` is the delay before sending an update about a group that has already notified. `repeat_interval` is how long before re-sending for an alert that is still firing unchanged.

**5. How would you handle planned maintenance without being paged?**

Create a silence in Alertmanager matching the affected labels for the maintenance window, with a comment explaining it. Alerts continue to fire and remain visible in the UI; only the notification is suppressed.

**6. Where should a Slack webhook URL be stored?**

In a Kubernetes Secret, mounted into the Alertmanager pod through `alertmanagerSpec.secrets` and referenced with `api_url_file`. Putting it in a values file means committing a credential to version control.

---

## What's Next

You have a complete monitoring stack: collection, storage, visualisation and alerting.

Now the operational questions. How do you upgrade it without losing your data? How do you change configuration safely? And when something is wrong, which commands actually tell you what is happening?

[Section 9: Upgrading and Managing the Stack](./09-upgrading-the-stack.md)
