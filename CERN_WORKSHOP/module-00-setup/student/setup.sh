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

# Check if python3-venv is installed
if ! dpkg -s python3-venv >/dev/null 2>&1; then
    echo "Installing python3-venv..."
    apt-get update && apt-get install -y python3-venv
fi

AGENT_DIR="$SCRIPT_DIR/agent"
VENV_DIR="$AGENT_DIR/venv"

echo "Creating Python Virtual Environment..."
python3 -m venv "$VENV_DIR"

echo "Installing Agent dependencies in venv..."
"$VENV_DIR/bin/pip" install -r "$AGENT_DIR/requirements.txt"

# Ask for Instructor IP
if [ -z "$INSTRUCTOR_IP" ]; then
    echo ""
    echo "--------------------------------------------------------"
    echo "Please enter the IP address of the Instructor's machine."
    echo "This is required for the monitoring dashboard."
    echo "--------------------------------------------------------"
    read -p "Instructor IP (e.g., 192.168.1.X): " INSTRUCTOR_IP
fi

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
Environment="WORKSHOP_ROOT=$REPO_ROOT"
ExecStart=$PYTHON_BIN -u $AGENT_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now capi-agent.service

# 5. User Tools
echo ">>> Step 5: User Tools Setup"
cp "$SCRIPT_DIR/request-help.sh" "/home/$REAL_USER/request-help.sh"
chown "$REAL_USER:$REAL_USER" "/home/$REAL_USER/request-help.sh"
chmod +x "/home/$REAL_USER/request-help.sh"

# Secure the Environment: Remove local solutions
echo ">>> Securing Workshop: Removing local solution files..."
find "$REPO_ROOT" -type d -name "challenges" -exec rm -rf {} +
echo "✅ Solution files removed. You must request them from the instructor."

# Add Dashboard URL to bashrc if not present
BASHRC="/home/$REAL_USER/.bashrc"
if ! grep -q "DASHBOARD_URL" "$BASHRC"; then
    echo "export DASHBOARD_URL=http://$INSTRUCTOR_IP:8000/api/report" >> "$BASHRC"
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

# Run the installer (common script)
"$SCRIPT_DIR/../common/install-code-server.sh" "student123" "$CERT_CRT" "$CERT_KEY"

echo ""
echo "=================================================="
echo "✅ Setup Complete!"
echo "   - Docker & K8s Tools: Installed"
echo "   - Cockpit: Active (https://<YOUR-IP>:9090)"
echo "   - Code-Server: Active (https://<YOUR-IP>:8080)"
echo "   - Monitoring Agent: Active (Sending to $INSTRUCTOR_IP)"
echo "   - Help Tool: ~/request-help.sh"
echo "=================================================="
