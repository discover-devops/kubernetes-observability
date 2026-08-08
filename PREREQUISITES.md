# Prerequisites

Read this before starting Module 01. It covers what you need installed, what AWS access is required, and what the labs will cost.

---

## Table of Contents

- [Knowledge Assumed](#knowledge-assumed)
- [AWS Account Requirements](#aws-account-requirements)
- [Required Tools](#required-tools)
- [Installing the Tools](#installing-the-tools)
- [Verifying Your Setup](#verifying-your-setup)
- [Cost Expectations](#cost-expectations)
- [Recommended Working Environment](#recommended-working-environment)

---

## Knowledge Assumed

You should be comfortable with:

- Basic Linux command line - navigating directories, editing files, reading logs
- Core Kubernetes objects - Pods, Deployments, Services, Namespaces
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
- CloudFormation stacks (eksctl uses these internally)
- Elastic Load Balancers

An account with `AdministratorAccess` is simplest for learning. In a shared or corporate account, confirm with your platform team before creating clusters.

**Region used throughout this course:** `ap-south-1` (Mumbai)

You can substitute another region, but every command in the labs specifies `ap-south-1` explicitly. If you change it, change it consistently.

---

## Required Tools

| Tool | Minimum Version | Purpose |
|---|---|---|
| AWS CLI | 2.x | Authenticating to AWS, managing EKS addons |
| eksctl | 0.190+ | Creating and deleting EKS clusters |
| kubectl | 1.32+ | Interacting with the cluster |
| Helm | 3.14+ | Installing kube-prometheus-stack |
| git | any recent | Cloning this repository |

kubectl must be within one minor version of your cluster. This course uses Kubernetes 1.34, so kubectl 1.33, 1.34, or 1.35 will work.

---

## Installing the Tools

These instructions target Amazon Linux 2023 on an EC2 jump box, which is the environment used throughout the course. See [Recommended Working Environment](#recommended-working-environment) for why.

### AWS CLI

Pre-installed on Amazon Linux 2023. To install elsewhere:

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### eksctl

```bash
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
```

### kubectl

```bash
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
```

### git

```bash
sudo dnf install -y git
```

---

## Verifying Your Setup

Run all five checks before starting Module 01:

```bash
aws --version
eksctl version
kubectl version --client
helm version --short
git --version
```

Then confirm AWS authentication works:

```bash
aws sts get-caller-identity
```

Expected output is a JSON block containing your account ID, user ID, and ARN. If you get `Unable to locate credentials`, run `aws configure` and supply your access key, secret key, and `ap-south-1` as the default region.

Finally, confirm you can reach EKS specifically:

```bash
aws eks list-clusters --region ap-south-1
```

An empty list is the correct result if you have no clusters yet. An `AccessDenied` error means your IAM permissions are insufficient - resolve that before proceeding.

---

## Cost Expectations

These labs create real, billable AWS infrastructure.

| Resource | Approximate Cost |
|---|---|
| EKS control plane | USD 0.10 per hour, billed continuously |
| 2 x t3.large worker nodes | USD 0.1664 per hour combined |
| EBS gp3 volumes (2 x 30 GB) | USD 0.0066 per hour |
| Network Load Balancer (when created) | USD 0.0225 per hour plus data processing |
| NAT Gateway (if used) | USD 0.056 per hour plus data processing |

A full module session of roughly three hours costs about USD 1.00 without a load balancer, or about USD 1.10 with one.

The control plane is the item to watch. It bills 24 hours a day from creation until deletion, regardless of whether any workload is running. A cluster left up for a week costs approximately USD 17 for the control plane alone, before nodes.

### Cost Control Rules

1. Delete the cluster at the end of every session. Do not leave it running overnight.
2. Delete Kubernetes Service objects of type LoadBalancer, and Ingress objects, before deleting the cluster. The controller removes the AWS load balancer when the Kubernetes object is deleted. Delete the cluster first and the load balancer is orphaned and keeps billing with nothing pointing at it.
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

Empty results across all three mean the cleanup was complete. Anything listed is costing money and should be deleted.

4. Set a billing alarm. In the AWS Billing console, create a budget with an alert at a threshold you are comfortable with. This catches the cluster you forgot about on a Friday evening.

---

## Recommended Working Environment

Run all labs from an EC2 jump box in `ap-south-1` rather than from your laptop.

Reasons:

- kubectl and Helm operate against the EKS API endpoint in the same region, so latency is minimal
- Tool versions stay consistent regardless of whether your laptop runs Windows, macOS, or Linux
- No local firewall or corporate proxy interference with the Kubernetes API
- The jump box can be stopped when not in use, and its state persists between sessions

A `t3.micro` or `t3.small` running Amazon Linux 2023 is sufficient. The jump box only runs CLI tools; all workloads run on the EKS nodes.

Attach an IAM role to the jump box with the permissions listed above, so you do not need to store access keys on the instance.

Working from a laptop is possible and every command still applies. You will need the same tools installed locally and valid AWS credentials configured.

---

## Next Step

[CLUSTER-SETUP.md](./CLUSTER-SETUP.md) - build the EKS cluster used across all modules.
