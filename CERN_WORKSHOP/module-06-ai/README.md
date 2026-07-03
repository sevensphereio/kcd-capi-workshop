# Module 06: AI Workloads (Ollama Operator)

## 🎯 Objectives
We will turn our **kosmo-hybrid** cluster into an AI Powerhouse using the **Ollama Operator** (by nekomeowww).
This operator automates the lifecycle of the Ollama server and the model downloading process.

`kosmo-hybrid` is the cluster you built in **Module 05 (kosmotron)** — a
k0smotron **hosted control plane** (running as pods on the management cluster)
that drives real CAPD worker nodes. Because it is a labeled CAPI `Cluster`
(`cluster.x-k8s.io/cluster-name: kosmo-hybrid`), every pattern we learned for
CAPD workload clusters — including CAAPH `HelmChartProxy` addons — works here
unchanged; we just retarget the cluster selector.

### 🧠 Concept: The AI Stack on Kubernetes
1.  **Operator:** The controller that watches for `Ollama` and `Model` resources.
2.  **Ollama Server:** The inference engine managed by the operator.
3.  **Model:** The definition of the weights (e.g., `tinyllama`) to fetch.

---

## ⚠️ Dependency: complete Module 05 first

> **This module cannot run until [Module 05 (kosmotron)](../module-05-kosmotron/)
> is complete AND its `kosmo-hybrid` worker node(s) are `Ready`.**
>
> The TinyLlama Model pulls ~600MB of weights into a PVC, so it needs a **Ready
> worker node** to schedule on and a **working dynamic storage provisioner** to
> bind the PVC. If `kosmo-hybrid` has no Ready worker, the Model pod stays
> `Pending` forever. Confirm the worker is up before you start:
> ```bash
> clusterctl get kubeconfig kosmo-hybrid > kosmo-hybrid.kubeconfig
> kubectl --kubeconfig=kosmo-hybrid.kubeconfig get nodes
> # a worker node must show STATUS=Ready
> ```

---

## 💡 Important: Kubeconfig Context
The `clusterctl` and `HelmChartProxy` commands run against the **Management
Cluster** (`capi-mgmt`); the operator/model commands run against
`kosmo-hybrid` via `--kubeconfig=kosmo-hybrid.kubeconfig`. If in doubt about
your management context:
```bash
export KUBECONFIG=$(pwd)/../module-01-introduction/capi-mgmt.kubeconfig
kubectl config current-context
```
**Example Output:**
```text
kind-capi-mgmt
```

---

## 🛠️ Step 1: Install the Operator

We will install the operator directly onto **kosmo-hybrid**.

### 1. Get Access
First, fetch the credentials for the hybrid cluster (this is a hosted control
plane, so `clusterctl` extracts the kubeconfig from the management cluster):
```bash
clusterctl get kubeconfig kosmo-hybrid > kosmo-hybrid.kubeconfig
```

### 2. Provision storage on kosmo-hybrid
The `kosmo-hybrid` cluster has **no dynamic storage provisioner** — but the
Ollama Model needs a PVC to store the model weights. Install `local-path` as the
default StorageClass on kosmo-hybrid via CAAPH (same `HelmChartProxy` pattern as
Module 04, retargeted to the hybrid cluster's label):
```bash
kubectl apply -f local-path-hybrid.yaml   # HelmChartProxy targeting kosmo-hybrid
```
Wait until the StorageClass appears:
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig get sc
# local-path (default)  ...
```

> **Fallback — if the CAAPH HelmChartProxy on the hosted cluster is flaky:**
> the k0smotron-hosted data plane can occasionally leave the `HelmChartProxy`
> reconcile stuck (no StorageClass ever appears). If so, skip CAAPH and install
> the provisioner directly against the hybrid kubeconfig:
> ```bash
> kubectl --kubeconfig=kosmo-hybrid.kubeconfig apply -f \
>   https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
> # then mark it default:
> kubectl --kubeconfig=kosmo-hybrid.kubeconfig annotate sc local-path \
>   storageclass.kubernetes.io/is-default-class=true --overwrite
> ```

### 3. Apply Manifests
Install a **pinned** operator release. The CRD it ships is large, so we use
**server-side apply** (a client-side `kubectl apply` fails with
`metadata.annotations: Too long`):
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig apply --server-side \
  -f https://raw.githubusercontent.com/nekomeowww/ollama-operator/v0.10.10/dist/install.yaml
```
The bundled metrics sidecar points at the retired `gcr.io/kubebuilder`
registry, so repoint it at the maintained mirror:
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig -n ollama-operator-system \
  set image deploy/ollama-operator-controller-manager \
  kube-rbac-proxy=quay.io/brancz/kube-rbac-proxy:v0.15.0
```

**Verification:**
Check if the controller is running in the `ollama-operator-system` namespace.
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig get pods -n ollama-operator-system
```
**Example Output:**
```text
NAME                                                 READY   STATUS    RESTARTS   AGE
ollama-operator-controller-manager-xyz               2/2     Running   0          30s
```

---

## 🧠 Step 2: Deploy the Model

Now we ask the operator to download and run **TinyLlama**.

### 1. Create Manifest
This Custom Resource (`Model`) tells the operator which LLM to fetch.
**Note:** The API Group is `ollama.ayaka.io`. Since our workers are CAPD (single
node) we explicitly set `ReadWriteOnce` for storage.

Create `tinyllama.yaml`:
```yaml
apiVersion: ollama.ayaka.io/v1
kind: Model
metadata:
  name: tinyllama
  namespace: default
spec:
  image: tinyllama
  replicas: 1
  storageClassName: local-path
  persistentVolume:
    accessMode: ReadWriteOnce
```
> **Note:** the `v0.10.x` Model schema has no `spec.persistentVolume.size`
> field — the operator sizes the weights PVC itself. Use `storageClassName` to
> point at the `local-path` class you installed above.

### 2. Apply
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig apply -f tinyllama.yaml
```
**Example Output:**
```text
model.ollama.ayaka.io/tinyllama created
```

### 3. Watch the Download
The operator will spawn a pod. It first downloads the model (~600MB). This can take 2-5 minutes depending on your connection.
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig get pods -w
```
**Example Output:**
```text
NAME            READY   STATUS              RESTARTS   AGE
tinyllama-xyz   0/1     ContainerCreating   0          5s
tinyllama-xyz   0/1     Running             0          10s
tinyllama-xyz   1/1     Running             0          3m
```

---

## 🗣️ Step 3: Chat with the Cluster

Now that the model is loaded, let's query it.

### 1. Port Forward
Since the service is running inside the cluster network, we open a tunnel from our laptop to the service port (11434).
The operator creates a Service named after the model.
```bash
kubectl --kubeconfig=kosmo-hybrid.kubeconfig port-forward svc/tinyllama 11434:11434
```
**Example Output:**
```text
Forwarding from 127.0.0.1:11434 -> 11434
Forwarding from [::1]:11434 -> 11434
```

### 2. Inference (Curl)
In another terminal, send a prompt to the API.
```bash
curl http://localhost:11434/api/generate -d 
'{ 
  "model": "tinyllama",
  "prompt": "Why is the sky blue?",
  "stream": false
}'
```
**Example Output:**
```json
{
  "model": "tinyllama",
  "created_at": "2024-...".
  "response": "The sky appears blue because of Rayleigh scattering...",
  "done": true
}
```

---
## 🔮 What's Next?
You have completed the guided learning path spine:
*   **Module 01:** Management Cluster
*   **Module 02:** First Workload Cluster
*   **Module 03:** Templating & Fleets
*   **Module 04:** Addon Management
*   **Module 05:** kosmotron (hosted control planes)
*   **Module 06:** AI Workloads (this module)

Next up is **Module 07 (Observability)** — note the observability, sveltos, and
kordent modules are **optional (disabled by default)**. When you are ready to
prove your skills end-to-end, jump to the **capstone (Module 10)**.

[← Back to Module 05 (kosmotron)](../module-05-kosmotron/) · [Go to Module 07 (Observability, optional) →](../module-07-observability/)

## ✅ Validation
```bash
./validate.sh
```

---
### 🧠 Dig Deeper Challenge 1: Expose via LoadBalancer

Currently, we access AI via `port-forward`.
**Your Mission:** Edit the Service created by the operator to be of type `NodePort` or `LoadBalancer`.
Find the port and try to access it directly from your terminal without the tunnel.

### 🧠 Dig Deeper Challenge 2: Ollama Native Interaction

You are currently using `curl` to talk to the API.
**Your Mission:** Use the **official Ollama CLI binary** (installed on your student VM) to talk directly to your remote cluster.
You need to find a way to tell the local `ollama run` command to use your port-forwarded address (`localhost:11434`) instead of trying to start a local server.

*Hint: Environment Variables are your friend.*

### 🆘 Need Help?
Run:
```bash
~/request-help.sh module-06-ai
```
