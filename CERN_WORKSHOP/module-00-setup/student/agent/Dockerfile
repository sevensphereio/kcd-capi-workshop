# CAPI Workshop student agent — default (containerized) run path. The systemd
# unit is the opt-in alternative (AGENT_RUNTIME=systemd in setup.sh).
#
# The image is a self-contained "workshop toolbox": Python + the exact CLI
# toolchain the module validate.sh scripts shell out to. It deliberately does
# NOT bake in agent.py — the agent script and every module's validate.sh come
# from the repo bind-mount at runtime, so the container grades (and unlocks
# reveals into) the SAME working tree the student edits. This guarantees zero
# drift between the containerized and systemd run paths.
#
# Tool versions are kept in sync with module-00-setup/common/install-k8s-tools.sh.
FROM python:3.12-slim-bookworm

# buildx sets TARGETARCH (amd64/arm64). Plain `docker build` leaves it empty —
# fall back to amd64 so the image still builds without buildkit.
ARG TARGETARCH=amd64

# Versions — MUST match module-00-setup/common/install-k8s-tools.sh
ARG KIND_VERSION=v0.30.0
ARG KUBECTL_VERSION=v1.34.2
ARG CLUSTERCTL_VERSION=v1.11.1
ARG HELM_VERSION=v3.19.2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System tools the validate scripts assume on PATH: bash, git, jq, curl,
# coreutils (grep/wc/sed/…) ship in the base. ca-certificates for TLS fetches.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash git jq curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Kubernetes CLIs — pinned, matching the host toolchain.
RUN set -euxo pipefail; \
    arch="${TARGETARCH:-amd64}"; \
    # kubectl \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" \
      -o /usr/local/bin/kubectl; \
    # kind (only needed to satisfy `command -v kind` in module-01) \
    curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${arch}" \
      -o /usr/local/bin/kind; \
    # clusterctl \
    curl -fsSL "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CLUSTERCTL_VERSION}/clusterctl-linux-${arch}" \
      -o /usr/local/bin/clusterctl; \
    chmod +x /usr/local/bin/kubectl /usr/local/bin/kind /usr/local/bin/clusterctl; \
    # helm (tarball) \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${arch}.tar.gz" -o /tmp/helm.tgz; \
    tar -xzf /tmp/helm.tgz -C /tmp; \
    mv "/tmp/linux-${arch}/helm" /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    rm -rf /tmp/helm.tgz "/tmp/linux-${arch}"

# Python deps: `requests` (agent's only hard dep) + `PyYAML` so the agent can
# read module.yaml timeout_seconds/title. The systemd venv installs requests
# only; adding PyYAML here makes per-module timeouts (e.g. module-02's 300s)
# honoured instead of silently defaulting to 60s.
RUN pip install --no-cache-dir requests PyYAML

# HOME must be writable by an arbitrary host UID (the container runs as the
# student's UID:GID so files it writes into the repo stay student-owned).
# 0777 lets any UID create ~/.capi-agent and ~/.kube here.
ENV HOME=/home/agent
RUN mkdir -p /home/agent && chmod 0777 /home/agent

# WORKSHOP_ROOT is the repo bind-mount; the compose/run wrapper sets it.
ENV WORKSHOP_ROOT=/workshop \
    KUBECONFIG=/home/agent/.kube/config

WORKDIR /workshop

# Default command runs the repo's own agent.py (from the mount), so there is a
# single source of truth for the agent logic. Override-able via compose.
CMD ["python3", "-u", "/workshop/module-00-setup/student/agent/agent.py"]
