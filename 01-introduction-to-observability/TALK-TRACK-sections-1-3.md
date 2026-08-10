# Talk Track: Sections 1 to 3

Spoken script for the 35 slide deck. Read it once before the session, glance at it during.

Written the way you would actually say it. Short sentences. Say it in your own words once you know the shape.

---

## Timing

| Part | Slides | Minutes |
|---|---|---|
| Opening | 1 | 1 |
| Section 1: What is Observability | 2 to 13 | 8 |
| Section 2: Prometheus Architecture | 14 to 28 | 15 |
| Section 3: APT Installation | 29 to 35 | 5 |
| **Total** | | **29** |

That leaves roughly two hours for Section 4 onward, which is where it is needed.

Markers used below:

- **PAUSE** stop talking, let them read
- **ASK** question to the room, wait for an answer
- **CLICK** advance to the next build slide

---

# Opening

### Slide 1: Title

Today we start observability.

Before we install anything, I want you to understand why this thing exists. If you install Prometheus without knowing what problem it solves, you will just be copying commands.

So the first half hour is concepts. No cluster, no commands. Then we build the whole stack together.

---

# Section 1: What is Observability?

### Slide 2: Section divider

Section one. What is observability, and why does anyone care.

### Slides 3, 4, 5: The 2 AM problem (build)

Picture this. It is two in the morning. Your phone buzzes. Checkout is failing on production. Customers are dropping off.

You are half asleep. What do you do first?

**ASK** Let them answer. Someone will say "check the logs."

Hold that thought.

There are exactly three questions you need to answer. And the order matters more than you think.

**CLICK**

First. What is broken? Not "the site is down." Which component. Which service.

**CLICK**

Second. When did it start? If you can say "it started at 2:14," you have just narrowed your search from a whole day to one minute.

**CLICK**

Third. Why did it break? The actual root cause.

**PAUSE**

Now here is the mistake almost everyone makes. Under pressure, people jump straight to question three. They log into a machine and start reading logs.

That is the slowest possible path.

Think about it. A busy service writes millions of log lines a day. If you do not know which service and which minute, you are reading a phone book looking for a name you do not know.

Answer one and two first, and those millions of lines become a few hundred.

### Slide 6: Monitoring vs Observability

Two words that get used interchangeably. They are not the same thing, and interviewers love this question.

Monitoring answers questions you decided to ask in advance. You built a dashboard. CPU, memory, request rate. CPU crosses eighty percent, you get paged. That is monitoring. A fixed set of questions, asked over and over.

Observability is different. It means you can ask questions you never planned for.

At 2 AM you want to ask something like: which pods, in which namespace, on which node, started climbing at the exact moment checkout got slow?

Nobody built a dashboard for that. Nobody could have. You did not know you needed it until thirty seconds ago.

Now, the simple test at the bottom of the slide.

**ASK** How many of you have added a log line to production just to debug something? Show of hands.

Most hands go up.

That is the gap. You had to change the system in order to ask it a question. That is the opposite of observability.

Observability means the data was already there before you knew you needed it.

And to be clear, monitoring is not wrong. Monitoring is part of observability. You need both. Monitoring tells you something is wrong. Observability tells you what to do about it.

### Slides 7, 8, 9: The three pillars (build)

Observability stands on three kinds of data.

**CLICK**

Metrics. Numbers over time. A value, a timestamp, some labels. CPU is at 0.87 at 2:14:30.

The important thing about metrics is that they are cheap. A number is a few bytes. So you can collect them for everything, all the time, and keep them for months.

What metrics cannot do is tell you about one specific user. To make a number, you have already thrown away the individual events.

**CLICK**

Logs. One line for each thing that happened. This user, this order, this error, this exact second.

Logs have the detail that metrics threw away. But they are expensive. A busy service writes gigabytes an hour. You cannot keep them as long, and searching them across a wide time range is slow.

That is exactly why you narrow the window with metrics first.

**CLICK**

Traces. One request, followed across every service it touched.

In a monolith, a slow request is a slow function. Easy. In microservices, one checkout call might touch twelve services. The user waits three seconds. Which of the twelve caused it? That is what a trace answers.

**PAUSE**

Today we do the first one only. Metrics. Prometheus and Grafana.

Be careful about this in interviews. "We installed Prometheus" is not the same as "we have observability." One pillar is a good foundation. It is not the whole story.

### Slides 10, 11, 12: Hotstar analogy (build)

Let me make this concrete with something you have all seen.

IPL final night. Four crore people streaming at the same time. You are sitting in the Hotstar operations room.

**CLICK**

Look at the wall. Big dashboard. Concurrent viewers, four point one crore. Buffering ratio, zero point three percent. CDN egress, twelve terabits per second.

These numbers refresh every few seconds, whether anything is wrong or not. That is metrics.

Now at 21:14, buffering jumps from zero point three percent to four percent.

You now know what broke, and when. Two questions answered.

**CLICK**

Next, you open the event stream. Millions of lines scrolling past. One line per thing that happened.

You filter to 21:14, and a pattern jumps out. All these users dropping quality, all of them on the same CDN edge. Mumbai three.

Now you know who is affected, and where. That is logs.

**CLICK**

Last step. You pick one affected user and follow their play request through every hop. Phone, CDN edge, auth service, DRM licence server, manifest service.

Twelve milliseconds, thirty five, eighteen, then nine hundred, then twenty two.

There it is. The DRM licence server is adding nine hundred milliseconds.

That is why. That is a trace.

**PAUSE**

Three tools, three questions, one incident. The dashboard found the spike. The logs found the blast radius. The trace found the root cause.

And notice the order was not optional. If you had started with traces, you would be picking one request out of four crore at random and hoping it was a bad one.

### Slide 13: Detect, Scope, Diagnose

So remember it like this.

Metrics to detect. Logs to scope. Traces to diagnose.

Whenever someone asks you which tool to reach for, this is the answer. Always narrow the window first.

---

# Section 2: Prometheus Architecture

### Slide 14: Section divider

Section two. How Prometheus actually works.

There is one design decision in Prometheus that explains almost everything about its behaviour. Including some things that look strange at first.

### Slide 15: Push vs Pull

Most monitoring you have used works like the left side. The application holds a library, and every few seconds it sends data out to a collector. StatsD works this way. Most SaaS agents work this way.

Prometheus does the opposite.

Your application does not send anything. It just exposes an HTTP endpoint, usually at slash metrics, that returns its current numbers as plain text. It sits there. It waits.

Prometheus reaches out on a schedule and collects them.

Look at the box at the bottom. Your application has no queue. No retry logic. No backpressure handling. It does not even know where Prometheus is running.

It answers an HTTP request. That is the entire integration.

This looks like a small technical detail. It is not. Everything else follows from it.

### Slide 16: Telecom NOC, the push problem

Let me give you an analogy from telecom.

A mobile operator runs thousands of cell towers. The network operations centre needs to know the state of every one.

Say we do it with push. Every tower reports in whenever it wants. Two problems show up immediately.

First one. A tower stops reporting.

**ASK** What does that silence mean?

Did the tower die? Did the network link die? Or is the tower perfectly fine and just its reporting process crashed?

You cannot tell. And at 2 AM, "I cannot tell" is expensive.

Second problem. The NOC has no control over its own load. If something big happens and every tower reports at once, the collector gets overwhelmed at exactly the moment you need it most.

### Slide 17: Telecom NOC, the pull solution

Now flip it.

Each tower keeps a live status page. It updates it and does nothing else. The NOC polls every tower on a fixed schedule.

Both problems disappear.

First. The NOC polls a tower and the poll fails. That failure gets written down. This tower did not answer at 09:14:30. That is a fact. A data point. Not an absence of one.

Second. The NOC decides the interval, the timeout, the order. A hundred incidents happening at once does not change how much work the NOC has to do.

**PAUSE**

Prometheus is the NOC. Your pods are the towers.

### Slide 18: The up metric

Now let me make that concrete, because this is the payoff.

Every single time Prometheus scrapes a target, it writes an extra metric called up.

Scrape worked, up equals one. Scrape failed, up equals zero.

The target does not send this. Prometheus generates it.

So think about what that means. "This target is down" is now an ordinary time series. You can graph it. You can query it. You can alert on it. Exactly like CPU or memory.

In a push system, you have to figure out failure from missing data. That is much harder.

Look at the bottom of the slide. Most basic availability alerting in the world is built on that one expression. up equals equals zero.

Remember that one. It comes up in interviews constantly.

### Slide 19: Why pull suits Kubernetes

Four properties, quickly.

One. Failure is a signal, not silence. We just covered that.

Two. Prometheus controls its own load. A thousand pods cannot flood it.

Three, and this is the big one for Kubernetes. Targets are discovered, not configured. Pods come and go constantly with names and IPs you cannot predict. In a push model, every new pod would need to know where the collector is. In pull, Prometheus asks the Kubernetes API what exists right now, and scrapes it. A pod that appears at ten o'clock is being scraped by ten thirty.

Four. Applications stay simple. Just answer an HTTP request.

Now the honest trade-off at the bottom, because pull is not magic.

Pull needs network reachability to every target. And a batch job that runs for five seconds may finish before any scrape happens.

For that case there is a separate component called Pushgateway. The job pushes to it, Prometheus scrapes Pushgateway normally.

Write this down. Interviewers ask about the short-lived batch job on purpose. They ask it to find out whether you learned Prometheus from a tutorial or actually understand it.

### Slides 20 to 23: Core components (build)

Now the pieces.

**CLICK**

Prometheus server. Three jobs, keep them separate in your head.

It scrapes targets on a schedule. It stores what it scrapes in a local time series database. And it evaluates alerting rules against that data.

Note that last one carefully. Prometheus decides whether to alert. It does not decide who to tell.

**CLICK**

Exporters. Most systems do not speak Prometheus format natively. An exporter is a small process that sits next to such a system, reads its state, and republishes it as a slash metrics endpoint.

Three you will see constantly.

node-exporter tells you about the machine. CPU, memory, disk.

kube-state-metrics tells you about Kubernetes objects. How many replicas a deployment wants, how many it has, what phase a pod is in.

**PAUSE**

That distinction is important. node-exporter is about the infrastructure. kube-state-metrics is about what the API server believes. One is hardware, one is desired state. That is an interview question, almost guaranteed.

Third one, blackbox-exporter, probes external URLs from outside.

**CLICK**

Alertmanager. Prometheus fires alerts. Alertmanager decides what happens to them. Grouping related ones together, silencing duplicates, muting during maintenance, and routing to Slack or PagerDuty or email.

**CLICK**

And Grafana. Grafana stores nothing. Zero metrics of its own. It sends PromQL queries to Prometheus and draws the answers.

Every number you see on a Grafana dashboard was fetched from Prometheus when the page loaded.

### Slide 24: One scrape cycle

Let us walk one cycle end to end.

Prometheus looks at its target list, which came from Kubernetes service discovery.

It sends an HTTP GET to slash metrics on each target.

The target responds with plain text. Current values. And notice, no timestamps.

Prometheus attaches the timestamp itself and appends to the database. That is deliberate, so all samples from one scrape share the same consistent time.

It records up equals one, or zero if the scrape failed.

Then it waits for the interval and does it all again. Default is fifteen seconds. We will set thirty.

Now read the line at the bottom.

**PAUSE**

Prometheus only knows what it saw at scrape time. If something spikes and comes back to normal in between two scrapes, Prometheus never sees it.

That is a real limitation. Metrics are samples, not a complete record. This is why you never use metrics to audit individual events.

### Slide 25: The /metrics endpoint

Here is what a metrics endpoint actually looks like. No special protocol. Text over HTTP. You can curl it yourself.

Three things to notice.

HELP and TYPE are metadata. What the metric means, what kind it is.

There are no timestamps in the response. The target does not know or care what time it is.

And the TYPE line has two values here. Counter and gauge.

A counter only goes up, and resets to zero when the process restarts. A gauge moves up and down freely.

Why does this matter? Because a counter's raw value is meaningless on its own. Node CPU seconds total says twelve thousand. So what? What you care about is how fast it is climbing.

That is why nearly every PromQL query you see against a counter is wrapped in rate.

### Slide 26: Time series and labels

A time series is a metric name, plus labels, plus values over time.

The name and labels together are the identity. Change one label value and it is a completely different series with its own separate history.

Look at the second block. Same metric name, http requests total. Three different label sets. So three separate time series.

This is what makes PromQL powerful. You can filter on any label, throw away the ones you do not care about, group by the ones you do. Total requests per service. Error rate per method. Traffic by status code. All from the same data, without deciding any of that in advance.

### Slide 27: Cardinality

Now, the same feature that makes Prometheus powerful is also the fastest way to break it.

Look at the left side. Labels with bounded values. Method has a handful. Status has a few dozen. Service has maybe hundreds. Fine.

Right side. user id. One time series per user. request id. One per request, forever. Email. Millions.

Every unique combination of labels is a separate time series. And Prometheus keeps an index of all of them in memory.

So unbounded labels mean unbounded memory. This is the number one cause of Prometheus falling over in production.

**PAUSE**

The rule at the bottom. Labels are for dimensions you group by. Identity belongs in logs.

If you remember one operational warning from today, make it this one.

### Slide 28: PromQL taster

Last thing in section two. Just enough PromQL to read the queries coming up.

Take the CPU query. Read it inside out.

Innermost, we select the idle time counters.

rate over five minutes turns that counter into a per-second rate.

avg by instance collapses the per-core numbers into one number per node.

And then a hundred minus that, because time not spent idle is time spent busy.

Second query. rate of http requests where status matches five dot dot. The squiggle equals is a regex matcher, so that catches every 5xx.

Two things to carry with you. Counters almost always get wrapped in rate. And the five minutes in brackets is a lookback window, not a filter on time.

We will go much deeper into PromQL later in the course.

---

# Section 3: APT Installation

### Slide 29: Section divider

Section three. And this is the odd one out.

This is the only section today that does not run on Kubernetes. And the only one where we throw away what we build.

### Slide 30: Why bother

Let me tell you why we are doing it.

Section four is fifty minutes. Operator, CRDs, ServiceMonitors, sidecars. A lot of machinery.

And it is completely fair to sit there and think, is all of this really necessary? Cannot we just install Prometheus?

So let us just install Prometheus. Five minutes. Then look at what is missing.

Five minutes here will make the next fifty minutes make sense.

One more thing. I am doing this on a separate plain Ubuntu machine. No kubectl on it. No kubeconfig. No AWS credentials. Nothing.

So when I tell you at the end that this Prometheus cannot see our cluster, that is not me making a point. That is just a fact about the machine.

### Slide 31: What apt gives you

One command. apt install prometheus.

Thirty seconds later, you have a systemd service. It starts at boot, restarts on failure. On this one machine.

You have a config file at etc prometheus prometheus dot yml.

And you have the same web UI on port 9090 that we will see in section four. Same software.

One thing to notice though. The version. We get 2.53, from Ubuntu's community-maintained repository. Upstream Prometheus is on 3.x. So we are a full major version behind, and that is normal for distro packages. They freeze when the Ubuntu release freezes.

And to be fair to it, look at the bottom line. On a handful of VMs with fixed IPs, this is perfectly reasonable. This is why the package exists.

### Slide 32: static_configs

Now open the config file. This is the important slide.

Look at the highlighted word. static underscore configs.

**PAUSE** Give them a few seconds to read it.

Static. Every target Prometheus will ever scrape has to be typed into this file by hand. As a hostname and a port.

Deploy a new application? Edit this file. Add a server? Edit this file. An IP changed? Edit this file. And reload the service every time.

On ten fixed servers, fine. Annoying, but fine.

**ASK** Now think about Kubernetes. What is different?

Let them answer.

Right. Pods are created and destroyed all day long. Their names have random suffixes on the end. Their IPs come from a pool and get reused.

A deployment scaling from three replicas to ten just created seven targets that did not exist one second ago, at addresses nobody could have predicted.

There is no way to write that into a static file. It is not hard. It is impossible.

### Slide 33: One target vs dozens

Let us look at the proof.

In the Prometheus UI, go to Status, then Targets. This page lists everything Prometheus is scraping.

On our apt install, look at it. One target. Prometheus watching itself. That is the whole thing.

Everything else you would ever want to monitor has to be typed in by hand.

Now that is what the same page looks like in section four, after the Helm install. Kubelet, API server, CoreDNS, node-exporter, kube-state-metrics, and more.

Dozens of targets. And I did not configure a single one of them. Prometheus asked the Kubernetes API what existed, and started scraping.

**PAUSE**

Same software. Same web UI. Completely different picture.

That gap is what the Prometheus Operator exists to close. And that is why the next section is worth fifty minutes.

### Slide 34: Four limitations

To summarise what we just proved.

No service discovery. Targets are static text.

Manual configuration lifecycle. Editing a file on one specific machine and reloading a service. No API, no pipeline, no git.

No Kubernetes awareness at all. It cannot see pods, services, namespaces. It has no service account and no route to the API server.

And a single point of failure. One machine, one disk. If it dies, monitoring dies with it and nothing brings it back.

Every one of these gets solved in section four.

Then we purge the packages and terminate that VM. We are done with it.

### Slide 35: Coming up

So. Section four.

One Helm chart gives us the whole stack. Prometheus, the Operator, Grafana, Alertmanager, node-exporter, kube-state-metrics.

Configuration becomes Kubernetes objects you apply with kubectl and store in git, instead of a file you SSH in to edit.

And when we open that Targets page again, it will not have one entry on it.

Let us take a short break, then we move to the cluster.

---

## Notes for delivery

**The three ASK moments matter more than anything else on these slides.** Slide 3 (what do you do first), slide 6 (show of hands on adding log lines), and slide 32 (what is different about Kubernetes). Each one gets the room to reach the conclusion just before you state it, which is worth more than any explanation.

**Slide 18 and slide 32 are the two anchors.** If you are running behind, protect these two and compress elsewhere. The up metric is what makes pull-versus-push concrete. static_configs is what makes the operator necessary.

**Slide 33 needs no explanation.** One target next to dozens. Show it, say one line, move on. The comparison does the work.

**If you are short on time**, the safe cuts are slide 19 (four properties, partly repeats slide 17) and slide 26 (time series and labels, which you will cover again in Section 2 of the course when you do PromQL properly). Do not cut the analogies. They are what people remember a week later.
