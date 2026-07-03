# Student agent — run paths

The agent polls every module's `validate.sh`, reports progress to the
instructor dashboard (`/api/report`), and applies HMAC-signed reveals into the
student's working tree. It can run **two ways**; both execute the same
`agent.py` against the same repo checkout.

## 1. Docker container (default)

`../setup.sh` builds the image and starts the agent as a container — this is
what a normal student setup now uses. The image bakes the pinned CLI
toolchain (kubectl / clusterctl / helm / kind — versions tracked with
`../../common/install-k8s-tools.sh`) but **not** `agent.py`: the script and the
module `validate.sh` files come from the repo bind-mount, so there is a single
source of truth and zero drift from the systemd path.

### Via setup.sh (default)
```bash
sudo ./setup.sh          # AGENT_RUNTIME defaults to docker
```
This disables any pre-existing `capi-agent` systemd service (so you don't
double-report) and starts the container.

### Standalone (optional — drive the container directly)
```bash
# build + run (generates a private .env, git-ignored — it holds your token)
INSTRUCTOR_IP=192.168.1.100 \
DASHBOARD_API_TOKEN=<your-per-student-token> \
STUDENT_ID=ws1 \
  ./run-agent-docker.sh up

./run-agent-docker.sh logs     # follow output
./run-agent-docker.sh status   # container state
./run-agent-docker.sh down     # stop + remove
```

### Why these container settings
- **`network_mode: host`** — the kind management cluster's kubeconfig points at
  `127.0.0.1:<port>` and CAPD workload clusters live on the Docker bridge; both
  are only reachable from the host network namespace.
- **Runs as the student's UID:GID** — kubeconfigs, `validation_output/`, and
  unlocked reveal markdown written into the repo stay student-owned, not root.
- **`~/.kube` mounted read-only**, repo mounted read-write.
- **No Docker socket** — the validate scripts never invoke the `kind`/`docker`
  daemon (the `kind` binary is present only for a `command -v kind` check).

### Requirements
Docker with the Compose plugin (`docker compose`) or legacy `docker-compose`.
The student must have created the kind management cluster (module-01) before the
agent can reach any cluster; until then modules simply report `PENDING`.

## 2. systemd service (opt-in)

The legacy path: a Python venv plus a `capi-agent.service` unit, no container.
Choose it explicitly with:
```bash
sudo AGENT_RUNTIME=systemd ./setup.sh
```
Manage it with `systemctl {status,restart,stop} capi-agent` and read logs via
`journalctl -u capi-agent -f`.
