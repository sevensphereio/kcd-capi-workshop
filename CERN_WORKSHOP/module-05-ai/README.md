# Module 05: AI Workloads (Ollama)

## Objectives
We will turn our **Production Cluster (Red)** into an AI Kubernetes platform.
We will deploy the Ollama stack manually to understand the components before automating it later.

### Benefits & Limitations: AI on Kubernetes

| Benefits | Limitations |
| :--- | :--- |
| **Scalability:** Scale inference pods horizontally.<br>**Portability:** Run the same model on AWS, Azure, or Laptop.<br>**Ecosystem:** Integrate with monitoring, ingress, security tools. | **Resource Hungry:** LLMs need massive RAM/GPU.<br>**Image Size:** Downloading 10GB models takes time.<br>**Scheduling:** Needs advanced scheduling (bin-packing) to be efficient. |

---

## Important: Kubeconfig Context
Ensure your `kubectl` context is pointing to the **Management Cluster** (`capi-mgmt`) before executing commands in this module, unless otherwise specified. If in doubt, set your environment variable:
```bash
export KUBECONFIG=$../module-01-introduction/capi-mgmt.kubeconfig
kubectl config current-context
```
**Example Output:**
```text
kind-capi-mgmt
```

---

## Step 1: Install the Operator

We will install the operator directly onto **Cluster Red**.

### 1. Get Access
First, ensure we have the credentials for Cluster Red.
```bash
clusterctl get kubeconfig cluster-red > cluster-red.kubeconfig
```

### 2. Apply Manifests
We use the `--kubeconfig` flag to target the workload cluster directly. This mimics a "Manual" administrator action, contrasting with the automated approaches seen earlier.
```bash
kubectl --kubeconfig=cluster-red.kubeconfig \
  apply -f https://raw.githubusercontent.com/nekomeowww/ollama-operator/v0.10.1/dist/install.yaml
```
**Example Output:**
```text
namespace/ollama-system created
customresourcedefinition.apiextensions.k8s.io/models.ollama.nekomeowww.com created
...
deployment.apps/ollama-operator-controller-manager created
```

**Verification:**
Check if the controller is running in the `ollama-system` namespace.
```bash
kubectl --kubeconfig=cluster-red.kubeconfig get pods -n ollama-system
```
**Example Output:**
```text
NAME                                                 READY   STATUS    RESTARTS   AGE
ollama-operator-controller-manager-xyz               2/2     Running   0          30s
```

---

## Step 2: Deploy the Model

Now we ask the operator to download and run **TinyLlama** (a small, fast model suitable for labs).

### 1. Create Manifest
This Custom Resource (`Model`) tells the operator which LLM to fetch.
Create `tinyllama.yaml`:
```yaml
apiVersion: ollama.nekomeowww.com/v1alpha1
kind: Model
metadata:
  name: tinyllama
  namespace: default
spec:
  model: tinyllama
  replicas: 1
```

### 2. Apply
```bash
kubectl --kubeconfig=cluster-red.kubeconfig apply -f tinyllama.yaml
```
**Example Output:**
```text
model.ollama.nekomeowww.com/tinyllama created
```

### 3. Watch the Download
The operator will spawn a pod. It first downloads the model (~600MB). This can take 2-5 minutes depending on your connection.
```bash
kubectl --kubeconfig=cluster-red.kubeconfig get pods -w
```
**Example Output:**
```text
NAME            READY   STATUS              RESTARTS   AGE
ollama-xyz      0/1     ContainerCreating   0          5s
ollama-xyz      0/1     Running             0          10s
ollama-xyz      1/1     Running             0          3m
```

---

## Step 3: Chat with the Cluster

Now that the model is loaded, let's query it.

### 1. Port Forward
Since the service is running inside the cluster network, we open a tunnel from our laptop to the service port (11434).
```bash
kubectl --kubeconfig=cluster-red.kubeconfig port-forward svc/ollama 11434:80
```
**Example Output:**
```text
Forwarding from 127.0.0.1:11434 -> 80
Forwarding from [::1]:11434 -> 80
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
  "created_at": "2024-...",
  "response": "The sky appears blue because of Rayleigh scattering...",
  "done": true
}
```

If you get a JSON response with text, your Kubernetes cluster is now an AI Platform!



## Validation
```bash
./validate.sh
```

---
### Dig Deeper Challenge 1: Expose via LoadBalancer

Currently, we access AI via `port-forward`. That's not production-ready.
**Your Mission:** Edit the Service created by the operator to be of type `NodePort` or `LoadBalancer`.
Find the port and try to access it directly from your terminal without the tunnel.

### Dig Deeper Challenge 2: Ollama Native Interaction

You are currently using `curl` to talk to the API. It's ugly.
**Your Mission:** Use the **official Ollama CLI binary** (installed on your student VM) to talk directly to your remote cluster.
You need to find a way to tell the local `ollama run` command to use your port-forwarded address (`localhost:11434`) instead of trying to start a local server.

*Hint: Environment Variables are your friend.*

### Need Help?
If you are stuck on this challenge, you can request the solution to be revealed in this file.
Run:
```bash
~/request-help.sh module-05-ai
```
Wait for the instructor to approve, then check this file again.

---
[Go to Module 06 ->](../module-06-observability/)