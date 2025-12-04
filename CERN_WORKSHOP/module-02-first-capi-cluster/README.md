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
`clusterctl` uses these environment variables to fill in the templates. We define the version and size of our target cluster here.

```bash
# The Kubernetes version for the new cluster
export KUBERNETES_VERSION=v1.31.0

# Topology: 1 Control Plane (Master), 1 Worker
export CONTROL_PLANE_MACHINE_COUNT=1
export WORKER_MACHINE_COUNT=1
```



### 2. Generate Manifest
This command renders a complete Kubernetes YAML manifest based on the `docker` infrastructure provider template. We pipe (`>`) the output to a file instead of applying it directly, so we can inspect it.

```bash
clusterctl generate cluster first-capi-cluster \
  --flavor development \
  --kubernetes-version "${KUBERNETES_VERSION}" \
  --control-plane-machine-count="${CONTROL_PLANE_MACHINE_COUNT}" \
  --worker-machine-count="${WORKER_MACHINE_COUNT}" \
  > first-capi-cluster.yaml
```
*No output is expected (it goes to the file).*

### 3. Apply (Start Provisioning)
We submit the generated manifest to the Management Cluster. This creates the CAPI Custom Resources (`Cluster`, `MachineDeployment`), triggering the controllers to start creating Docker containers.

```bash
kubectl apply -f first-capi-cluster.yaml
```
**Example Output:**
```text
cluster.cluster.x-k8s.io/first-capi-cluster created
dockercluster.infrastructure.cluster.x-k8s.io/first-capi-cluster created
kubeadmcontrolplane.controlplane.cluster.x-k8s.io/first-capi-cluster-control-plane created
dockermachinetemplate.infrastructure.cluster.x-k8s.io/first-capi-cluster-control-plane created
machinedeployment.cluster.x-k8s.io/first-capi-cluster-md-0 created
dockermachinetemplate.infrastructure.cluster.x-k8s.io/first-capi-cluster-md-0 created
kubeadmconfigtemplate.bootstrap.cluster.x-k8s.io/first-capi-cluster-md-0 created
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
[Go to Module 03 ->](../module-03-templating/)