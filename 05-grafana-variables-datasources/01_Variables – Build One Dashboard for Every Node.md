### Section 1: Variables – Build One Dashboard for Every Node


### Why Do We Need Variables?

Let's start with a problem.

In our previous session, we built a dashboard that displayed CPU, Memory, Disk, and Pod information for the entire cluster. That worked well because our K3s cluster is small.

Now imagine a production environment with:

* 50 worker nodes

* 200 namespaces

* Thousands of pods

If every panel shows data for everything simultaneously, the dashboard becomes difficult to read.

Instead of creating separate dashboards like:

* Node-1 Dashboard

* Node-2 Dashboard

* Production Dashboard

* Development Dashboard

we should build one dashboard that changes automatically based on what we select.

This is exactly what Grafana Variables solve.

### Google Maps Analogy

Think of a printed world map.

Everything is visible, but finding your street is difficult.

Now think about Google Maps.

You type a location, and the entire view automatically focuses on that place.

Grafana Variables work the same way.

Instead of changing the dashboard manually, we select a value from a dropdown, and every panel automatically updates.

![](blob\:https://chatgpt.com/b583c7cf-5a96-4639-83fc-f6015c5b69fc)

### How Variables Work Internally

A Grafana variable is simply a placeholder.

For example:

$node

When the dashboard loads, Grafana replaces `$node` with whatever value we choose.

Let's see that transformation.

### Before selecting a node

promql

rate(node_cpu_seconds_total{instance="$node", mode="idle"}[5m])

At this point, `$node` is only a placeholder.

### After selecting `node-1:9100`

Grafana automatically converts the query into:

promql

rate(node_cpu_seconds_total{instance="node-1:9100", mode="idle"}[5m])

Notice that Prometheus never sees `$node`.

Grafana replaces it before sending the query.

![](blob\:https://chatgpt.com/ea83e21c-3e6b-43b6-bab4-8c3a884e6279)

This substitution happens for every panel that uses that variable.

### Types of Variables

Grafana provides several types of variables. We don't use all of them every day, but it's important to know where each one fits.

<img width="1090" height="557" alt="image" src="https://github.com/user-attachments/assets/d963ccf1-d855-460b-ba00-b115d98462b8" />


For today's lab, we'll use three of them:

* Query Variable

* Interval Variable

* Chained Query Variable

### Lab 1 – Create a Node Variable

Our goal is simple.

Instead of hardcoding a node name inside every query, we'll create a dropdown that automatically lists every node from Prometheus.

### Step 1 – Open Dashboard Settings

Open the dashboard we created previously.

Navigate to:

> Dashboard → Settings (Gear Icon)

Then open:

> Variables → Add Variable

![How to Create Dynamic Grafana Templates with Chained Variables | SigNoz](https://images.openai.com/static-rsc-4/XhTZhRTWKU-YzdOY-PpjhosbnHKbf3lbnFGty5SB8HsbYLNL7Yn8B3-payOp9Acqaz1765nDiz1DQfNKwoiIOKq88kA_UuZdhZ5_xm4hnT-MOv29BQvtFd8IgSv9a6WUqwiq9N2uFUdHobEsdV6EaAOxj3hV4zPp2t9X3LewCOY?purpose=inline)

A new variable configuration page opens.

### Step 2 – Configure the Variable

We'll fill each field one by one.

|
Field

|

Value

|
| --- | --- |
|

Type

|

Query

|
|

Name

|

`node`

|
|

Label

|

Node

|
|

Data Source

|

Prometheus

|

The name becomes the variable we use later.

$node

The label is simply what appears in the dashboard dropdown.

### Step 3 – Write the Query

This is the most important part.

Instead of typing node names manually, we'll ask Prometheus to discover them.

Write this query.

promql

label_values(node_cpu_seconds_total, instance)

Let's understand it.

Start with the metric.

promql

node_cpu_seconds_total

This metric exists for every node.

Now wrap it with:

promql

label_values(...)

`label_values()` extracts unique values from a label.

Our label is:

instance

So the complete query becomes:

promql

label_values(node_cpu_seconds_total, instance)

Expected preview:

node-1:9100

node-2:9100

node-3:9100

If you're using K3s with a single node, you'll likely see only one value.

### Step 4 – Configure Refresh

Set:

|
Setting

|

Value

|
| --- | --- |
|

Refresh

|

On Time Range Change

|
|

Multi-value

|

OFF

|
|

Include All

|

ON

|
|

All Value

|

`.+`

|

Why use `.+`?

This is a regular expression that matches everything.

When "All" is selected, Grafana substitutes `.+`, allowing Prometheus to match every node.

Finally click:

Update → Apply

A new dropdown appears at the top of the dashboard.

![Docker Container Monitoring with cAdvisor Node Exporter Prometheus and Grafana - Virtualization Howto](https://images.openai.com/static-rsc-4/BZ00OF_5WGgNe-HOnfnybTg1IsGjS52U1zpNKAZ8bKpy0kMDZaHcPAV2wklWQ7i5QKe5Uqfco129dhYHkWGEYmydqeAl-7vsQolQQdgYeu5oDFbks4K16dyM8AQZdM4mHkEHPJ31RP5YWWbCuip8hVvfOPS7i0p3zCtu9NFkWJo?purpose=inline)

### Lab 2 – Update an Existing Panel

Now let's make our CPU panel use the new variable.

Open the CPU panel.

Select Edit.

We'll rebuild the query instead of pasting it.

### Start with the metric

promql

node_cpu_seconds_total

Now filter by instance.

promql

node_cpu_seconds_total{instance="$node"}

Now select only idle CPU.

promql

node_cpu_seconds_total{instance="$node", mode="idle"}

Finally calculate the rate.

promql

rate(node_cpu_seconds_total{instance="$node", mode="idle"}[5m])

Save the panel.

Now change the dropdown between nodes.

Every panel using `$node` automatically updates.

This is the first time our dashboard becomes dynamic.

### What Changed?

Earlier, every query was tied to one fixed value.

Now the dashboard behaves like an application.

One dropdown controls every visualization.

This is exactly how production dashboards are designed—build once, filter everywhere.

### Quick Check

After completing this lab, you should have:

* A Node dropdown at the top of the dashboard.

* Values automatically fetched from Prometheus.

* CPU panel updating when the selected node changes.

* One dashboard that works for every node instead of maintaining multiple copies.

In the next topic, we'll add a Namespace variable, enable multi-selection, and learn why `=~` becomes mandatory when multiple values are selected.
