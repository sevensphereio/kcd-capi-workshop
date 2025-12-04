# Module 01: Introduction & Management Cluster

## Module Objectives
This module is the essential foundation. You cannot complete the subsequent modules without this one.

In this module we will:
1.  **Validate** your workstation tools.
2.  **Bootstrap** a local Kubernetes cluster (Kind) to act as our **Management Cluster**.
3.  **Initialize** Cluster API (CAPI) components on it.

### Concept: The Management Cluster Architecture

### Benefits & Limitations: Cluster API

| Benefits | Limitations |
| :--- | :--- |
| **Unified API:** Manage AWS, Azure, and Docker clusters with the same YAML.<br>**Self-Healing:** Controllers automatically repair broken nodes.<br>**Automation:** Create 100 clusters as easily as 1. | **Complexity:** High learning curve (CRDs, Providers).<br>**Bootstrap:** Requires an initial cluster (Mgmt) to start.<br>**Overhead:** Running controllers consumes resources. |

In Cluster API, we distinguish two types of clusters:
*   **Management Cluster:** The "Brain". It hosts the CAPI controllers and the Custom Resource Definitions (CRDs) that define what a "Cluster" is. It does NOT run your applications.
*   **Workload Cluster:** The "Muscle". These are the clusters created and managed by the Management Cluster. They run your actual apps.

[[ add CAPI diagram]]

---

## Step 0: Prerequisite Check

Before starting, open your terminal and verify your tool versions.

**1. Verify Docker is active**
We need the Docker daemon running because Kind will create containers to simulate Kubernetes nodes.
```bash
docker ps
```
**Example Output:**
```text
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
(Empty if no containers are running, or a list of containers)
```

**2. Verify Kind version**
Kind (Kubernetes IN Docker) is our bootstrap tool.
```bash
kind version
```
**Example Output:**
```text
kind v0.30.0 go1.22.2 linux/amd64
```

**3. Verify Kubectl**
The standard Kubernetes CLI to interact with our clusters.
```bash
kubectl version --client
```
**Example Output:**
```text
Client Version: v1.34.2
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
```

**4. Verify Clusterctl**
The specialized CLI for Cluster API operations.
```bash
clusterctl version
```
**Example Output:**
```text
clusterctl version: {Major:1, Minor:11, GitVersion:"v1.11.1", GitCommit:"...", GitTreeState:"clean", BuildDate:"...", GoVersion:"go1.22.5", Compiler:"gc", Platform:"linux/amd64"}
```

---

## Step 1: Create the Management Cluster

We mount the docker socket to allow "Docker-in-Docker" provisioning.

### 1. Create configuration file
We define a custom Kind cluster config. The `extraMounts` section is critical: it mounts your host's Docker socket (`/var/run/docker.sock`) inside the Kind container. This allows the CAPI controller running *inside* Kind to spawn new sibling containers on your host.

Create `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
    - hostPath: /var/run/docker.sock
      containerPath: /var/run/docker.sock
```

### 2. Launch the cluster
This command instructs Kind to pull the node image and bootstrap a single-node cluster named `capi-mgmt` using our config.
```bash
kind create cluster --config kind-config.yaml --name capi-mgmt
```
**Example Output:**
```text
Creating cluster "capi-mgmt" ...
 ✓ Ensuring node image (kindest/node:v1.31.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-capi-mgmt"
You can now use your cluster with:
kubectl cluster-info --context kind-capi-mgmt
```

### 3. Save Kubeconfig
While `kubectl` context is automatically set, it's good practice to explicitly save the kubeconfig to a known path. This is especially useful for scripting or if you need to manage multiple management clusters. Let's save it to our current directory.
```bash
kind get kubeconfig --name capi-mgmt > $(pwd)/capi-mgmt.kubeconfig
```
**Example Output:**
```text
# No direct output, kubeconfig is written to capi-mgmt.kubeconfig
```

### 4. Verify Context
Before proceeding, ensure your `kubectl` is configured to talk to the Management Cluster. You can do this by setting the `KUBECONFIG` environment variable.
```bash
export KUBECONFIG=$(pwd)/capi-mgmt.kubeconfig
kubectl config current-context
```
**Example Output:**
```text
kind-capi-mgmt
```

---

## Step 2: Initialize Cluster API

We will now install the "Brain" software.

### 1. Enable Features (ClusterTopology & CRS)
We export these environment variables to enable specific Feature Gates in CAPI. `EXP_CLUSTER_RESOURCE_SET` allows auto-installing addons (like CNI), and `CLUSTER_TOPOLOGY` enables the newer "Classy Clusters" API.

```bash
export EXP_CLUSTER_RESOURCE_SET=true
export CLUSTER_TOPOLOGY=true
```

### 2. Run Initialization (Pinned Version)
We explicitly bind to **CAPI v1.11.1** to ensure reproducibility. This command fetches the manifests for the Core CAPI controller, the Kubeadm Bootstrap provider, the Kubeadm Control Plane provider, and the Docker Infrastructure provider, and installs them into the cluster.

```bash
clusterctl init \
  --core cluster-api:v1.11.1 \
  --bootstrap kubeadm:v1.11.1 \
  --control-plane kubeadm:v1.11.1 \
  --infrastructure docker:v1.11.1
```
**Example Output:**
```text
Fetching providers
Installing cert-manager Version="v1.15.3"
Waiting for cert-manager to be available...
Installing Provider="cluster-api" Version="v1.11.1" TargetNamespace="capi-system"
Installing Provider="bootstrap-kubeadm" Version="v1.11.1" TargetNamespace="capi-kubeadm-bootstrap-system"
Installing Provider="control-plane-kubeadm" Version="v1.11.1" TargetNamespace="capi-kubeadm-control-plane-system"
Installing Provider="infrastructure-docker" Version="v1.11.1" TargetNamespace="capd-system"
Your management cluster has been initialized successfully!
```

### Deep Dive: What is installed?
`clusterctl` installs 4 component groups via Helm charts/Manifests, all pinned to **v1.11.1**:
*   **Core Provider (cluster-api):** The generic logic.
*   **Bootstrap Provider (kubeadm):** Generates `cloud-init`.
*   **Control Plane Provider (kubeadm):** Manages etcd/api-server lifecycle.
*   **Infrastructure Provider (docker):** Manages containers.

---

## Step 3: Final Verification

```bash
kubectl get pods -A | grep -E 'capi|capd|cert-manager'
```
**Example Output:**
```text
caaph-system                      caaph-controller-manager-xxx                      1/1     Running   0          2m
capd-system                       capd-controller-manager-xxx                       1/1     Running   0          2m
capi-kubeadm-bootstrap-system     capi-kubeadm-bootstrap-controller-manager-xxx     1/1     Running   0          2m
capi-kubeadm-control-plane-system capi-kubeadm-control-plane-controller-manager-xxx 1/1     Running   0          2m
capi-system                       capi-controller-manager-xxx                       1/1     Running   0          2m
cert-manager                      cert-manager-xxx                                  1/1     Running   0          3m
cert-manager                      cert-manager-cainjector-xxx                       1/1     Running   0          3m
cert-manager                      cert-manager-webhook-xxx                          1/1     Running   0          3m
```

**Success Checklist:**
- [ ] `cert-manager-*`: Running
- [ ] `capi-controller-manager-*`: Running
- [ ] `capd-controller-manager-*`: Running

## Automatic Validation

```bash
./validate.sh
```
---
## Dig Deeper Challenge

You have installed CAPI, but do you understand what lies beneath?
**Your Mission:** Use `kubectl` to inspect the **Custom Resource Definition (CRD)** for `DockerCluster`.
Find out exactly what fields are allowed in the `spec` section. Is there a field to configure the Load Balancer image?

*Hint: `kubectl get crd ...`*

### Need Help?
If you are stuck on this challenge, you can request the solution to be revealed in this file.
Run:
```bash
../module-00-setup/student/request-help.sh module-01-introduction
```
Wait for the instructor to approve, then check this file again.

## Dig Deeper Challenge 2: Audit Logging
Kind supports audit logging. Can you re-create the management cluster with Audit Logging enabled?

*Hint: Check the hints file via the request tool.*

---
[Go to Module 02 ->](../module-02-first-capi-cluster/)