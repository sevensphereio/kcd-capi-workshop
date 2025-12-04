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
2.  **Enter Instructor IP:**
    The script will ask for the Instructor's IP. This connects your progress agent to the class dashboard.

3.  **Verify:**
    Run `docker ps`. You should see it working.

---

## 🗺️ 2. The Journey

Follow the modules sequentially. Each directory contains a `README.md` with instructions.

| Module | Topic | Goal |
| :--- | :--- | :--- |
| **01** | [Introduction](./module-01-introduction/) | Build the Management Cluster 🧠 |
| **02** | [Workload Cluster](./module-02-first-capi-cluster/) | Deploy your first cluster 🚀 |
| **03** | [Templating](./module-03-templating/) | Deploy a Fleet (Dev/Staging/Prod) 🏭 |
| **04** | [CAAPH](./module-04-caaph/) | Manage Apps (Addons) 📦 |
| **05** | [AI](./module-05-ai/) | Run LLMs on Kubernetes 🤖 |

---

## ✅ 3. Validation

At the end of each module, run the validation script to check your work:
```bash
./validate.sh
```
If it prints **[OK]**, you can move to the next module.

---

## 🆘 4. Getting Help

Each module has a **"Dig Deeper"** challenge at the end. These are tough!
If you get stuck:

1.  **Request Hints:**
    ```bash
    ~/request-help.sh module-XX-name
    ```
    The instructor will approve, and hints will appear in your README.

2.  **Request Solution:**
    Still stuck after 10 minutes? Run the same command again to request the full solution.

---

## 🖥️ 5. Tools

*   **Web Terminal:** Access `https://<YOUR-IP>:9090` (Login: your linux user).
*   **VS Code (Web):** Access `http://<YOUR-IP>:8080` (Optional, if installed).

Enjoy the workshop!
