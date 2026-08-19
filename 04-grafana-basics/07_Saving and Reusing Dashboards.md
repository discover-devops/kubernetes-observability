# Topic 7: Saving and Reusing Dashboards

## 1. Context

We have built a dashboard with five panels.

The next question is:

What happens if the Grafana Pod restarts? Or if we want to use the same dashboard in another Grafana instance?

This is why we save dashboards properly and learn how to export and import them.

Think of the complete flow:

Create Dashboard -> Save Dashboard -> Organize Dashboard -> Export Dashboard -> Import Anywhere

---

## 2. Concept

### Step 1: Save the Dashboard

After creating all five panels, click the Save icon in the top right corner or press Ctrl+S.

Grafana asks for a few details:

* **Dashboard Name:** Enter `Node Overview`.
* **Folder:** Select `Kubernetes`.
* **Tags:** Add `kubernetes`, `nodes`, and `infrastructure`.

**Why use folders?**
As organizations grow, they may have hundreds of dashboards. Instead of keeping everything together, folders help organize them.

Example folder structure:

```text
Grafana
|-- Kubernetes
|-- Infrastructure
|-- Applications
`-- Databases

```

So when someone needs a Kubernetes dashboard, they immediately know where to find it.

**Why use tags?**
Tags make dashboards easier to search. For example, if someone searches `kubernetes`, Grafana can quickly show dashboards with that tag.

To summarize:

* Folder organizes dashboards.
* Tags make dashboards searchable.

---

### Step 2: What Gets Saved?

When we click Save, Grafana stores details like:

* Panel layout
* PromQL queries
* Visualization type
* Thresholds
* Units
* Titles
* Legend settings

**Notice what is not saved:**
The dashboard does not store the actual metric values. It stores the configuration needed to recreate the visualization.

```text
Dashboard
|-- Query
|-- Panel Type
|-- Thresholds
|-- Layout
`-- Settings

Live Data
  |
  v
Prometheus

```

Every time someone opens the dashboard, Grafana runs the queries again and displays the latest data.

---

## 3. Internal Working

### Step 3: Export Dashboard as JSON

Suppose you have built a dashboard. Now you want to use it in another cluster. Do you rebuild everything?

No. Grafana allows us to export the dashboard as a JSON file.

**UI Steps:**
Dashboard -> Settings -> JSON Model -> Export

Grafana generates a JSON representation of the dashboard.

The important point is: The JSON contains the dashboard definition, not a screenshot. It includes panel definitions, queries, layout, thresholds, titles, and visualization settings.

```text
Dashboard -> JSON -> Portable Dashboard Definition

```

---

### Step 4: Import Dashboard

Now imagine another Grafana instance. Instead of rebuilding everything, we simply import the JSON.

**UI Steps:**
Dashboards -> Import -> Upload JSON -> Select Data Source -> Import

Within a few clicks, the same dashboard appears.

---

## 4. Architecture Before Commands

### Why Does the Data Source UID Matter?

This connects back to something we learned in the Data Sources section.

Remember this line: `uid: prometheus-main`

Suppose our dashboard references Prometheus. When we import the dashboard elsewhere, Grafana needs to know which data source that dashboard should use.

A stable UID helps Grafana map the dashboard to the correct data source across environments.

```text
Grafana A (Dashboard)
  |
  v
UID: prometheus-main

Export JSON
  |
  v
Grafana B
  |
  v
UID: prometheus-main
  |
  v
Dashboard works

```

This is why production teams prefer fixed UIDs for provisioned data sources.

---

## 5. Dashboard Lifecycle

Let us put everything together:

Create Dashboard -> Add Panels -> Save -> Folder + Tags -> Export JSON -> Import into another Grafana -> Reuse the same dashboard

This is the complete lifecycle of a Grafana dashboard from creation to reuse.

---

## 6. Student Interaction and Checkup

Test your understanding with these questions:

* **Question 1:** What is the name of today's dashboard?
* **Answer:** Node Overview


* **Question 2:** Why do we use folders?
* **Answer:** To organize dashboards.


* **Question 3:** Why do we use tags?
* **Answer:** To make dashboards easier to search.


* **Question 4:** What does Export create?
* **Answer:** A JSON definition of the dashboard.


* **Question 5:** Does Export contain live metric values?
* **Answer:** No. It contains the dashboard configuration.


* **Question 6:** Why is a fixed Data Source UID useful?
* **Answer:** It helps imported dashboards connect to the correct data source across Grafana instances.



---

## 7. Session Wrap Up

This completes the full Grafana workflow:

Prometheus -> Grafana Installation -> Data Source -> Explore -> Dashboard -> Panels -> Save -> Export -> Import

You can now install Grafana on Kubernetes, connect it to Prometheus, test queries, build a multi-panel dashboard, save it, and move it between Grafana environments using the dashboard JSON.
