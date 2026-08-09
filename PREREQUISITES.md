# Prerequisites

Read this before starting Module 01. It covers what you need installed, what AWS access is required, and what the labs will cost.

---

## Table of Contents

- [Knowledge Assumed](#knowledge-assumed)
- [AWS Account Requirements](#aws-account-requirements)
- [The Jump Box](#the-jump-box)
- [Required Tools](#required-tools)
- [Installing the Tools](#installing-the-tools)
- [Verifying Your Setup](#verifying-your-setup)
- [Security Group Rules](#security-group-rules)
- [Cost Expectations](#cost-expectations)

---

## Knowledge Assumed

You should be comfortable with:

- Basic Linux command line: navigating directories, editing files, reading logs
- Core Kubernetes objects: Pods, Deployments, Services, Namespaces
- Running `kubectl` commands and reading their output
- Basic YAML syntax and indentation rules

You do not need prior experience with Prometheus, Grafana, PromQL, or Helm. Each is introduced from the beginning.

---

## AWS Account Requirements

You need an AWS account with permissions to create:

- EKS clusters and managed node groups
- EC2 instances, security groups, and EBS volumes
- VPCs, subnets, route tables, internet gateways, and NAT gateways
- IAM roles and policies
- CloudFormation stacks, which eksctl uses internally
- Elastic Load Balancers

An account or role with `AdministratorAccess` is simplest for learning. In a shared or corporate account, confirm with your platform team before creating clusters.

**Region used throughout this course:** `ap-south-1` (Mumbai)

You can substitute another region, but every command in the labs names `ap-south-1` explicitly. If you change it, change it consistently.

---

## Machines Used in This Course

Two Ubuntu EC2 instances, with clearly separate roles. They are never used interchangeably.

### The EKS jump box

Used for Section 4 onward, which is everything involving Kubernetes.

| Setting | Value |
|---|---|
| AMI | Ubuntu Server 24.04 LTS or later |
| Instance type | t3.small |
| Storage | 20 GB gp3 |
| Region | ap-south-1 |
| Public IP | Required |
| IAM role | Attached, with the permissions listed above |

This box runs command line tools only. All workloads run on the EKS worker nodes, so it does not need to be large. Install the tools listed below on this machine.

### The standalone VM

Used only for Section 3, which installs Prometheus directly on an operating system to demonstrate what that approach cannot do.

| Setting | Value |
|---|---|
| AMI | Ubuntu Server 24.04 LTS or later |
| Instance type | t3.micro |
| Storage | Default 8 GB |
| Public IP | Required |
| IAM role | Not required |

Install nothing on this machine in advance. No kubectl, no AWS CLI, no Helm. Section 3 installs what it needs through apt, and the machine is terminated when the section ends.

Keeping this separate from the jump box matters for two reasons. It makes the isolation real rather than asserted, since the machine genuinely has no path to the cluster. And it avoids a port conflict, because both Prometheus installations listen on 9090 and running them on one machine produces a failure that teaches nothing about monitoring.

---

## IAM Identity and Cluster Access

Worth understanding before you create the cluster, because it causes a confusing failure otherwise.

Two permission systems are involved. AWS IAM governs what you can do to the cluster as an AWS resource: create it, delete it, manage addons. Kubernetes RBAC governs what you can do inside it with kubectl. IAM has no authority over the second.

EKS connects them through access entries, which map an IAM principal to a Kubernetes identity. Without a mapping there is no kubectl access, regardless of IAM permissions. It is entirely possible to hold `AdministratorAccess` and still receive:

```
error: You must be logged in to the server (Unauthorized)
```

EKS creates an access entry automatically for whichever IAM principal calls `CreateCluster`, granting it cluster administrator rights. This is implicit. It does not appear in your cluster configuration file and you never request it.

The practical consequence: create the cluster from the jump box and use it from the jump box. Copying a kubeconfig to a machine running under a different IAM role will not work, because the kubeconfig calls `aws eks get-token`, which returns a token for that machine's principal, and that principal has no access entry.

If you ever do need a second machine to reach the cluster, add an access entry rather than copying credentials:

```bash
eksctl create accessentry \
  --cluster observability-demo \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME \
  --access-policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope-type cluster
```

### A note on the public IP

If you stop and start an instance, its public IP changes unless an Elastic IP is attached. That breaks your SSH session and any browser URLs you had open. Either leave instances running for the duration of a session, or attach an Elastic IP.

---

## Required Tools

| Tool | Minimum Version | Purpose |
|---|---|---|
| AWS CLI | 2.x | Authenticating to AWS, managing EKS addons |
| eksctl | 0.190 or later | Creating and deleting EKS clusters |
| kubectl | 1.33 to 1.35 | Interacting with the cluster |
| Helm | 3.14 or later | Installing kube-prometheus-stack |
| git | any recent | Cloning this repository |
| unzip | any | Required by the AWS CLI installer |

kubectl must be within one minor version of your cluster. This course uses Kubernetes 1.34, so kubectl 1.33, 1.34, or 1.35 all work.

---

## Installing the Tools

Run these in order on the Ubuntu jump box.

### Base packages

```bash
sudo apt update
sudo apt install -y unzip curl git
```

Install `unzip` first. The AWS CLI installer downloads a zip archive and fails with `missing required dependencies: unzip` if it is absent, which is a confusing error given the installer is itself a download.

### AWS CLI v2

Ubuntu's `awscli` package is version 1 and is not suitable for EKS work. Install v2 directly:

```bash
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws
```

### kubectl

```bash
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### eksctl

```bash
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
```

### Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
```

---

## Verifying Your Setup

Run all five version checks:

```bash
aws --version
eksctl version
kubectl version --client
helm version --short
git --version
```

Then confirm AWS authentication:

```bash
aws sts get-caller-identity
```

Expected output is a JSON block containing your account ID and an ARN. With an instance role attached, the ARN looks like this:

```
arn:aws:sts::123456789012:assumed-role/YourRoleName/i-0abc123def456
```

The `assumed-role` form confirms the instance role is being used rather than stored credentials. If you get `Unable to locate credentials`, no role is attached to the instance.

Finally, confirm EKS access specifically:

```bash
aws eks list-clusters --region ap-south-1
```

An empty list is the correct result before you have created anything. An `AccessDenied` error means the role's permissions are insufficient, and that must be resolved before continuing.

---

## Security Group Rules

The EKS jump box needs inbound rules for SSH and for the web interfaces reached during the labs.

The standalone VM used in Section 3 needs only SSH and port 9090.

| Type | Protocol | Port | Source | Used by |
|---|---|---|---|---|
| SSH | TCP | 22 | Your IP | Shell access |
| Custom TCP | TCP | 9090 | Your IP | Prometheus UI |
| Custom TCP | TCP | 3000 | Your IP | Grafana |
| Custom TCP | TCP | 9093 | Your IP | Alertmanager |

Set the source to your own IP address in every case, never `0.0.0.0/0`. None of these interfaces has meaningful authentication in a lab setup, and Grafana's default credentials are widely known.

### Port forwarding from a jump box

Later sections reach these interfaces using `kubectl port-forward`. By default, port-forward binds to `127.0.0.1` on the machine running it, which means it is reachable only from that machine. Since you will browse from your laptop to the jump box, every port-forward command in this course includes `--address 0.0.0.0`:

```bash
kubectl port-forward --address 0.0.0.0 svc/some-service 3000:80 -n monitoring
```

Without that flag the security group rule makes no difference, and the browser reports a connection timeout with nothing obviously wrong on the cluster. This is a common and confusing failure, so the flag is included everywhere it is needed.

---

## Cost Expectations

These labs create real, billable AWS infrastructure.

| Resource | Approximate Cost |
|---|---|
| EKS control plane | USD 0.10 per hour, billed continuously |
| 2 x t3.large worker nodes | USD 0.1664 per hour combined |
| EBS gp3 volumes, 2 x 30 GB | USD 0.0066 per hour |
| Jump box, t3.small | USD 0.0208 per hour |
| Network Load Balancer, when created | USD 0.0225 per hour plus data processing |

A three hour session costs roughly USD 1.00.

The control plane is the item to watch. It bills 24 hours a day from creation until deletion, whether or not any workload is running. A cluster left up for a week costs about USD 17 for the control plane alone, before nodes.

### Cost Control Rules

1. Delete the cluster at the end of every session. Do not leave it running overnight.
2. Delete Kubernetes Services of type LoadBalancer, and Ingress objects, before deleting the cluster. The controller removes the AWS load balancer when the Kubernetes object is deleted. Delete the cluster first and the load balancer is orphaned, continuing to bill with nothing behind it.
3. After every cleanup, verify nothing was left behind:

```bash
aws elbv2 describe-load-balancers --region ap-south-1 \
  --query "LoadBalancers[].LoadBalancerName" --output table

aws ec2 describe-volumes --region ap-south-1 \
  --filters Name=status,Values=available \
  --query "Volumes[].VolumeId" --output table

aws ec2 describe-addresses --region ap-south-1 \
  --query "Addresses[?AssociationId==null].PublicIp" --output table
```

Empty results across all three mean cleanup was complete. Anything listed is costing money and should be deleted.

4. Set a billing alarm in the AWS Billing console with a threshold you are comfortable with. This catches the cluster you forgot about on a Friday evening.

---

## Next Step

[CLUSTER-SETUP.md](./CLUSTER-SETUP.md) builds the EKS cluster used across all modules.
