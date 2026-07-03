# 🚀 Student Guide: CAPI workshop

Welcome! You are about to build a modern Kubernetes Platform using Cluster API.

## 🛠️ 1. Setup Your Machine

You should be on a Linux machine (Ubuntu 22.04+ recommended).

1.  **Run the Setup Script:**
    ```bash
    cd module-00-setup/student
    export DASHBOARD_URL=http://142.44.160.188:8000
    export INSTRUCTOR_IP=142.44.160.188
    sudo ./setup.sh
    ```
2.  **Enter Instructor IP and your personal token:**
    The script asks for the Instructor's IP and **your personal Dashboard
    API token**. Your instructor mints one token per student (tied to your
    machine's name) — ask them for yours and don't share it. This connects
    your progress agent to the class dashboard.

3.  **Verify:**
    Run `docker ps`. You should see it working.

---

## 🗺️ 2. The Journey

Follow the modules sequentially. Each directory contains a `README.md` with instructions.

| Module | Topic | Goal |
| :--- | :--- | :--- |
| **01** | [Introduction](./module-01-introduction/) | Build the Management Cluster 🧠 |
| **02** | [Workload Cluster](./module-02-first-capi-cluster/) | Deploy your first cluster 🚀 |
| **03** | [Templating](./module-03-templating/) | Deploy a Fleet (blue/green/red) 🏭 |
| **04** | [CAAPH](./module-04-caaph/) | Manage add-ons via HelmChartProxy 📦 |
| **05** | [Kosmotron](./module-05-kosmotron/) | Hosted Control Planes ☁️ |
| **06** | [AI](./module-06-ai/) | Run LLMs on Kubernetes 🤖 |
| **07** | [Observability](./module-07-observability/) | Federated Prometheus + Grafana 📊 *(optional)* |
| **08** | [Sveltos](./module-08-sveltos/) | Drift detection & policy 🛡️ *(optional)* |
| **09** | [Kordent](./module-09-kordent/) | Platform layer above CAPI 🧩 *(optional)* |
| **10** | [Capstone](./module-10-capstone/) | Build a golden fleet from scratch 🏆 |

> Modules 07–09 are **optional** and disabled by default. To enable one, set `enabled: true` in its `module.yaml` and regenerate (or remove its `.disabled` marker).

---

## ✅ 3. Validation

At the end of each module, run the validation script to check your work:
```bash
./validate.sh
```
If it exits 0 (you'll see `MODULE NN VALIDATED!`) you can move to the next
module. Exit codes 100 (PENDING) and 101 (IN_PROGRESS) mean the script is
still waiting for asynchronous resources to come up — re-run after a minute.

For a global view across every module:
```bash
./verify-all.sh   # from the repo root, runs all modules in parallel
```

## 🧹 3.5 Reset (per-module)

Stuck on a module and want a clean retry without nuking the whole lab?
Each module ships a `cleanup.sh`:
```bash
cd module-NN-name
./cleanup.sh --yes   # idempotent; tears down only what this module created
```

To reset everything (including the kind management cluster):
```bash
./cleanup-all.sh --yes   # from the repo root
```

The `--yes` flag is mandatory — running the scripts without it just
prints the usage. This is intentional: the cleanup is destructive and
silent destruction is bad pedagogy.

---

## 🆘 4. Getting Help

Each module has a **"Dig Deeper"** challenge at the end. These are tough!
If you get stuck, ask the instructor for help straight from your terminal.

`setup.sh` already configured everything the help tool needs (your dashboard
URL, your personal token, your **Student ID**, and the workshop path). Just
**open a new shell** (so those exports are loaded) and run:

1.  **Request Hints:**
    ```bash
    ~/request-help.sh module-02-first-capi-cluster
    ```
    Use the real module directory name (e.g. `module-02-first-capi-cluster`).
    The tool automatically attaches **the exact validation error you are
    currently hitting** — the same output the monitoring agent captured when it
    last graded that module — so the instructor sees precisely where you are
    stuck. You'll see:
    ```
    ✅ Request sent! Instructor notified for HINTS.
    ```
    Once the instructor approves, the hints are appended to that module's
    `README.md` (watch it refresh in your editor).

2.  **Request Solution:**
    Still stuck after ~10 minutes? Run the **same command again** — it escalates
    to a request for the full solution, which the instructor can then release.

> **Note on your Student ID.** Your token is tied to a specific Student ID
> (e.g. `ws1`) that your instructor gave you and that you entered during
> `setup.sh`. It is exported as `STUDENT_ID` in your `~/.bashrc`, and both the
> monitoring agent and `request-help.sh` use it, so your progress and your help
> requests always show up under the same name on the dashboard. If
> `request-help.sh` ever reports a `403`/authorization error, check that
> `echo $STUDENT_ID` matches the id your instructor minted your token for.

---

## 🖥️ 5. Tools

*   **Web Terminal:** Access `https://<YOUR-IP>:9090` (Login: your linux user).
*   **VS Code (Web):** Access `http://<YOUR-IP>:8080` (Optional, if installed).

Enjoy the workshop!
