# Module 02: Creating a Workload Cluster

## Module Objectives
Now that the brain (Management Cluster) is ready, we will create the muscles: our first **Workload Cluster**.
You will learn to:
1.  **Generate** a declarative cluster manifest.
2.  **Monitor** the asynchronous provisioning cycle.
3.  **Access** the new cluster via kubeconfig.
4.  **Finalize** the setup by installing networking (CNI).

### Concept: Declarative Infrastructure

### Benefits & Limitations: Declarative Infrastructure

| Benefits | Limitations |
| :--- | :--- |
| **GitOps:** The cluster state is code (YAML).<br>**Reproducibility:** Easy to recreate exact copies.<br>**Audit:** Every change is tracked in git history. | **Latency:** Provisioning takes time (VM creation).<br>**Abstraction Leaks:** You still need to know K8s internals (CNI, CSI) to debug.<br>**Docker Provider:** Great for dev, but networking is complex/slow. |

With CAPI, you don't run imperative commands like `create server` or `install k8s`.
Instead, you write a YAML file describing "I want a cluster with 1 Control Plane and 1 Worker".
You submit this YAML to the Management Cluster, and CAPI's reconciliation loops make it happen.

```mermaid
graph LR
    User[👤 User] -->|1. Submit YAML| Mgmt[🧠 Management Cluster]
    Mgmt -->|2. Create Docker Containers| Docker[🐳 Docker Engine]
    Docker -->|3. Spin up| Nodes[📦 Nodes (CP & Worker)]
    Mgmt -->|4. Init K8s| Nodes
```

---

## Important: Kubeconfig Context
Before starting, ensure your `kubectl` context is pointing to the **Management Cluster** (`capi-mgmt`). Most commands in this module will implicitly target the Management Cluster, then we will switch to the Workload Cluster's kubeconfig when interacting with it.
```bash
export KUBECONFIG=../module-01-introduction/capi-mgmt.kubeconfig
kubectl config current-context
```
**Example Output:**
```text
kind-capi-mgmt
```

---

## Step 1: Define the Cluster

### 1. Configuration Variables
These describe the cluster we're about to create — its Kubernetes version and size. They're already baked into the shipped `first-capi-cluster.yaml`; we list them here so the manifest's values are explicit (and so you have them handy if you later regenerate to a different filename).

```bash
# The Kubernetes version for the new cluster
export KUBERNETES_VERSION=v1.31.0

# Topology: 1 Control Plane (Master), 1 Worker
export CONTROL_PLANE_MACHINE_COUNT=1
export WORKER_MACHINE_COUNT=1
```



### 2. Inspect the Manifest
This module ships a ready-to-apply manifest — **`first-capi-cluster.yaml`** — already rendered for the values above (1 control plane, 1 worker, `v1.31.0`). Open it and read through the objects before applying:

```bash
less first-capi-cluster.yaml    # or open it in your editor
```

> **Why it's shipped pre-generated (CAPD v1.11.1).** You would normally render
> this yourself with `clusterctl generate cluster ... --flavor development-topology`.
> However, the Docker infrastructure provider release **v1.11.1 does not publish**
> a `development-topology` template, so that command fails with
> `failed to read "cluster-template-development-topology.yaml"` — and because it
> writes with `> first-capi-cluster.yaml`, running it would also **overwrite the
> shipped manifest with an empty file**. We therefore provide the equivalent
> manifest in the repo. (If you want to regenerate for other flavors later, write
> to a *different* filename so you never clobber this one.)

### 3. Apply (Start Provisioning)
We submit the manifest to the Management Cluster. It is **Classy** (ClusterClass-based): it creates a reusable `ClusterClass` (`quick-start`) plus the template objects it references, and a single topology-based `Cluster`. The controllers then expand that topology into the underlying `KubeadmControlPlane` / `MachineDeployment` resources for you and start creating Docker containers.

```bash
kubectl apply -f first-capi-cluster.yaml
```
**Example Output:**
```text
clusterclass.cluster.x-k8s.io/quick-start created
dockerclustertemplate.infrastructure.cluster.x-k8s.io/quick-start-cluster created
kubeadmcontrolplanetemplate.controlplane.cluster.x-k8s.io/quick-start-control-plane created
dockermachinetemplate.infrastructure.cluster.x-k8s.io/quick-start-control-plane created
dockermachinetemplate.infrastructure.cluster.x-k8s.io/quick-start-default-worker-machinetemplate created
dockermachinepooltemplate.infrastructure.cluster.x-k8s.io/quick-start-default-worker-machinepooltemplate created
kubeadmconfigtemplate.bootstrap.cluster.x-k8s.io/quick-start-default-worker-bootstraptemplate created
cluster.cluster.x-k8s.io/first-capi-cluster created
```

---

## Step 2: Monitoring Provisioning

Provisioning is asynchronous. It happens in phases.

### Phase 1: Infrastructure
Check the high-level cluster object. It should show `Provisioning`.
```bash
kubectl get cluster
```
**Example Output:**
```text
NAME                 PHASE          AGE     VERSION
first-capi-cluster   Provisioning   10s     v1.31.0
```

### Phase 2: Control Plane
Check the physical machines. You should see the Control Plane node starting first.
```bash
kubectl get machines
```
**Example Output:**
```text
NAME                                          CLUSTER              NODENAME                               PROVIDERID                                     PHASE          AGE     VERSION
first-capi-cluster-control-plane-xyz          first-capi-cluster   first-capi-cluster-control-plane-xyz   docker:////first-capi-cluster-control-plane-xyz   Running        2m      v1.31.0
first-capi-cluster-md-0-abc                   first-capi-cluster   first-capi-cluster-md-0-abc            docker:////first-capi-cluster-md-0-abc            Running        1m      v1.31.0
```

**HINT:** you can use the kubectl klock plugin to monitor a specific resource, try it :)

---

## Step 3: Accessing the Cluster

The new cluster works, but your local `kubectl` doesn't know about it yet.

### 1. Retrieve Kubeconfig
CAPI automatically generated the kubeconfig for the new cluster and stored it in a Secret named `first-capi-cluster-kubeconfig`. This command fetches that secret and saves it locally.

```bash
clusterctl get kubeconfig first-capi-cluster > first-capi-cluster.kubeconfig
```

### 2. Test Connection
We use the `--kubeconfig` flag to tell kubectl to talk to our *new* cluster (Workload) instead of the Management Cluster.
```bash
kubectl --kubeconfig=first-capi-cluster.kubeconfig cluster-info
```
**Example Output:**
```text
Kubernetes control plane is running at https://127.0.0.1:35231
CoreDNS is running at https://127.0.0.1:35231/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

---

## Step 4: Networking (CNI)

### 1. The "NotReady" Problem
Check the nodes status on the workload cluster.
```bash
kubectl --kubeconfig=first-capi-cluster.kubeconfig get nodes
```
**Example Output:**
```text
NAME                                   STATUS     ROLES           AGE   VERSION
first-capi-cluster-control-plane-xyz   NotReady   control-plane   3m    v1.31.0
first-capi-cluster-md-0-abc            NotReady   <none>          2m    v1.31.0
```

### 2. Install Calico
We apply the Calico CNI manifests to the **Workload Cluster**. This installs the DaemonSets required for pod networking. Without this, CoreDNS cannot start.

```bash
kubectl --kubeconfig=first-capi-cluster.kubeconfig \
  apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml
```
**Example Output:**
```text
poddisruptionbudget.policy/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
serviceaccount/calico-node created
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
...
daemonset.apps/calico-node created
deployment.apps/calico-kube-controllers created
```

### 3. Final Verification
Verify that the nodes transition to `Ready` status.
```bash
kubectl --kubeconfig=first-capi-cluster.kubeconfig get nodes
```
**Example Output:**
```text
NAME                                   STATUS   ROLES           AGE   VERSION
first-capi-cluster-control-plane-xyz   Ready    control-plane   5m    v1.31.0
first-capi-cluster-md-0-abc            Ready    <none>          4m    v1.31.0
```
*Status: `Ready`*.

**HINT:** you can use the kubectl klock plugin to monitor a specific resource, try it :)

Congratulations! You have provisioned a fully functional Kubernetes cluster using **ONLY** Kubernetes objects managed by the CAPI controllers.

## Automatic Validation

```bash
./validate.sh
```

---
## Dig Deeper Challenge

Calico is great, but eBPF is the future.
**Your Mission:** Replace Calico with **Cilium** on your `first-capi-cluster` cluster.
You will need to delete Calico first, then find a way to install Cilium (CLI or Helm) using the kubeconfig.

*Warning: Ensure your nodes become `Ready` again!*

### Need Help?
If you are stuck on this challenge, you can request the solution to be revealed in this file.
Run:
```bash
~/request-help.sh module-02-first-capi-cluster
```
Wait for the instructor to approve, then check this file again.

### Dig Deeper Challenge 2: Persistent Storage
Your cluster has no storage. Install the 'local-path-provisioner' manually on the workload cluster and create a PVC.

*Hint: Check the hints file via the request tool.*

---
## 🔮 What's Next?
You have built a cluster manually. It was tedious, right?
In **Module 03**, we will delete this cluster and replace it with a **Fleet of 3 Clusters** using Helm automation.
We will also learn how to automatically inject CNI (Calico) so you never have to run `kubectl apply` manually again.

[Go to Module 03 ->](../module-03-templating/)