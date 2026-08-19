# Topic 8: Variables (Grafana Part 2)

## 1. Context

So far, our dashboard is static.

For example, if we have a CPU panel showing data for `worker-node-1`, what happens when we want to see `worker-node-2`? Do we create another dashboard?

No. Grafana solves this with Variables.

A Variable creates a dynamic dropdown that lets one dashboard display different data without changing the queries manually.

Think of the complete flow:

One Dashboard -> Variable Dropdown -> Select a Node -> All Panels Update

The key takeaway is: Variables make dashboards reusable instead of creating one dashboard per node, namespace, or cluster.

---

## 2. Concept

### Concept 1: What is a Variable?

A Variable is a placeholder that stores a value selected by the user.

For example:

```text
Variable: Node
Value: worker-node-1

```

When the user changes the dropdown from `worker-node-1` to `worker-node-2`, every panel using that variable automatically refreshes.

The important distinction is:

* **Without Variables:** Separate dashboards.
* **With Variables:** One dashboard with a dropdown.

---

### Concept 2: Where Do Variables Come From?

Variables do not invent values. They query the Data Source.

```text
Grafana -> Variable Query -> Prometheus -> List of Nodes -> Dropdown

```

Prometheus provides the available values, and Grafana turns them into a selectable list.

---

## 3. Hands-On Lab

### Lab 1: Create a Variable

From the Grafana UI:

Dashboards -> Settings -> Variables -> Add Variable

Now configure it:

* **Name:** `node` (We will reference this later as `$node`)
* **Type:** Select `Query` (A Query Variable gets its values from Prometheus)
* **Data Source:** Select `Prometheus`

Now we need a query that returns node names.

---

### Lab 2: Variable Query

Enter the following query in the label values input:

`label_values(node_uname_info, instance)`

What does this return?

```text
worker-node-1
worker-node-2
master-node

```

Grafana converts these values into the dropdown list.

The important teaching point is: The variable stores one of these values at a time, not all of them at once.

---

## 4. Internal Working and Syntax

### Concept 3: Using the Variable

Now let us use the variable in a panel.

Suppose our original CPU query looked like this:

```promql
100 - (
  avg by (instance)(
    rate(node_cpu_seconds_total{mode="idle"}[5m])
  ) * 100
)

```

Instead of showing every instance, we can filter it using our variable:

```promql
node_cpu_seconds_total{instance="$node"}

```

Notice `$node`. This is the variable name we created earlier.

Now the execution flow becomes:

Dropdown -> worker-node-1 -> $node -> PromQL -> Prometheus -> Updated Graph

This is why variables are powerful.

---

## 5. Architecture and Value

### Concept 4: Why Variables Matter

Imagine an organization with:

* 100 Kubernetes nodes
* 200 namespaces
* Multiple clusters

**Without variables:**

```text
CPU Dashboard Node-1
CPU Dashboard Node-2
CPU Dashboard Node-3
...

```

**With variables:**

```text
Node Overview Dashboard -> Select Node -> View Any Node

```

One dashboard becomes completely reusable.

---

### Common Variable Examples

These are standard variable use cases:

* **node:** Select a node
* **namespace:** Select a namespace
* **pod:** Select a pod
* **service:** Select an application

The concept stays the same across all of them. Only the queries and values change.

---

## 6. Live Demonstration Sequence

Follow these exact steps in the UI:

1. Open the target dashboard.
2. Go to **Dashboard Settings**.
3. Click **Variables**.
4. Click **Add Variable**.
5. Set Name to `node`.
6. Set Type to `Query`.
7. Set Data Source to `Prometheus`.
8. Run the label query: `label_values(node_uname_info, instance)`.
9. Save the variable.
10. Watch the dropdown appear at the top of the dashboard.
11. Change the selected node from the dropdown.
12. Show the panel updating automatically.

---

## 7. Student Interaction and Checkup

Test your understanding with these questions:

* **Question 1:** What is a Variable?
* **Answer:** A dynamic value placeholder used inside dashboard queries.


* **Question 2:** Does Grafana generate variable values?
* **Answer:** No. It fetches them from the Data Source.


* **Question 3:** What type of variable are we using?
* **Answer:** Query Variable.


* **Question 4:** How do we reference a variable inside a query?
* **Answer:** `$node`


* **Question 5:** Why use Variables?
* **Answer:** One dashboard can monitor many nodes, namespaces, or pods without creating multiple dashboards.



---

## 8. Transition

Now that our dashboard is dynamic, the next logical topic is **Grafana Alerting**, where we will use query results to trigger notifications when conditions such as CPU over 90 percent, Pod Restarts increase, or HTTP 5xx errors spike become true.
