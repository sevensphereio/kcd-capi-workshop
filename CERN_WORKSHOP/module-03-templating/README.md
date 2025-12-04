# Module 03: Templating & Resource Management

## Objectives
*   **Mass Deployment:** Use Helm to deploy a fleet of 3 clusters (`Blue`, `Green`, `Red`) with specific configurations.
*   **ClusterResourceSet (CRS):** Deep dive into the "ApplyOnce" vs "Reconcile" modes for automatic resource injection (CNI, Configs).

### Benefits & Limitations: Helm Fleet Management

| Benefits | Limitations |
| :--- | :--- |
| **DRY:** One template for N clusters.<br>**Consistency:** All clusters look the same.<br>**Speed:** Deploy 50 clusters in one command. | **Rigidity:** Hard to handle specific edge cases per cluster.<br>**Helm Complexity:** Templating YAML in YAML can get messy.<br>**Drift:** If manual changes happen, Helm might overwrite them (or fail). |

---

## Important: Kubeconfig Context
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

## Step 0: Cleanup Previous Clusters

## Deep Dive: ClusterResourceSet (CRS)

Typically, when you create a Kubernetes cluster (especially with CAPI), it is "uninitialized". It lacks a CNI (Network Interface) and nodes remain `NotReady`.
`ClusterResourceSet` allows you to automatically apply YAML manifests (ConfigMaps/Secrets) to any cluster matching a label selector.

### Modes of Operation
There are two strategies defined by the `mode` field:

1.  **ApplyOnce (Default):**
    *   **Behavior:** The resource is applied *only once* when the cluster is created.
    *   **Use Case:** Installing a CNI or initial setup. If the user later modifies the resource on the workload cluster, CAPI *will not* overwrite it. This allows "Day 2" customization by the user.
    *   **Risk:** If the user deletes the resource, it is not recreated automatically.

2.  **Reconcile:**
    *   **Behavior:** The controller constantly monitors the resource. If the version on the workload cluster drifts (changes) from the Management Cluster's definition, CAPI *forces* it back.
    *   **Use Case:** Enforcing strict compliance (e.g., Security Policies, RBAC). The user *cannot* modify these resources permanently.

---

## Exercise 1: Zero-Touch CNI (ApplyOnce)

We will set up Calico to be installed automatically on all our future clusters using the default `ApplyOnce` mode.

### 1. Store the Manifest
CAPI's `ClusterResourceSet` controller lives on the Management Cluster. It needs to access the YAML it will inject into workload clusters. We store the Calico YAML inside a Kubernetes **ConfigMap** so CAPI can read it.

```bash
wget https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O calico.yaml
kubectl create configmap calico-cni --from-file=calico.yaml
```
**Example Output:**
```text
configmap/calico-cni created
```

### 2. Create the CRS
We define a `ClusterResourceSet` that links the **Label Selector** (`cni: calico`) to the **Resource** (`calico-cni` ConfigMap).

Create `crs-calico.yaml`:
```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta2
kind: ClusterResourceSet
metadata:
  name: calico-crs
spec:
  strategy: ApplyOnce 
  clusterSelector:
    matchLabels:
      cni: calico
  resources:
  - kind: ConfigMap
    name: calico-cni
```

Apply the CRS definition to the Management Cluster.
```bash
kubectl apply -f crs-calico.yaml
```
**Example Output:**
```text
clusterresourceset.addons.cluster.x-k8s.io/calico-crs created
```

---

## Exercise 2: Strict Policy (Reconcile)

We want to enforce a specific "Company Banner" ConfigMap on all clusters. If a user deletes it, it must come back.

### 1. Create the Resource
Create a simple ConfigMap manifest locally: banner.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: company-banner
  namespace: default
data:
  message: "PROPERTY OF KORDENT CORP - UNAUTHORIZED ACCESS PROHIBITED"
```

Store it in the Management Cluster so CAPI can access it.
```bash
kubectl create configmap company-banner --from-file=banner.yaml
```
**Example Output:**
```text
configmap/company-banner created
```

### 2. Create the Strict CRS
This CRS uses `mode: Reconcile`. It targets clusters labeled `env: prod`.

the file will be called: crs-security.yaml
```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta2
kind: ClusterResourceSet
metadata:
  name: security-policy
spec:
  strategy: Reconcile  # <--- FORCE MODE
  clusterSelector:
    matchLabels:
      env: prod    # Only for production clusters
  resources:
  - kind: ConfigMap
    name: company-banner
```

Apply it.
```bash
kubectl apply -f crs-security.yaml
```
**Example Output:**
```text
clusterresourceset.addons.cluster.x-k8s.io/security-policy created
```

**HINT:** you can list the created clusterresourcesets using `kubectl get clusterresourcesets`
---

## Exercise 3: Deploying the Fleet (Helm)

We will now deploy 3 clusters.

### Concept: Labels as Policy Selectors
In CAPI and Sveltos, **Labels are Power**.
We don't assign resources to "Cluster X" by name. We assign them to "Any cluster with label Y".

*   `cni: calico` → Triggers the **Calico CRS** (installs networking).
*   `env: prod` → Triggers the **Security CRS** (installs banner) and later the **Production Profile**.
*   `env: staging` → Triggers the **Staging Profile**.

Note how we assign these labels in `helm-fleet/values.yaml`:
*   **Blue:** `cni: calico`, `env: dev` -> Gets Calico (ApplyOnce).
*   **Green:** `cni: calico`, `env: staging` -> Gets Calico (ApplyOnce).
*   **Red:** `cni: calico`, `env: prod` -> Gets Calico (ApplyOnce) AND Banner (Reconcile).

### 1. Deploy
Helm renders the templates and applies them to the Management Cluster. This creates 3 `Cluster` objects, 3 `DockerCluster` objects, etc.
```bash
helm install my-fleet ./helm-fleet
```
**Example Output:**
```text
NAME: my-fleet
LAST DEPLOYED: Mon Nov 24 10:00:00 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

### 2. Monitor Provisioning
Watch CAPI react to these new objects.
```bash
kubectl get clusters
```
**Example Output:**
```text
NAME                 PHASE          AGE   VERSION
first-capi-cluster   Provisioned    1h    v1.31.0
cluster-blue         Provisioning   10s   v1.31.0
cluster-green        Provisioning   10s   v1.31.0
cluster-red          Provisioning   10s   v1.31.0
```

---

## Exercise 4: Testing the Drift (Demo)

Wait for **Cluster Red** to be ready (kubeconfig available).

### 1. Get Access
Retrieve the credentials for the production cluster.
```bash
clusterctl get kubeconfig cluster-red > cluster-red.kubeconfig
```

### 2. Verify Presence
Check that the "Company Banner" was automatically created.
```bash
kubectl --kubeconfig=cluster-red.kubeconfig get cm company-banner
```
**Example Output:**
```text
NAME             DATA   AGE
company-banner   1      2m
```

### 3. Try to Delete (The Reconcile Test)
Simulate a malicious user or accidental deletion on the workload cluster.
```bash
kubectl --kubeconfig=cluster-red.kubeconfig delete cm company-banner
```
**Example Output:**
```text
configmap "company-banner" deleted
```

Wait 30-60 seconds...

Check if it came back. The CAPI controller should have detected the drift and re-applied the ConfigMap.
```bash
kubectl --kubeconfig=cluster-red.kubeconfig get cm company-banner
```
**Example Output:**
```text
NAME             DATA   AGE
company-banner   1      5s
```

### 4. Try modifying Calico (The ApplyOnce Test)
If you were to delete Calico resources on `cluster-blue`, they **would not** come back automatically, because `calico-crs` uses `ApplyOnce`.

## Validation
```bash
./validate.sh
```

---
## Dig Deeper Challenge 1: Variable Worker Count

Modify the Helm chart so you can override the worker count specifically for the 'red' cluster in values.yaml.
In values.yaml, add a 'workerCount' field to the cluster object. In the template, use `{{ .workerCount | default 1 }}`.

## Dig Deeper Challenge 2: Fleet Explosion

You deployed 3 clusters (Blue/Green/Red). That's cute.
**Your Mission:** Modify your Helm Values (`values.yaml`) to deploy **5 new clusters** (`mass-01` to `mass-05`) without writing 5 separate blocks of YAML.
You might need to refactor your `values.yaml` to accept a `count` or `range` parameter.

### Need Help?
If you are stuck on this challenge, you can request the solution to be revealed in this file.
Run:
```bash
~/request-help.sh module-03-templating
```
Wait for the instructor to approve, then check this file again.

---
[Go to Module 04 ->](../module-04-caaph/)