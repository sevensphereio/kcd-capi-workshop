# Module 04: Application Management with CAAPH

## Objectives
*   **Helm Addon Provider:** Install and understand the CAAPH controller.
*   **Declarative App Deployment:** Deploy **Metrics Server** and **Local Path Provisioner** to our new fleet (`cluster-blue`).

---

## Deep Dive: The Add-on Problem
In Kubernetes, managing the cluster lifecycle is solved (CAPI). But managing what runs *inside* (CNI, CSI, Metrics, Ingress) is harder.
CAAPH bridges this gap. It watches for `HelmChartProxy` objects on the Management Cluster and projects Helm Releases onto Workload Clusters.

**Why not just use Helm locally?**
Because you have 100 clusters. You don't want to switch context 100 times. With CAAPH, you apply 1 YAML on the management cluster, and 100 clusters get updated.

### ⚖️ Benefits & Limitations: CAAPH (Addon Provider)

| Benefits ✅ | Limitations ⚠️ |
| :--- | :--- |
| **Centralized:** Install apps on child clusters from the parent.<br>**No SSH/Kubeconfig:** No need to access the child cluster directly.<br>**Lifecycle:** Auto-updates apps when the chart version changes. | **Debugging:** Logs are on the Mgmt cluster, errors are harder to find.<br>**Delay:** Propagation takes time.<br>**Dependencies:** Hard to manage complex app dependencies. |

---

## 💡 Important: Kubeconfig Context
Ensure your `kubectl` context is pointing to the **Management Cluster** (`capi-mgmt`) before executing commands in this module, unless otherwise specified. If in doubt, set your environment variable:
```bash
export KUBECONFIG=../module-01-introduction/capi-mgmt.kubeconfig
kubectl config current-context
```
**Example Output:**
```text
kind-capi-mgmt
```

---

## 🛠️ Step 1: Install Provider

### 1. Initialization
We install the **Addon Provider** component on the Management Cluster. This spins up the CAAPH controller pod.
```bash
clusterctl init --addon helm:v0.5.2
```
**Example Output:**
```text
Fetching providers
Installing Provider="helm" Version="v0.2.0" TargetNamespace="caaph-system"
```

### 2. Verification
Ensure the pod is running.
```bash
kubectl get pods -n caaph-system
```
**Example Output:**
```text
NAME                                   READY   STATUS    RESTARTS   AGE
caaph-controller-manager-xyz           1/1     Running   0          45s
```

---

## 📦 Exercise 1: Metrics Server

We will target **Cluster Blue** (`cluster.x-k8s.io/cluster-name: cluster-blue`).

### 1. Create Manifest
We define a `HelmChartProxy` object. This tells CAAPH:
*   **Where:** Target clusters matching `cluster-blue`.
*   **What:** The `metrics-server` chart from the official repo.
*   **How:** Install it into the `metrics` namespace with specific values.

Create `metrics-server.yaml`:
```yaml
apiVersion: addons.cluster.x-k8s.io/v1alpha1
kind: HelmChartProxy
metadata:
  name: metrics-server-blue
spec:
  clusterSelector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: cluster-blue
  repoURL: https://kubernetes-sigs.github.io/metrics-server/
  chartName: metrics-server
  version: 3.12.1
  options:
    install:
      createNamespace: true
  valuesTemplate: |
    args:
      - --kubelet-insecure-tls
```

### 2. Apply
Submit this CR to the Management Cluster.
```bash
kubectl apply -f metrics-server.yaml
```
**Example Output:**
```text
helmchartproxy.addons.cluster.x-k8s.io/metrics-server-blue created
```

---

## 💾 Exercise 2: Storage Class (Local Path)

By default, Kind clusters (Docker) don't have a dynamic provisioner when managed by CAPI (unless extra mounted). Let's install the standard Rancher `local-path-provisioner`.

### 1. Create Manifest
This proxy installs a Storage Class provider. Note that `valuesTemplate` allows us to configure the chart just like a local `values.yaml`.

Create `local-path.yaml`:
```yaml
apiVersion: addons.cluster.x-k8s.io/v1alpha1
kind: HelmChartProxy
metadata:
  name: local-path-blue
spec:
  clusterSelector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: cluster-blue
  repoURL: https://charts.rancher.io
  chartName: local-path-provisioner
  version: 0.0.30
  options:
    install:
      createNamespace: true
  valuesTemplate: |
    storageClass:
      defaultClass: true
```

### 2. Apply
```bash
kubectl apply -f local-path.yaml
```
**Example Output:**
```text
helmchartproxy.addons.cluster.x-k8s.io/local-path-blue created
```

---

## 🔍 Verification

Wait for `cluster-blue` to be fully provisioned (from Module 04).

### 1. Check Proxies
Verify that the Management Cluster has accepted the proxies.
```bash
kubectl get helmchartproxies
```
**Example Output:**
```text
NAME                  READY   REASON
metrics-server-blue   True    
local-path-blue       True    
```

### 2. Check Workload Cluster
Log into Cluster Blue to confirm the apps are actually running.
```bash
clusterctl get kubeconfig cluster-blue > cluster-blue.kubeconfig
kubectl --kubeconfig=cluster-blue.kubeconfig get pods -A
kubectl --kubeconfig=cluster-blue.kubeconfig get sc
```
**Example Output:**
```text
NAMESPACE       NAME                                      READY   STATUS    RESTARTS   AGE
default         metrics-server-xyz                        1/1     Running   0          1m
local-path      local-path-provisioner-xyz                1/1     Running   0          1m
...
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default) rancher.io/local-path   Delete          WaitForFirstConsumer   false                  2m
```

## Validation
```bash
./validate.sh
```
---
## Dig Deeper Challenge

Metrics are nice, but certificates are critical.

**Your Mission:** Deploy **cert-manager** to `cluster-blue` using CAAPH.
*Hint: You need to add the Jetstack repo (`https://charts.jetstack.io`) and ensure `installCRDs: true` is set in the values.*

### Need Help?
If you are stuck on this challenge, you can request the solution to be revealed in this file.
Run:
```bash
~/request-help.sh module-04-caaph
```
Wait for the instructor to approve, then check this file again.

### Dig Deeper Challenge 2: Private Registry Secret
Can you use CAAPH to inject a Docker Registry Secret (imagePullSecret) into the workload cluster?

*Hint: Check the hints file via the request tool.*

---
[Go to Module 05 ->](../module-05-ai/)