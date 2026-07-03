#!/bin/bash
set -e

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

# Detect real user (for service configuration)
REAL_USER=${SUDO_USER:-$USER}
echo "Running setup for user: $REAL_USER"

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")" # Up: student -> module-00-setup -> root

echo "=== Student Environment Setup ==="

# 1. Run Common Steps
echo ">>> Step 1: System & Docker Setup (Common)"
"$SCRIPT_DIR/../common/install-docker.sh"

echo ">>> Step 2: K8s Tools Setup (Common)"
"$SCRIPT_DIR/../common/install-k8s-tools.sh"

echo ">>> Step 2.5: System Limits Configuration"
"$SCRIPT_DIR/../common/configure-system-limits.sh" -y

echo ">>> Step 3: Validation (Common)"
# Run validation as the real user to check their permissions
sudo -u "$REAL_USER" "$SCRIPT_DIR/../common/validate-env.sh"

# 4. Agent Setup
echo ">>> Step 4: Monitoring Agent Setup"

# Runtime selection: "docker" (default) runs the agent as a container via
# run-agent-docker.sh; "systemd" runs it as a systemd service in a Python venv.
# Set AGENT_RUNTIME=systemd to opt into the legacy systemd path.
AGENT_RUNTIME="${AGENT_RUNTIME:-docker}"
AGENT_DIR="$SCRIPT_DIR/agent"

if [ "$AGENT_RUNTIME" = "systemd" ]; then
    # Check if python3-venv is installed
    if ! dpkg -s python3-venv >/dev/null 2>&1; then
        echo "Installing python3-venv..."
        apt-get update && apt-get install -y python3-venv
    fi

    VENV_DIR="$AGENT_DIR/venv"

    echo "Creating Python Virtual Environment..."
    python3 -m venv "$VENV_DIR"

    echo "Installing Agent dependencies in venv..."
    "$VENV_DIR/bin/pip" install -r "$AGENT_DIR/requirements.txt"
fi

# Ask for Instructor IP
if [ -z "$INSTRUCTOR_IP" ]; then
    echo ""
    echo "--------------------------------------------------------"
    echo "Please enter the IP address of the Instructor's machine."
    echo "This is required for the monitoring dashboard."
    echo "--------------------------------------------------------"
    read -p "Instructor IP (e.g., 192.168.1.X): " INSTRUCTOR_IP
fi

# Ask for Dashboard API Token
if [ -z "$DASHBOARD_API_TOKEN" ]; then
    echo ""
    echo "--------------------------------------------------------"
    echo "Please enter YOUR PERSONAL Dashboard API Token."
    echo "Your instructor mints one per student (it is tied to your"
    echo "machine's name) — ask them for yours. Do not share it."
    echo "--------------------------------------------------------"
    read -p "Your personal Dashboard API Token: " DASHBOARD_API_TOKEN
fi

if [ -z "$DASHBOARD_API_TOKEN" ]; then
    echo "Error: DASHBOARD_API_TOKEN is required."
    exit 1
fi

# Ask for the Student ID. It MUST match the id the instructor used to mint your
# token (the token is HMAC(master, student_id)), and it is the id the agent
# reports under + the id request-help.sh files help requests under. If left
# blank we fall back to this machine's hostname (the agent's own default), so
# the agent and request-help.sh always agree on one identity.
if [ -z "$STUDENT_ID" ]; then
    echo ""
    echo "--------------------------------------------------------"
    echo "Please enter YOUR Student ID (e.g. ws1), exactly as your"
    echo "instructor gave it to you when they minted your token."
    echo "Press Enter to default to this machine's hostname."
    echo "--------------------------------------------------------"
    read -p "Your Student ID [$(hostname -f)]: " STUDENT_ID
fi
STUDENT_ID="${STUDENT_ID:-$(hostname -f)}"
echo "Using Student ID: $STUDENT_ID"

if [ "$AGENT_RUNTIME" = "docker" ]; then
    # --- Containerized agent (default) ---
    echo "Starting Agent as a Docker container (AGENT_RUNTIME=docker)..."
    # Reuse the systemd unit name space: make sure a previously-installed
    # service isn't also running and double-reporting.
    if systemctl list-unit-files 2>/dev/null | grep -q '^capi-agent.service'; then
        echo "Disabling existing capi-agent systemd service to avoid double-reporting..."
        systemctl disable --now capi-agent.service 2>/dev/null || true
    fi
    # run-agent-docker.sh targets $SUDO_USER (the student) for UID/GID + kube dir.
    INSTRUCTOR_IP="$INSTRUCTOR_IP" \
    DASHBOARD_API_TOKEN="$DASHBOARD_API_TOKEN" \
    STUDENT_ID="${STUDENT_ID:-}" \
        "$AGENT_DIR/run-agent-docker.sh" up
else
    # --- Systemd agent (opt-in: AGENT_RUNTIME=systemd) ---
    AGENT_SCRIPT="$AGENT_DIR/agent.py"
    PYTHON_BIN="$VENV_DIR/bin/python3"
    SERVICE_FILE="/etc/systemd/system/capi-agent.service"

    echo "Creating Systemd Service for Agent..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=CAPI Workshop Agent
After=network.target

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$AGENT_DIR
Environment="DASHBOARD_URL=http://$INSTRUCTOR_IP:8000/api/report"
Environment="DASHBOARD_API_TOKEN=$DASHBOARD_API_TOKEN"
Environment="WORKSHOP_ROOT=$REPO_ROOT"
Environment="STUDENT_ID=${STUDENT_ID:-}"
ExecStart=$PYTHON_BIN -u $AGENT_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now capi-agent.service
fi

# 5. User Tools
echo ">>> Step 5: User Tools Setup"
cp "$SCRIPT_DIR/request-help.sh" "/home/$REAL_USER/request-help.sh"
chown "$REAL_USER:$REAL_USER" "/home/$REAL_USER/request-help.sh"
chmod +x "/home/$REAL_USER/request-help.sh"

# Secure the Environment: Remove local solutions
echo ">>> Securing Workshop: Removing local solution files..."
find "$REPO_ROOT" -type d -name "challenges" -exec rm -rf {} +
echo "✅ Solution files removed. You must request them from the instructor."

# Add Dashboard URL, API token, Student ID and workshop root to bashrc if not
# present. request-help.sh relies on all four: the URL + token to reach the
# dashboard, STUDENT_ID so the request is filed (and authorized) under the same
# identity the agent uses, and WORKSHOP_ROOT to locate the agent's captured
# validation output (the exact error) to attach to the request.
BASHRC="/home/$REAL_USER/.bashrc"
if ! grep -q "DASHBOARD_URL" "$BASHRC"; then
    echo "export DASHBOARD_URL=http://$INSTRUCTOR_IP:8000/api/report" >> "$BASHRC"
fi
if ! grep -q "DASHBOARD_API_TOKEN" "$BASHRC"; then
    echo "export DASHBOARD_API_TOKEN=$DASHBOARD_API_TOKEN" >> "$BASHRC"
fi
if ! grep -q "STUDENT_ID" "$BASHRC"; then
    echo "export STUDENT_ID=$STUDENT_ID" >> "$BASHRC"
fi
if ! grep -q "WORKSHOP_ROOT" "$BASHRC"; then
    echo "export WORKSHOP_ROOT=$REPO_ROOT" >> "$BASHRC"
fi

# 6. Code-Server (VS Code) Setup
echo ">>> Step 6: Installing Code-Server (Web IDE)..."
CERT_DIR="/etc/ssl/code-server"
mkdir -p "$CERT_DIR"
CERT_KEY="$CERT_DIR/server.key"
CERT_CRT="$CERT_DIR/server.crt"

if [ ! -f "$CERT_CRT" ]; then
    echo "Generating Self-Signed Certificate for HTTPS..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_KEY" -out "$CERT_CRT" \
        -subj "/CN=$(hostname)/O=CAPI-Workshop/C=US"
fi

# Generate a random Code-Server password instead of a shared default.
CODE_SERVER_PASS="${CODE_SERVER_PASSWORD:-$(openssl rand -base64 12)}"

# Run the installer (common script)
"$SCRIPT_DIR/../common/install-code-server.sh" "$CODE_SERVER_PASS" "$CERT_CRT" "$CERT_KEY"

echo ""
echo "=================================================="
echo "✅ Setup Complete!"
echo "   - Docker & K8s Tools: Installed"
echo "   - Cockpit: Active (https://<YOUR-IP>:9090)"
echo "   - Code-Server: Active (https://<YOUR-IP>:8080)"
echo "       Password: $CODE_SERVER_PASS"
echo "       (save this — it was randomly generated for your machine)"
echo "   - Monitoring Agent: Active (Student ID: $STUDENT_ID → $INSTRUCTOR_IP)"
echo "   - Help Tool: ~/request-help.sh <module-name>"
echo ""
echo "   Need a hint? From a NEW shell (so the env is loaded), run e.g.:"
echo "       ~/request-help.sh module-02-first-capi-cluster"
echo "   Your current validation error is attached automatically, and hints"
echo "   appear in that module's README. Run it again after ~10 min for the"
echo "   full solution."
echo "=================================================="
