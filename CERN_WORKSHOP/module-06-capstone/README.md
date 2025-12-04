# Module 06: The Capstone Project

## The Ultimate Challenge
You have learned the individual components: CAPI, Helm, CAAPH, and AI.
Now, **you are the Platform Engineer**.

Your manager wants a new "Golden Fleet" for a high-priority AI project.
You must build it from scratch, using all the tools you've mastered.

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

## Requirements specification

You must deploy a new fleet of clusters named `gold-01` and `gold-02`.

### 1. Infrastructure (CAPI + Helm)
*   Create a **NEW Helm Chart** named `golden-fleet`.
*   Deploy 2 clusters: `gold-01` and `gold-02`.
*   **Architecture:**
    *   **Control Plane:** High Availability (3 replicas).
    *   **Workers:** 1 replica (v1.31.0).
    *   **Labels:** `env: gold`, `stack: ai`.

### 2. Networking (CRS)
*   Ensure **Calico** is installed automatically on both clusters using `ClusterResourceSet`.

### 3. Applications (CAAPH)
*   Deploy **Metrics Server** to both clusters using `HelmChartProxy`.

### 4. Workload (AI)
*   Deploy the **Ollama Operator** and **TinyLlama** model to `gold-01` ONLY.
*   *Constraint:* Do this manually or via CAAPH (your choice), but it must be running.

---

## Rules
1.  No copy-pasting entire files from previous modules. Try to write the Helm chart structure yourself (or `helm create`).
2.  The validation script is strict. It checks for specific names (`gold-01`, `gold-02`, `golden-fleet`).

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
~/request-help.sh module-06-capstone
```
Wait for the instructor to approve, then check this file again.