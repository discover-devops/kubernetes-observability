# Section 3: Installing Prometheus with APT

**Module:** 01 - Introduction to Observability: Prometheus and Grafana Setup

**Duration:** approximately 5 minutes

**Hands-on:** Yes. Runs on a plain Ubuntu VM, not on Kubernetes.

**Prerequisites:** Section 2. An Ubuntu EC2 instance separate from your EKS jump box.

---

## Table of Contents

- [Why This Section Exists](#why-this-section-exists)
- [Before You Start](#before-you-start)
- [Lab: Install Prometheus from the Package Manager](#lab-install-prometheus-from-the-package-manager)
  - [Step 1: Check What the Repository Offers](#step-1-check-what-the-repository-offers)
  - [Step 2: Install](#step-2-install)
  - [Step 3: Confirm the Services Are Running](#step-3-confirm-the-services-are-running)
  - [Step 4: Read the Configuration File](#step-4-read-the-configuration-file)
  - [Step 5: Open the Prometheus UI](#step-5-open-the-prometheus-ui)
  - [Step 6: Look at the Targets Page](#step-6-look-at-the-targets-page)
- [What This Tells Us](#what-this-tells-us)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Key Takeaways](#key-takeaways)
- [Interview Questions](#interview-questions)
- [What's Next](#whats-next)

---

## Why This Section Exists

This is the only section in the module that does not run on Kubernetes, and the only one whose result we will throw away.

That is deliberate. Section 4 installs Prometheus properly, using Helm and the Prometheus Operator, and that installation involves a lot of moving parts: CRDs, an operator, ServiceMonitors, sidecars. It is reasonable to look at all of that and ask whether it is really necessary.

The fastest way to answer that is to install Prometheus the simple way first and see exactly what is missing. Five minutes here makes the next fifty minutes make sense.

Do not use this approach in production on Kubernetes. That is the point of the section.

---

## Before You Start

This section runs on a separate Ubuntu virtual machine, not on the jump box you use for the EKS labs.

Keeping them apart is deliberate. This machine has no kubectl, no kubeconfig, no AWS credentials for the cluster, and no awareness that Kubernetes exists anywhere. When the section concludes that this Prometheus cannot see your cluster, that is a literal fact about the machine rather than a claim you have to accept.

It also keeps the two installations from interfering. Both Prometheus installations use port 9090, and running them on one machine would produce a port conflict that has nothing to teach you about monitoring.

**Machine specification**

| Setting | Value |
|---|---|
| AMI | Ubuntu Server 24.04 LTS or later |
| Instance type | t3.micro is sufficient |
| Storage | Default 8 GB |
| Public IP | Required |

Nothing else needs to be installed on it. No kubectl, no AWS CLI, no Helm.

**Security group rule**

| Type | Protocol | Port | Source |
|---|---|---|---|
| SSH | TCP | 22 | Your IP address |
| Custom TCP | TCP | 9090 | Your IP address |

Set the source to your own IP, not `0.0.0.0/0`. This Prometheus has no authentication of any kind.

Confirm the operating system before starting:

```bash
lsb_release -a
```

Expected output on Ubuntu 26.04:

```
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 26.04 LTS
Release:        26.04
Codename:       resolute
```

## Lab: Install Prometheus from the Package Manager

### Step 1: Check What the Repository Offers

Before installing anything, ask apt what it would give you:

```bash
sudo apt update
apt-cache policy prometheus prometheus-alertmanager
```

Expected output:

```
prometheus:
  Installed: (none)
  Candidate: 2.53.5+ds1-3
  Version table:
     2.53.5+ds1-3 500
        500 http://ap-south-1.ec2.archive.ubuntu.com/ubuntu resolute/universe amd64 Packages
prometheus-alertmanager:
  Installed: (none)
  Candidate: 0.28.1+ds-3
  Version table:
     0.28.1+ds-3 500
        500 http://ap-south-1.ec2.archive.ubuntu.com/ubuntu resolute/universe amd64 Packages
```

`apt-cache policy` is a dry run. It reports what apt knows about a package without changing anything: whether it is installed, which version it would install, and which repository that version comes from.

Three things in this output are worth reading carefully, because they are the first two arguments against this installation method.

**The version is behind.** The candidate is Prometheus 2.53.5. Upstream Prometheus has been on the 3.x series for some time. A distribution package is frozen when the Ubuntu release is frozen, so you get whatever was current at that moment, not what is current today.

**The repository is `universe`.** Ubuntu splits its archive into components. `main` is maintained and supported by Canonical. `universe` is community maintained. Prometheus comes from `universe`, which means security updates arrive on a best-effort basis rather than a guaranteed one.

**The version string contains `+ds1-3`.** That suffix means Debian-modified source. Debian repackages the upstream release to fit its own filesystem conventions, so file paths and service names differ from what the official Prometheus documentation describes. If you follow upstream docs after installing this package, the paths will not match.

If `Candidate` shows `(none)` for either package, enable the universe repository first:

```bash
sudo add-apt-repository universe
sudo apt update
```

### Step 2: Install

```bash
sudo apt install -y prometheus prometheus-alertmanager
```

This takes about 30 seconds. The package installs binaries, creates a `prometheus` system user, writes a default configuration, installs systemd unit files, and starts both services immediately.

Confirm the installed version:

```bash
prometheus --version
```

### Step 3: Confirm the Services Are Running

```bash
sudo systemctl status prometheus --no-pager
```

Look for `Active: active (running)` in the output.

```bash
sudo systemctl status prometheus-alertmanager --no-pager
```

Both should be running. The `--no-pager` flag stops systemd from opening the output in a pager, which would otherwise leave you stuck in a scroll view.

Note what has happened here. Two long-running processes are now managed by systemd on this specific machine. If this machine reboots, systemd restarts them. If this machine dies, they are gone and nothing brings them back somewhere else. Hold that thought until the end of the section.

Confirm Prometheus is listening:

```bash
sudo ss -tlnp | grep 9090
```

Expected output:

```
LISTEN  0  4096  *:9090  *:*  users:(("prometheus",pid=1234,fd=8))
```

The `*:9090` means it is bound to all interfaces, so it is reachable from outside the machine. If you see `127.0.0.1:9090` instead, it is bound to localhost only and the browser step will not work.

### Step 4: Read the Configuration File

This is the most important step in the section.

```bash
cat /etc/prometheus/prometheus.yml
```

The file is short. The part that matters is the `scrape_configs` block, which looks roughly like this:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
```

Read `static_configs` carefully. That word is the entire argument of this section.

Every target Prometheus will ever scrape has to be written into this file by hand, as a hostname and port. If you deploy a new application, you edit this file. If you add a server, you edit this file. If a server's IP address changes, you edit this file. And after every edit you reload the service.

On a handful of virtual machines with stable addresses, that is perfectly workable, and this is why the package exists.

Now consider what it means on Kubernetes. Pods are created and destroyed continuously. Their names contain generated suffixes. Their IP addresses are assigned from a pool and are reused. A deployment scaling from three replicas to ten creates seven targets that did not exist a second ago, with addresses nobody can predict.

There is no way to write that into a static file.

### Step 5: Open the Prometheus UI

Get this machine's public IP:

```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4
echo
```

That two-step call is IMDSv2, the current EC2 instance metadata service. The first call gets a short-lived token, the second uses it. The older single-line version without a token is disabled on current EC2 defaults.

Open in your browser:

```
http://<public-ip>:9090
```

You get the Prometheus web UI. This is the same UI you will see in Section 4, running the same software. Everything you learn here about the interface carries over.

Try a query. In the expression box, type:

```
up
```

Press Execute. You get one or two rows, each with a value of 1.

That is the `up` metric from Section 2, and this is a good moment to point out that it is real and observable, not a diagram. Prometheus is scraping itself and recording that the scrape succeeded.

### Step 6: Look at the Targets Page

Navigate to **Status** in the top menu, then **Targets**.

This page lists everything Prometheus is scraping. On this machine you will see one job called `prometheus`, pointing at `localhost:9090`, with state UP. You may see a second job called `node` in state DOWN, because the config references node-exporter on port 9100 but the package was never installed.

That is the whole picture. One target, which is Prometheus itself.

Leave this page open for a moment and consider what it would take to monitor a real system from here. Every application, every host, every exporter would need a line in `prometheus.yml`, added by hand, kept up to date by hand, and followed by a reload.

This page is what Section 4 is going to change.

---

## What This Tells Us

Four limitations, all visible in what you just ran.

**No service discovery.** Targets are static text in a file. Prometheus has no way to learn that something new exists.

**Manual configuration lifecycle.** Adding a target means editing a file on a specific machine and reloading a service. There is no API, no version control integration, and no way to do it from a pipeline without SSH.

**No Kubernetes awareness.** This Prometheus cannot see pods, services, deployments, or namespaces. It does not know a cluster exists. It has no credentials, no service account, and no path to the API server.

**Single point of failure.** Prometheus runs on this one machine, storing data on this one disk, managed by this one systemd instance. If the machine goes down, monitoring goes down with it, and nothing reschedules it.

Now hold that against what Section 4 delivers. Prometheus runs as a pod, so Kubernetes restarts and reschedules it. Targets are discovered from the Kubernetes API as they appear. Configuration is expressed as Kubernetes objects you apply with kubectl and store in git. Changes are picked up without a restart.

That is the gap the Prometheus Operator exists to close, and it is why the next section is worth fifty minutes.

---

## Troubleshooting

**`E: Unable to locate package prometheus`**

The universe repository is not enabled, or the package index is stale. Run `sudo add-apt-repository universe` followed by `sudo apt update`, then retry.

**Browser does not load, request times out**

Almost always the security group. Confirm port 9090 is open to your IP on this instance. Note that the request timing out rather than being refused is the signature of a firewall or security group block. A connection actively refused means something is wrong on the machine instead.

**Browser shows connection refused**

Prometheus is not listening on an external interface. Check with `sudo ss -tlnp | grep 9090`. If it shows `127.0.0.1:9090`, edit `/etc/default/prometheus` and add `--web.listen-address=0.0.0.0:9090` to `ARGS`, then run `sudo systemctl restart prometheus`.

**Service shows `failed` in systemctl status**

Read the actual error rather than guessing:

```bash
sudo journalctl -u prometheus -n 50 --no-pager
```

A YAML syntax error in `prometheus.yml` is the usual cause if you edited the file. Validate it before restarting:

```bash
promtool check config /etc/prometheus/prometheus.yml
```

**Public IP command returns nothing**

Either the instance has no public IP assigned, or IMDSv2 token retrieval failed. Confirm the instance has a public IPv4 address in the EC2 console.

---

## Cleanup

This machine has served its purpose. The simplest cleanup is to terminate the instance entirely, which removes the installation, the exposed web UI, and the running cost in one action.

If you would rather keep the machine, remove the packages instead.

```bash
sudo systemctl stop prometheus prometheus-alertmanager
sudo systemctl disable prometheus prometheus-alertmanager
sudo apt purge -y prometheus prometheus-alertmanager
sudo apt autoremove -y
```

`purge` removes configuration files as well as binaries, which `remove` alone would leave behind.

Confirm nothing is left listening:

```bash
sudo ss -tlnp | grep 9090
```

No output is the correct result.

Then terminate the instance, or stop it if you want to keep it for reference.

Everything from Section 4 onward runs on the EKS jump box, which is a different machine. Nothing from this section carries forward except the understanding of what was missing.

---

## Key Takeaways

- Prometheus installs from apt as an ordinary systemd service and works fine on standalone virtual machines.
- The packaged version lags upstream significantly and comes from the community-maintained universe repository.
- Targets are defined in `static_configs` in `/etc/prometheus/prometheus.yml`, written by hand.
- Static configuration cannot work on Kubernetes, where pod names and IP addresses are generated and short-lived.
- This installation has no service discovery, no Kubernetes awareness, and no resilience if the machine fails.
- Those four gaps are exactly what the Prometheus Operator addresses, and are the reason for the approach in Section 4.

---

## Interview Questions

**1. Can you run Prometheus outside Kubernetes?**

Yes. It is a single binary and runs as an ordinary service on any Linux machine. It is a reasonable choice for monitoring a small, stable set of virtual machines. It becomes unsuitable when targets are dynamic.

**2. What is the practical limitation of `static_configs`?**

Every target must be written into the configuration file by hand and the service reloaded after each change. That is manageable for fixed infrastructure and impossible for environments where instances are created and destroyed automatically with unpredictable addresses.

**3. Why is a distribution package usually the wrong choice for production Prometheus?**

The version is frozen at the distribution's release date and lags upstream, often by a full major version. On Ubuntu it ships from the community-maintained universe component rather than the officially supported main. The package is also patched to fit Debian filesystem conventions, so paths differ from upstream documentation.

**4. You have fifty virtual machines with fixed IP addresses and no container platform. Is apt-installed Prometheus a reasonable choice?**

It can be. The dynamic-target problem does not apply, and static configuration is workable at that scale, particularly if the file is generated by configuration management. The remaining concerns are the version lag and the single point of failure, both of which can be addressed separately.

**5. What happens to Prometheus if the machine it runs on fails?**

Monitoring stops. There is no scheduler to restart it elsewhere, and the time series data on that machine's local disk is unavailable until the machine returns. Running Prometheus as a Kubernetes workload addresses the restart and rescheduling problem, though data durability still depends on the storage layer.

---

## What's Next

You have seen what a plain installation gives you and, more usefully, what it does not.

The next section installs the same Prometheus on Kubernetes using Helm, together with the Prometheus Operator, Alertmanager, Grafana, node-exporter, and kube-state-metrics. When you reach the Targets page in that installation, it will not have one entry. It will have dozens, none of which you configured by hand.

[Section 4: Helm Installation](./04-helm-installation.md)
