# Cluster Setup

Builds the EKS cluster used by every module in this course. Run this once per session, and run the teardown at the end of the session.

Time to complete: approximately 15 to 20 minutes, most of it waiting.

---

## Table of Contents

- [What Gets Created](#what-gets-created)
- [Cluster Configuration](#cluster-configuration)
- [Why These Choices](#why-these-choices)
- [Creating the Cluster](#creating-the-cluster)
- [Verifying the Cluster](#verifying-the-cluster)
- [Creating a Working StorageClass](#creating-a-working-storageclass)
- [Verifying Storage](#verifying-storage)
- [Troubleshooting](#troubleshooting)
- [Teardown](#teardown)

---

## What Gets Created

- One EKS control plane running Kubernetes 1.34
- One managed node group with two t3.large worker nodes
- A dedicated VPC with public and private subnets across three availability zones
- Five EKS addons: vpc-cni, coredns, kube-proxy, eks-pod-identity-agent, aws-ebs-csi-driver
- IAM roles for the cluster, node group, and EBS CSI driver

---

## Cluster Configuration

Save this as `cluster.yaml`:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: observability-demo
  region: ap-south-1
  version: "1.34"

iam:
  withOIDC: true

addonsConfig:
  autoApplyPodIdentityAssociations: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: eks-pod-identity-agent
  - name: aws-ebs-csi-driver

managedNodeGroups:
  - name: ng-demo
    instanceType: t3.large
    desiredCapacity: 2
    minSize: 2
    maxSize: 3
    volumeSize: 30
```

Create it in one command:

```bash
cat > cluster.yaml << 'EOF'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: observability-demo
  region: ap-south-1
  version: "1.34"

iam:
  withOIDC: true

addonsConfig:
  autoApplyPodIdentityAssociations: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: eks-pod-identity-agent
  - name: aws-ebs-csi-driver

managedNodeGroups:
  - name: ng-demo
    instanceType: t3.large
    desiredCapacity: 2
    minSize: 2
    maxSize: 3
    volumeSize: 30
EOF
```

---

## Why These Choices

Each of these settings exists because omitting it causes a specific failure later in the course.

### aws-ebs-csi-driver

Prometheus, Alertmanager, and Grafana all request PersistentVolumeClaims by default.

EKS ships a `gp2` StorageClass out of the box, so `kubectl get sc` returns a result and the cluster appears ready for storage. But that StorageClass uses the in-tree provisioner that was removed in Kubernetes 1.31, and it is not marked default. The component that actually provisions EBS volumes is the EBS CSI driver, which is not installed by default either. Both problems have to be fixed, and the section on creating a StorageClass below covers the second.

Without it, PVCs sit in `Pending` indefinitely, the StatefulSet pods never schedule, and Helm still reports a successful install. It looks like a Helm problem. It is a storage problem, and it is the single most common failure when installing kube-prometheus-stack on a fresh EKS cluster.

### eks-pod-identity-agent and autoApplyPodIdentityAssociations

The EBS CSI driver needs AWS IAM permissions to create volumes. Historically this required manually creating an IAM role, an OIDC trust policy, and a service account annotation.

Setting `autoApplyPodIdentityAssociations: true` makes eksctl create the role and the pod identity association automatically during cluster creation. The `eks-pod-identity-agent` addon is what makes those associations work at runtime. Together they replace several manual IAM commands.

### t3.large rather than t3.medium

Two constraints, and pod count is the one that catches people.

**Pod count.** With the VPC CNI, the maximum pods per node is derived from the instance's ENI and IP address limits, not from CPU or memory. A t3.medium caps at 17 pods. A t3.large allows 35.

On a t3.medium, system components consume roughly 7 pod slots before you install anything: aws-node, kube-proxy, two CoreDNS replicas, the EBS CSI node driver, and two EBS CSI controller replicas. kube-prometheus-stack adds around 7 more: the operator, prometheus-0, alertmanager-0, Grafana, kube-state-metrics, and node-exporter. That reaches 14 to 16 of the 17 available, leaving no room for the demo applications you need to scrape.

**Memory.** A t3.medium has 4 GB total and roughly 3.4 GB allocatable. Prometheus alone can consume 1 to 2 GB once it is scraping a full cluster. Add Grafana, the operator, and kube-state-metrics and pods begin getting evicted mid-session.

### Two nodes rather than one

node-exporter runs as a DaemonSet, one pod per node. With a single node you cannot demonstrate per-node metric comparison, which is a core part of the Grafana dashboards later in the course. Two nodes also provide somewhere for pods to reschedule during the self-healing demonstrations.

### volumeSize 30

Container images for the monitoring stack are large. Prometheus, Grafana, and the operator images together with the default 20 GB root volume leave very little headroom, and disk pressure evictions are difficult to diagnose during a lab.

---

## Creating the Cluster

```bash
eksctl create cluster -f cluster.yaml
```

This runs for 15 to 20 minutes. eksctl creates two CloudFormation stacks in sequence: the cluster stack containing the VPC and control plane, then the node group stack.

Progress lines appear roughly every 30 seconds. The final line reads:

```
EKS cluster "observability-demo" in "ap-south-1" region is ready
```

eksctl updates your kubeconfig automatically. No manual `aws eks update-kubeconfig` is needed.

---

## Verifying the Cluster

Run these four checks before installing anything.

### Nodes are ready

```bash
kubectl get nodes -o wide
```

Both nodes should show `Ready`. If either shows `NotReady` for more than two minutes, check the node group in the EKS console for capacity or subnet issues.

### System pods are running

```bash
kubectl get pods -n kube-system
```

Every pod should be `Running`. Expect to see aws-node and kube-proxy on each node, two CoreDNS replicas, the EBS CSI controller, and the EBS CSI node driver on each node.

### Addons are active

```bash
aws eks list-addons --cluster-name observability-demo --region ap-south-1
```

All five addons should be listed. Confirm the EBS CSI driver specifically:

```bash
aws eks describe-addon \
  --cluster-name observability-demo \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1 \
  --query "addon.[status,serviceAccountRoleArn]" \
  --output table
```

Status must be `ACTIVE` and the role ARN must not be empty. An empty ARN means the pod identity association was not created and volume provisioning will fail.

---

## Creating a Working StorageClass

This step is required. Skipping it produces a failure that looks like a Helm problem and is not.

### The problem

EKS ships a StorageClass named `gp2`. Run `kubectl get sc` and you will see it, which makes the cluster look ready for storage.

It is not. Look at its provisioner:

```bash
kubectl get sc
```

```
NAME   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2    kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  24h
```

Two things are wrong here.

**The provisioner is `kubernetes.io/aws-ebs`.** That is the old in-tree EBS plugin, which was removed from Kubernetes in version 1.31. On a 1.34 cluster, nothing implements it. The StorageClass is a definition pointing at code that no longer exists.

**There is no `(default)` marker.** Recent EKS versions no longer mark gp2 as the default StorageClass. A PersistentVolumeClaim that does not name a StorageClass gets no class assigned at all, and can never bind.

The combination produces this, which is what you would see after installing any chart that requests storage:

```
NAME                       STATUS    VOLUME   CAPACITY   STORAGECLASS   AGE
prometheus-db-prometheus-0 Pending                                      23m
```

Note the empty STORAGECLASS column. That empty column is the signature of this problem.

### The fix

Create a gp3 StorageClass backed by the EBS CSI driver, and mark it default:

```bash
cat > gp3-sc.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
parameters:
  type: gp3
  encrypted: "true"
EOF

kubectl apply -f gp3-sc.yaml
```

Verify:

```bash
kubectl get sc
```

```
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  24h
gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   10s
```

`gp3 (default)` with provisioner `ebs.csi.aws.com` is what you need.

Why gp3 rather than gp2: it is cheaper per gigabyte, delivers a 3,000 IOPS baseline regardless of volume size, and supports volume expansion. There is no reason to choose gp2 on a new cluster.

---

## Verifying Storage

Prove that provisioning works end to end before installing anything. Two minutes here prevents twenty minutes of debugging later.

```bash
cat > test-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod
spec:
  containers:
    - name: app
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: storage-test
EOF

kubectl apply -f test-pvc.yaml
```

The gp3 StorageClass uses `WaitForFirstConsumer`, so the PVC stays Pending until a pod actually mounts it. Creating both together triggers provisioning immediately.

Wait about 30 seconds, then check:

```bash
kubectl get pvc storage-test
```

You want `Bound`, with `gp3` in the STORAGECLASS column. That confirms the CSI driver has working IAM permissions, created a real EBS volume, and attached it.

Clean up:

```bash
kubectl delete -f test-pvc.yaml
rm test-pvc.yaml
```

---

## Troubleshooting

### PVC stays Pending after the pod is created

Describe it to see the actual reason:

```bash
kubectl describe pvc storage-test
```

Check the Events section at the bottom. Common causes:

- `failed to provision volume with StorageClass "gp2": ... UnauthorizedOperation` - the CSI driver lacks IAM permissions. Confirm the addon's `serviceAccountRoleArn` is populated using the describe-addon command above.
- No events at all, and no CSI controller pods in `kubectl get pods -n kube-system` - the addon was not installed. Add it:

```bash
aws eks create-addon \
  --cluster-name observability-demo \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1
```

### Cluster creation fails partway through

eksctl usually rolls back automatically. Confirm nothing was left behind:

```bash
aws cloudformation list-stacks \
  --region ap-south-1 \
  --stack-status-filter CREATE_COMPLETE CREATE_IN_PROGRESS DELETE_FAILED ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'observability-demo')].[StackName,StackStatus]" \
  --output table
```

An empty table means the environment is clean and you can retry. Any stack in `DELETE_FAILED` or `ROLLBACK_COMPLETE` must be deleted from the CloudFormation console before recreating, or the next attempt fails on a name collision.

### Insufficient capacity in an availability zone

If the node group fails with a capacity error, either change `instanceType` to `t3a.large` or `m5.large`, or pin the node group to specific availability zones by adding to the node group definition:

```yaml
    availabilityZones: ["ap-south-1a", "ap-south-1b"]
```

### Nodes stuck NotReady

Usually the VPC CNI failing to allocate IP addresses. Check the aws-node logs:

```bash
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
```

---

## Teardown

Run this at the end of every session. The control plane bills continuously whether or not you are using it.

### Step 1: Delete load balancer resources first

This ordering matters. Deleting the cluster while a Service of type LoadBalancer or an Ingress still exists leaves the AWS load balancer orphaned - it keeps billing with nothing behind it, and the eksctl delete may hang because the VPC cannot be removed while an ENI is still attached.

```bash
kubectl delete ingress --all --all-namespaces
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer
```

Wait 60 seconds for the controllers to remove the AWS resources, then confirm:

```bash
aws elbv2 describe-load-balancers --region ap-south-1 \
  --query "LoadBalancers[].LoadBalancerName" --output table
```

### Step 2: Delete the cluster

```bash
eksctl delete cluster --name observability-demo --region ap-south-1 --wait
```

The `--wait` flag blocks until deletion completes. Without it the command returns immediately and you cannot tell whether it succeeded.

### Step 3: Verify nothing is left billing

```bash
aws cloudformation list-stacks --region ap-south-1 \
  --stack-status-filter CREATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'observability-demo')].[StackName,StackStatus]" \
  --output table

aws ec2 describe-volumes --region ap-south-1 \
  --filters Name=status,Values=available \
  --query "Volumes[].[VolumeId,Size]" --output table

aws ec2 describe-addresses --region ap-south-1 \
  --query "Addresses[?AssociationId==null].[PublicIp,AllocationId]" --output table
```

All three must return empty. Available EBS volumes are volumes with no attachment - they are left over from deleted pods and continue to bill. Unassociated Elastic IPs bill as well.

---

## Next Step

[Module 01 - Introduction to Observability](./01-introduction-to-observability/)
