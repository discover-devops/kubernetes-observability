# Monitoring and Observability: The Foundation

Before any tool, before any command, this is the engineering system you need to understand.

Most courses begin with "today we will install Prometheus using Helm." Students memorise commands, and six months later they cannot answer why Prometheus exists. This document takes the other route. By the time Prometheus appears, you will already know why every one of its components has to be there.

---

## Table of Contents

**Part 1: Why Monitoring Exists**
- [1.1 The Blindness Problem](#11-the-blindness-problem)
- [1.2 Monitoring vs Alerting](#12-monitoring-vs-alerting)
- [1.3 Monitoring Starts Before Failure](#13-monitoring-starts-before-failure)
- [1.4 Two Types of Observation](#14-two-types-of-observation)
- [1.5 Monitoring vs Observability](#15-monitoring-vs-observability)
- [1.6 The Three Pillars](#16-the-three-pillars)
- [1.7 A Real Kubernetes Example](#17-a-real-kubernetes-example)

**Part 2: The Generic Monitoring Architecture**
- [2.1 The Question Nobody Asks](#21-the-question-nobody-asks)
- [2.2 Every Monitoring System Has Four Jobs](#22-every-monitoring-system-has-four-jobs)
- [2.3 The Six Actors](#23-the-six-actors)
- [2.4 The Generic Architecture](#24-the-generic-architecture)
- [2.5 Bringing Kubernetes Back](#25-bringing-kubernetes-back)

**Part 3: How Data Actually Travels**
- [3.1 Two Communication Models](#31-two-communication-models)
- [3.2 Why Kubernetes Changes Everything](#32-why-kubernetes-changes-everything)
- [3.3 Service Discovery](#33-service-discovery)
- [3.4 Exporters and Metric Producers](#34-exporters-and-metric-producers)
- [3.5 What Exactly Is a Metric?](#35-what-exactly-is-a-metric)
- [3.6 Time-Series Databases](#36-time-series-databases)

**Part 4: Prometheus as an Implementation**
- [4.1 Putting Prometheus Into the Architecture](#41-putting-prometheus-into-the-architecture)
- [4.2 The Major Components](#42-the-major-components)
- [4.3 The Pull Model, Made Real](#43-the-pull-model-made-real)
- [4.4 Storage](#44-storage)
- [4.5 PromQL](#45-promql)
- [4.6 Alerting and Alertmanager](#46-alerting-and-alertmanager)
- [4.7 Grafana](#47-grafana)
- [4.8 The Complete Architecture](#48-the-complete-architecture)

---
---

# Part 1: Why Monitoring Exists

## 1.1 The Blindness Problem

Imagine you are the CTO of a large streaming platform. You have 20,000 containers running across hundreds of Kubernetes nodes. Everything is working.

Now suddenly customers start complaining: videos are buffering.

What do you do?

You do not know which service failed. Which pod failed. Whether CPU is high. Whether memory is exhausted. Whether the database is slow. Whether the network is dropping packets.

You are blind.

That is the biggest problem, and monitoring exists to remove that blindness.

Monitoring answers one simple question:

> **What is happening inside my system right now?**

Monitoring is observation.

---

## 1.2 Monitoring vs Alerting

Monitoring only watches. Alerting decides when humans should be disturbed.

That is a huge difference, and it is worth being precise about.

Monitoring keeps recording CPU usage every 15 seconds. It may record 20%, 25%, 35%, 40%, 55%. Nothing happens. It just records.

Suddenly CPU becomes 98%. Monitoring simply records 98%. It does not care.

Alerting is what says: wait, this crossed the threshold, wake somebody up.

> **Monitoring collects. Alerting reacts.**
>
> Monitoring tells you what is happening. Alerting tells you something bad is happening, please act.

There is a second reason these are separate systems, and it is the one people miss.

**Monitoring stores history. Alerting makes decisions.**

You can ask a monitoring system "what happened yesterday at 3 PM?" and get an answer. Alerting cannot answer that. It only knows that a rule fired. Different jobs, different data, different systems.

---

## 1.3 Monitoring Starts Before Failure

Many beginners think monitoring starts after failure.

No. Monitoring starts before failure. In fact, the entire goal of monitoring is to prevent failures.

This also explains the timing difference between the two systems:

**Monitoring is proactive.** It continuously collects data whether or not anything is wrong.

**Alerting is reactive.** It sits and waits for a rule to be violated.

---

## 1.4 Two Types of Observation

Monitoring generally observes two very different things, and confusing them is a common mistake.

**Infrastructure** answers questions like: Is the VM alive? What is the CPU usage? Memory? Disk? Network? Is the node healthy? How many containers are running?

**Application** answers questions like: How many requests? What is the response time? How many login failures? Payment success rate? Orders processed? Error rate?

> **Infrastructure tells you the server is healthy. Application tells you the customers are unhappy.**

Those are very different statements, and both can be true at the same time. Every node green, every pod running, and checkout still failing for every customer. If you only watch infrastructure, you will not see it.

---

## 1.5 Monitoring vs Observability

Monitoring answers "what happened." Observability answers "why did it happen."

This is the modern evolution, and it is easiest to see through an example you already know.

With CloudWatch, you set up an alarm. Say CPU above 90 percent, or 5xx errors above 5 percent. The alarm fires. Good, now you know something is broken.

But the alarm itself does not tell you the reason. Was it a bad deployment? A slow downstream API? A database connection pool exhausted? A noisy neighbour pod on the same node?

That investigation, the "why," is observability.

Note carefully that monitoring is not replaced by observability. Monitoring is one important part of it.

| | Question answered | Behaviour |
|---|---|---|
| **Monitoring** | What is happening? | Continuously measures system health |
| **Alerting** | Should someone act? | Notifies when predefined conditions are violated |
| **Observability** | Why did it happen? | Correlates metrics, logs and traces to find root cause |

---

## 1.6 The Three Pillars

Observability is built on three major data sources.

### Metrics

Numbers collected over time. CPU usage, memory usage, requests per second, response time, error rate.

Metrics answer **"how much?"**

### Logs

Detailed records of events. For example: user Rahul logged in. Payment request received. Database connection failed. Order ID 12345 created.

Logs answer **"what exactly happened?"**

### Traces

This is the most powerful concept in microservices, and the hardest to appreciate until you see it.

Imagine a customer places an order. The request travels like this:

```
Frontend -> API Gateway -> Order Service -> Inventory Service -> Payment Service -> Notification Service
```

The whole thing took 4 seconds. Monitoring tells you "latency is high." That is all it can tell you.

A trace follows that single request across every service and measures how long it spent in each one:

```
API Gateway            5 ms
Order Service         20 ms
Inventory Service     15 ms
Payment Service    4,000 ms
Notification Service  10 ms
```

Immediately you know the Payment Service is the bottleneck.

Without traces, you would only know the request took 4 seconds. With traces, you know exactly where those 4 seconds were spent.

Traces answer **"where did the time go?"**

---

## 1.7 A Real Kubernetes Example

Let us put all of it together.

You deploy an e-commerce application. It has a frontend, an API gateway, a product service, an order service, a payment service, PostgreSQL and Redis.

**Monitoring** keeps watching, every few seconds: pod CPU, pod memory, restarts, API requests, error rate, database latency, queue size, node utilisation.

Nothing is sent to any human. It is just recording.

Now the payment service starts returning HTTP 500 errors.

Monitoring records 500, 500, 500. Still nothing sent to humans.

**Alerting** evaluates its rule: if more than 5 percent of requests fail for 5 minutes, notify. The rule becomes true. It sends: *payment service unhealthy*.

Now a human is awake. They open the dashboard, see the error rate climbing, pull the logs for that window, and follow a trace through the payment path.

That last part, the investigation, is **observability**.

---
---

# Part 2: The Generic Monitoring Architecture

## 2.1 The Question Nobody Asks

We have covered why monitoring exists, and how it differs from alerting and observability.

Now the next natural question. **How does monitoring actually happen?**

Think about it. Suppose I ask you: what is the CPU utilisation of Pod A?

How do you know?

- Where did that number come from?
- Who measured it?
- Who stored it?
- Who displayed it?
- Who generated the alert?

That is the architecture we need to understand. And we are going to build it without naming a single product.

### Start outside Kubernetes

Forget Kubernetes for five minutes. Imagine you run the streaming platform's operations floor on IPL final night.

There are 500 CDN edge servers spread across the country. Each one has its own vitals: request rate, cache hit ratio, bandwidth out, error rate.

**Question: how does the operations engineer know the health of all 500?**

Does the engineer log into every server every minute? No. That does not scale past about three servers.

Instead, each edge server runs an agent that continuously measures its own vitals. Those agents report to a central system. The engineers watch one big wall dashboard. If any server's error rate crosses a line, an alarm goes off.

Now replace the pieces:

| Operations floor | Kubernetes |
|---|---|
| CDN edge server | Kubernetes Pod |
| Operations engineer | DevOps engineer |
| The whole CDN fleet | Kubernetes cluster |
| Central monitoring station | Monitoring system |

Exactly the same architecture.

---

## 2.2 Every Monitoring System Has Four Jobs

This is one of the most important concepts in monitoring.

It does not matter whether you are using AWS CloudWatch, Azure Monitor, Datadog, New Relic, Prometheus, Dynatrace or Grafana Cloud. Every one of them performs the same four fundamental jobs.

### Job 1: Collect

Somebody has to gather the information. CPU usage, memory usage, disk usage, number of requests, pod restart count, API latency.

Somebody must measure these values. Without collection, monitoring is impossible.

### Job 2: Store

Once you collect CPU usage, where do you keep it? Throw it away?

No. You store it:

```
10:00   CPU = 35%
10:01   CPU = 42%
10:02   CPU = 39%
```

Now you can answer "what happened during the last hour?"

Storage gives you history. Without storage, you only know the current state, and the current state is almost never enough.

### Job 3: Analyze

Raw numbers do not help much on their own. The monitoring system now starts asking questions.

Is CPU above 90 percent? Is memory continuously increasing? Is the error rate rising? Is this pod restarting every minute? Is the response time getting slower?

This is where intelligence begins. You are no longer collecting data. You are interpreting it.

### Job 4: Present

Finally, humans need to understand all of it. Nobody wants to read millions of numbers.

So you build dashboards. Graphs. Heat maps. Trend lines.

Now the entire system becomes understandable at a glance.

**Notice something.** Nowhere have we mentioned Prometheus. These four jobs exist in every monitoring platform ever built. Prometheus is just one implementation of them.

---

## 2.3 The Six Actors

Every monitoring architecture has the same set of actors. Think of them as characters in a film.

### Actor 1: The Target

A target is simply the thing you are monitoring.

A Linux server. An EC2 instance. A Kubernetes node. A pod. A container. A database. NGINX, Redis, PostgreSQL.

If it generates useful information, it can become a monitoring target.

### Actor 2: The Metric Producer

Here is an important question. Can a monitoring system reach directly into a container and calculate CPU?

No. It cannot.

The application or the operating system already knows those values and has to expose them. Something must produce the metrics.

A Linux server exposes CPU, memory, disk, network. A Kubernetes API exposes nodes, pods, namespaces, deployments. An application exposes HTTP requests, login count, payment success, error count.

Whatever component exposes those values is the metric producer.

### Actor 3: The Collector

Now imagine you have 200 nodes, 3,000 pods and 100 databases.

Somebody has to visit all of them and gather the metrics. That is the collector's job.

Think of a census officer going house to house. The collector continuously gathers data from every target.

### Actor 4: Storage

The collector cannot hold millions of measurements in memory forever. So it writes them down.

Storage is simply historical memory. Later you will learn that this is a specialised kind of database, optimised for measurements over time. For now, that is enough.

### Actor 5: Visualization

Humans do not consume raw data. They consume dashboards.

That is why visualization exists. It turns millions of measurements into something a person can understand in two seconds.

### Actor 6: Notification

Now suppose CPU reaches 98 percent. The monitoring system already knows. But the humans do not.

Somebody has to tell them. That is the notification layer. Email, Slack, Microsoft Teams, PagerDuty, SMS, a phone call. Whatever the organisation uses.

---

## 2.4 The Generic Architecture

Now, for the first time, we can draw the complete picture.

```
   Application / Kubernetes / Database
                 |
                 |  generates metrics
                 v
     Metric Producer / Exporter
                 |
                 |  exposes metrics
                 v
       Monitoring Collector
                 |
                 |  collects and stores
                 v
        Time-Series Storage
                 |
                 +--------------------> Dashboard
                 |
                 +--------------------> Alert Engine
                                             |
                                             v
                                  Email / Slack / Teams
```

Notice that there are deliberately no product names in this diagram.

This architecture applies whether you are using Prometheus, CloudWatch, Azure Monitor, Datadog, New Relic, Dynatrace or Splunk Observability.

> **The products change. The architecture does not.**

---

## 2.5 Bringing Kubernetes Back

Now picture your EKS cluster. Inside it: 3 worker nodes, 150 pods, 25 deployments, 15 services, an ingress, PostgreSQL, Redis, RabbitMQ.

Each of these produces a different kind of metric. Your monitoring system becomes a central observer, continuously asking:

- Node 1, what is your CPU?
- Pod `payment-service`, how much memory are you using?
- PostgreSQL, how many active connections do you have?
- NGINX ingress, how many requests did you receive?
- Kubernetes API server, are you healthy?

Every few seconds, it collects the answers, stores them, analyses them and visualises them.

The foundation is now solid. Next we ask how those questions actually get asked.

---
---

# Part 3: How Data Actually Travels

## 3.1 Two Communication Models

Now comes the most important architectural question. **How does data actually travel?**

Imagine you are monitoring an EKS cluster with 5 worker nodes, 250 pods, 40 deployments, Redis, PostgreSQL, NGINX, Java applications and Python applications.

Who talks to whom?

### Start with a story

Imagine you are the principal of a school with 2,000 students. Every morning you want attendance. How can you collect it?

**Option 1.** You personally go to every classroom. Class 1, class 2, class 3, collecting attendance.

**Option 2.** Every teacher emails you the attendance every morning.

**Option 3.** Each classroom has an electronic system, and you open one dashboard that fetches everything automatically.

Exactly the same problem exists in monitoring. The monitoring system wants information from hundreds of systems. How should it communicate?

There are only two fundamental answers. Everything eventually falls into one of them.

### Model 1: Pull

The monitoring server goes and asks every target.

Think of a teacher taking attendance. The teacher asks "Rahul?" and gets "present." The teacher initiates the conversation. The students do not.

In monitoring, the collector asks:

- Node 1, give me CPU
- Pod 35, give me memory
- Database, give me active connections

The collector initiates. This is the **pull model**.

### Model 2: Push

Now reverse it.

Every classroom sends attendance to the principal. The principal never asks. Each classroom simply says "today's attendance is 38."

In monitoring, every application sends its metrics to the monitoring server. The application initiates the communication. This is the **push model**.

### Which is better?

Stop here and think about it before reading on.

> **If you had 5,000 Kubernetes pods that are constantly being created and deleted, which communication model would you prefer?**

There are good arguments on both sides, and that is exactly the point. The answer depends entirely on the environment. Which brings us to the next question.

---

## 3.2 Why Kubernetes Changes Everything

Traditional servers are stable. Kubernetes is not.

Pods are born. Pods die. Pods move. IP addresses change. Autoscaling happens. Deployments happen. Nodes disappear.

Nothing is permanent.

Compare the two directly:

**Traditional infrastructure**

```
Server A    IP: 10.0.1.10
Server B    IP: 10.0.1.11
Server C    IP: 10.0.1.12
```

These servers may exist for years. Easy to monitor. Write the addresses in a file once and forget about it.

**Kubernetes**

```
payment-abc123    IP: 10.244.1.15
        |
        |   pod crashes
        v
payment-xyz789    IP: 10.244.3.28
```

Same application. Different pod. Different IP.

So here is the new challenge. Your payment pod dies. A new payment pod is created. Its IP has changed.

**How does the monitoring system know where the new pod is?**

Nobody is going to manually update a configuration file. Everything must happen automatically.

Which raises the question that leads to the next concept: how does the monitoring server even know a new pod exists?

---

## 3.3 Service Discovery

Monitoring has two jobs: **find the target**, and **collect the metrics**.

People usually focus on step two. But if you cannot find the target, step two is impossible.

So before collecting any data, a monitoring system must first answer:

- Which pods exist?
- Which nodes exist?
- Which services exist?
- Which of them should I be monitoring?

That is the purpose of service discovery.

### The Google Maps analogy

Imagine you are a food delivery driver, and your customers keep changing houses every five minutes. Memorising addresses is impossible.

Instead, Google Maps always tells you the latest location.

Service discovery plays the same role. It continuously tells the monitoring system: a new pod has appeared, this pod has disappeared, this service has moved, these endpoints are now available.

Without service discovery, monitoring a Kubernetes cluster would be very close to impossible.

### Where does the information come from?

Now the important question. **Who knows that a new pod was created?**

The **Kubernetes API server**.

The API server is the source of truth for the cluster. It knows every node, pod, service, deployment, namespace and endpoint.

So instead of guessing, or maintaining a list by hand, the monitoring system simply asks the API server.

```
   Kubernetes API Server
            |
            |  "here are all the pods"
            v
    Service Discovery
            |
            |  "monitor these targets"
            v
   Monitoring Collector
            |
            v
      Collect Metrics
```

### The full journey

Putting the whole flow together, from nothing to a fired alert:

```
   Monitoring Server
          |
          v
   Find the Target          <- service discovery
          |
          v
   Connect to Target
          |
          v
   Request Metrics
          |
          v
   Receive Metrics
          |
          v
   Store Metrics
          |
          v
   Analyze Metrics
          |
          v
   Display Metrics
          |
          v
   Trigger Alert
```

---

## 3.4 Exporters and Metric Producers

We have found the pod. Now, how do we know its CPU?

Ask the question directly. **Can a monitoring system calculate Linux CPU by itself?**

No. Linux already knows its own CPU. The monitoring system simply asks for it.

So somebody has to expose that information in a standard format. That somebody is an **exporter**.

This is not a Prometheus concept. Every monitoring system needs some component to expose metrics in a standard way. The names differ. The role does not.

The main ones you will meet:

| Exporter | What it exposes |
|---|---|
| **Node exporter** | Node level: CPU, memory, disk, network |
| **kube-state-metrics** | Kubernetes object state: pod phase, deployment replicas, job status |
| **cAdvisor** | Container level resource usage, built into the kubelet |
| **Application `/metrics`** | Whatever your own code chooses to expose |

That distinction between node exporter and kube-state-metrics matters and is often asked about.

Node exporter tells you about the **machine**. kube-state-metrics tells you about **what the Kubernetes API believes**, such as how many replicas a deployment wants versus how many it has. One is hardware, one is desired state.

---

## 3.5 What Exactly Is a Metric?

Not every metric behaves the same way, and this is why monitoring systems have different metric types.

Consider three different things you might measure:

**CPU, memory, temperature.** These go up and down freely.

**Login count, request count, orders processed.** These only ever increase.

**Latency, request duration.** A single number is meaningless here. You need a statistical summary, because the average hides everything that matters.

Those three behaviours give you the four metric types:

| Type | Behaviour | Example |
|---|---|---|
| **Gauge** | Goes up and down | Memory in use, temperature, queue depth |
| **Counter** | Only increases, resets to zero on restart | Total requests, total errors, orders processed |
| **Histogram** | Buckets observations into ranges | Request duration distribution |
| **Summary** | Calculates quantiles at the source | 95th percentile latency |

Two consequences worth carrying forward.

A counter's raw value is nearly meaningless. "Total requests since the process started is 4,829,113" tells you almost nothing. What you care about is how fast it is climbing. This is why counters are almost always converted into a rate before being used.

And an average latency of 200 milliseconds can hide the fact that one percent of your users are waiting nine seconds. That is what histograms and summaries exist to reveal.

---

## 3.6 Time-Series Databases

Now the last question before we can talk about a real product. Where are all these millions of metrics stored?

Every metric measurement has three parts: a **name**, a **value** and a **timestamp**.

```
10:00   CPU = 32%
10:15   CPU = 41%
10:30   CPU = 37%
```

Look at that shape carefully. The same name, over and over, with a slightly different number each time, thousands of times an hour, forever.

A relational database is not optimised for that pattern at all. It is designed for rows that are inserted once and updated occasionally, joined across tables, and queried by key.

A **time-series database** is designed for exactly this shape. Append-only writes. Heavy compression, because consecutive values are usually similar. Fast range queries over time. Automatic expiry of old data.

That is why monitoring systems do not use MySQL.

---
---

# Part 4: Prometheus as an Implementation

We have built the foundation: **why, what, how, communication, service discovery, metrics, storage.**

Only now does it make sense to introduce a product. And when the Prometheus architecture appears, it should not look like a diagram of unfamiliar boxes. It should look obvious.

Of course there is a collector. Something has to gather the data.
Of course there is service discovery. Pods keep changing.
Of course there are exporters. Something has to expose the metrics.

That is the difference between learning a product and understanding an engineering system.

---

## 4.1 Putting Prometheus Into the Architecture

Bring back the generic architecture and drop a name into it.

```
              Kubernetes / Applications
                        |
                  Metrics / Targets
                        |
                        v
              +-------------------+
              |    PROMETHEUS     |
              |                   |
              |   Collect         |
              |   Store           |
              |   Query           |
              |   Evaluate        |
              +---------+---------+
                        |
            +-----------+-----------+
            |                       |
            v                       v
        Grafana                Alertmanager
      Visualization            Notifications
```

Everything we discussed earlier now has a concrete implementation. Prometheus is our monitoring engine.

---

## 4.2 The Major Components

### Prometheus Server

The heart of the system. It discovers targets, scrapes metrics, stores them, allows us to query them, and evaluates alerting rules.

### Service Discovery

We just learned this concept. Prometheus needs to know who to monitor.

In Kubernetes, Prometheus talks to the Kubernetes API and dynamically discovers pods, services, nodes and endpoints. The previous lesson plugs directly into this component.

### Exporters and Application Metrics

Once Prometheus finds a target, the metric itself still has to come from somewhere.

```
   Node Exporter          ->  Node CPU / memory / disk
   kube-state-metrics     ->  Kubernetes object state
   cAdvisor               ->  Container resource usage
   Application /metrics   ->  Your own application metrics
```

---

## 4.3 The Pull Model, Made Real

Our earlier pull versus push discussion now becomes concrete. Prometheus works like this:

```
        Prometheus
             |
          HTTP GET
             |
             v
    http://target/metrics
             |
             v
      Metrics Response
```

Prometheus essentially says: give me your current metrics. The target responds.

That single exchange is called a **scrape**.

---

## 4.4 Storage

Prometheus receives a value and a time, over and over:

```
   CPU = 35%    timestamp 10:00
   CPU = 42%    timestamp 10:01
   CPU = 39%    timestamp 10:02
```

It stores this as time-series data.

So the concept from section 3.6 now has a real implementation: **Prometheus ships with its own local time-series database.** No separate database to install, no connection string to configure.

---

## 4.5 PromQL

Now a new question appears. Prometheus is holding millions of metrics. How do we ask it anything?

That is **PromQL**, the Prometheus Query Language.

```
   rate(http_requests_total[5m])
```

PromQL lets us query and calculate against the stored metrics. We are not going deep here. For now, just establish its purpose: it is how every question gets asked, whether by a human, a dashboard, or an alerting rule.

---

## 4.6 Alerting and Alertmanager

Now connect back to Part 1, where we separated monitoring from alerting.

Prometheus can evaluate rules such as:

```
   CPU > 90%
   HTTP error rate > 5%
```

When the condition becomes true, Prometheus generates an alert. It then hands that alert to a separate component:

```
      Prometheus
           |
           |  alert
           v
      Alertmanager
           |
           +--- Slack
           +--- Email
           +--- PagerDuty
           +--- Teams
```

The distinction is important and it is exactly the one we drew in Part 1:

> **Prometheus detects the condition. Alertmanager handles the notification.**

This is why grouping, silencing and routing all live in Alertmanager and not in Prometheus. Prometheus knows about data. Alertmanager knows about people and schedules.

---

## 4.7 Grafana

Finally, visualization.

```
        Prometheus
            |
        Query / PromQL
            |
            v
         Grafana
            |
        Dashboards
            |
    +-------+-------+
    |       |       |
   CPU   Memory  Requests
```

The most important sentence about Grafana:

> **Prometheus is the monitoring and data engine. Grafana is the visualization layer.**

Grafana does not collect Kubernetes metrics itself. It stores nothing. It queries Prometheus and draws the answers.

---

## 4.8 The Complete Architecture

Now the whole picture.

```
                         EKS CLUSTER
   +------------------------------------------------+
   |                                                |
   |   Kubernetes API Server                        |
   |            |                                   |
   |            |  service discovery                |
   |            v                                   |
   |    +-----------------+                         |
   |    |  Pods / Nodes   |                         |
   |    |  Services       |                         |
   |    +--------+--------+                         |
   |             |                                  |
   |         /metrics                               |
   |             |                                  |
   |    +--------v--------+                         |
   |    |    Exporters    |                         |
   |    |  / App Metrics  |                         |
   |    +--------+--------+                         |
   |             |                                  |
   +-------------+----------------------------------+
                 |
            HTTP scrape
                 |
                 v
        +-------------------+
        |    PROMETHEUS     |
        |                   |
        |  Service Discovery|
        |  Scraping         |
        |  TSDB             |
        |  PromQL           |
        |  Alert Rules      |
        +---------+---------+
                  |
          +-------+--------+
          |                |
          v                v
   +-------------+  +----------------+
   |   Grafana   |  |  Alertmanager  |
   |             |  |                |
   |  Dashboards |  |  Notifications |
   +-------------+  +--------+-------+
                             |
                             v
                    Slack / Email /
                    PagerDuty / Teams
```

And this is the whole story in one sentence:

> **The Kubernetes API discovers the targets. Prometheus scrapes their metrics and stores them. PromQL queries them. Grafana visualises them. Alertmanager handles the notifications.**

---

## Summary: The Path We Took

| Level | Question | Answer |
|---|---|---|
| 0 | Why does monitoring exist? | To remove blindness |
| 0 | How is alerting different? | Monitoring collects, alerting reacts |
| 0 | How is observability different? | Monitoring says what, observability says why |
| 1 | What does every monitoring system do? | Collect, store, analyze, present |
| 1 | Who are the actors? | Target, producer, collector, storage, visualization, notification |
| 2 | How does data travel? | Pull or push |
| 2 | How do you find targets that keep changing? | Service discovery, via the Kubernetes API |
| 2 | Who exposes the metrics? | Exporters |
| 2 | What kinds of metrics are there? | Counter, gauge, histogram, summary |
| 2 | Where are they stored? | A time-series database |
| 3 | What implements all of this? | Prometheus, Grafana, Alertmanager |

Every box in the final architecture diagram exists because of a question we asked before the box appeared. That is the point.
