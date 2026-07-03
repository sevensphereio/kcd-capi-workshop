# Module 10: The Capstone Project

## The Ultimate Challenge
You have learned the individual components: CAPI, templating, CAAPH,
kosmotron hosted control planes, and AI workloads. Now, **you are the
Platform Engineer**.

Your manager wants a new "Golden Fleet" for a high-priority AI project.
You must build it from scratch, composing every tool you have mastered
in the previous modules.

### Benefits & Limitations: Capstone Project

| Benefits ✅ | Limitations ⚠️ |
| :--- | :--- |
| **Synthesize Knowledge:** Apply all learned concepts in one project.<br>**Real-World Scenario:** Mimics a complex platform engineering task.<br>**Problem Solving:** Encourages independent research and debugging. | **Difficulty:** High, requires mastery of previous modules.<br>**Time Consuming:** May take significant effort to complete.<br>**Debugging:** Complex issues can arise from interacting components. |

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

## What the capstone composes

The capstone is deliberately a *composition* exercise: it wires together
the always-on spine of the workshop into a single deliverable.

1. **Golden fleet (module-03 templating + calico-crs)** — two CAPI
   clusters `gold-01` and `gold-02`, templated by a `golden-fleet` Helm
   chart. Both carry the labels `env: gold` and `cni: calico`; `gold-01`
   additionally carries `stack: ai`. Because they are labelled
   `cni: calico`, the **module-03 `calico-crs` ClusterResourceSet**
   installs Calico on them automatically — you write **no new CRS**.
2. **Metrics (module-04 CAAPH)** — a single `HelmChartProxy`
   (`metrics-gold`) whose `clusterSelector` is
   `matchLabels: { env: gold }`. CAAPH installs `metrics-server` on both
   `gold-01` and `gold-02`.
3. **Kosmotron hosted control plane (module-05 kosmotron)** — a
   k0smotron **standalone** `Cluster` named `gold-hcp`, a hosted control
   plane that runs as pods (`kmc-gold-hcp-*`) on the management cluster
   with no dedicated workers. Apply the committed manifest:
   ```bash
   kubectl apply -f gold-hcp.yaml
   ```
   This is the always-on kosmotron leverage; the validator asserts the
   `k0smotron.io` Cluster exists and its `kmc-gold-hcp` pods are Running.
4. **AI workload (module-06 ai)** — the **Ollama Operator** plus the
   **TinyLlama** model on `gold-01` **only**, reusing the local-path +
   operator pattern from module-06. Scope it with a
   `clusterSelector: { matchLabels: { stack: ai } }` (only `gold-01` has
   that label) or apply it directly to `gold-01.kubeconfig`.

---

## Requirements specification

You must deploy a new fleet of clusters named `gold-01` and `gold-02`.

### 1. Infrastructure (CAPI + Helm)
*   Create a **NEW Helm Chart** named `golden-fleet`.
*   Deploy 2 clusters: `gold-01` and `gold-02`.
*   **Architecture:**
    *   **Control Plane:** High Availability (3 replicas).
    *   **Workers:** 1 replica (v1.31.0).
    *   **Labels:** `env: gold`, `cni: calico` on both; `stack: ai` on `gold-01`.

### 2. Networking (CRS)
*   Ensure **Calico** is installed automatically on both clusters by
    re-using the module-03 `calico-crs` (`cni: calico` selector). No new
    CRS needed.

### 3. Applications (CAAPH)
*   Deploy **Metrics Server** to both clusters using a `HelmChartProxy`
    (`metrics-gold`) with `clusterSelector: { env: gold }`.

### 4. Hosted control plane (kosmotron)
*   Apply `gold-hcp.yaml` to create the k0smotron hosted control plane
    `gold-hcp` (pods `kmc-gold-hcp-*` in `default`).

### 5. Workload (AI)
*   Deploy the **Ollama Operator** and **TinyLlama** model to `gold-01`
    ONLY. Do this manually or via CAAPH (your choice), but it must be
    running in `ollama-operator-system`.

---

## Optional modules

If the optional modules are **enabled** (their `.disabled` marker is
removed), the capstone additionally verifies that the gold fleet is
wired into them:

| Optional module              | Extra capstone check                          |
| :--------------------------- | :-------------------------------------------- |
| `module-07-observability`    | gold fleet is monitored (pods Running in `monitoring`) |
| `module-08-sveltos`          | a Sveltos `ClusterProfile` targets the gold env |
| `module-09-kordent`          | KCM manages the gold fleet (pods Running in `kcm-system`) |

These modules are **disabled by default**. Each optional check is
`.disabled`-gated: when the dependency's `../module-0{7,8,9}-*/.disabled`
marker is present, the check short-circuits to success (`exit 0`) so the
auto-generated `validate.sh` passes on the always-on spine without a
cluster for those tools. Enabling an optional module (removing its
`.disabled`) automatically activates its capstone check on the next run —
**no capstone edit needed**. This is the graceful-degradation contract.

---

## Rules
1.  No copy-pasting entire files from previous modules. Try to write the Helm chart structure yourself (or `helm create`).
2.  The validation script is strict. It checks for specific names (`gold-01`, `gold-02`, `golden-fleet`, `gold-hcp`).

---

## 🛠️ Scaffolding (Recommended Approach)

You don't have to start from a blank page. A pre-staged skeleton lives at
`./golden-fleet-skeleton/` — copy it and fill in the `TODO:` markers:

```bash
cp -r golden-fleet-skeleton golden-fleet
$EDITOR golden-fleet/values.yaml          # set up gold-01, gold-02
$EDITOR golden-fleet/templates/cluster.yaml   # use {{ .cpCount }} for HA
helm install golden-fleet ./golden-fleet
kubectl apply -f gold-hcp.yaml            # kosmotron hosted control plane
```

Build order (suggested):

1.  **Chart skeleton** → copy `golden-fleet-skeleton/` and edit
    `values.yaml`. Two clusters: `gold-01`, `gold-02`. `cpCount: 3`,
    `workerCount: 1`, `k8sVersion: v1.31.0`. Both labelled
    `env: gold`, `cni: calico`. `gold-01` additionally `stack: ai`.
2.  **HA control plane** → in `templates/cluster.yaml`, replace the
    hard-coded `replicas: 1` on `KubeadmControlPlane` with
    `replicas: {{ .cpCount }}`.
3.  **Calico** → re-use the `calico-crs` from module 03 (it already
    targets `cni: calico`). No new CRS needed.
4.  **Metrics-server** → write a single `HelmChartProxy` (`metrics-gold`)
    whose `clusterSelector` is `matchLabels: { env: gold }`. CAAPH
    installs it on both `gold-01` and `gold-02`.
5.  **Kosmotron gold-hcp** → `kubectl apply -f gold-hcp.yaml` to stand up
    the hosted control plane (mirrors module-05-kosmotron).
6.  **Ollama on gold-01 only** → scope this with
    `clusterSelector: { matchLabels: { stack: ai } }` (only `gold-01`
    has that label) **or** apply the operator + Model directly to
    `gold-01.kubeconfig` (mirrors module-06-ai).

If you get stuck:

```bash
~/request-help.sh module-10-capstone   # appends challenges/hints.md
# 10 minutes later, run again to escalate to challenges/solution.md
```

---

## Validation
```bash
./validate.sh
```

---
## Dig Deeper Challenge 1: GitOps Pipeline
Imagine you have ArgoCD. How would you structure this repository so that a commit to `values.yaml` triggers the update?
*Conceptual challenge only.*

### Need Help?
If you are stuck on this challenge, you can request the solution to be revealed in this file.
Run:
```bash
~/request-help.sh module-10-capstone
```
Wait for the instructor to approve, then check this file again.

---

⬅️ Previous: [Module 06 — AI Workloads](../module-06-ai/) &nbsp;|&nbsp; 🏁 This is the final module — back to the [Workshop index](../README.md)
