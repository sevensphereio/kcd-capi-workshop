#!/bin/bash
set -e

AGENT_DIR="/home/ubuntu/CERN_WORKSHOP/module-00-setup/student/agent"
VENV_DIR="$AGENT_DIR/venv"
SERVICE_FILE="/etc/systemd/system/capi-agent.service"

# Preserve Instructor IP by reading old service file
OLD_ENV=$(grep "Environment=\"DASHBOARD_URL" "$SERVICE_FILE" || echo "")

echo ">>> Checking venv..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install requests

echo ">>> Fixing Systemd Service..."
cat <<EOF > agent.service.tmp
[Unit]
Description=CAPI Workshop Agent
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$AGENT_DIR
$OLD_ENV
Environment="WORKSHOP_ROOT=/home/ubuntu/CERN_WORKSHOP"
ExecStart=$VENV_DIR/bin/python3 -u agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv agent.service.tmp "$SERVICE_FILE"

echo ">>> Reloading & Restarting..."
sudo systemctl daemon-reload
sudo systemctl enable capi-agent
sudo systemctl restart capi-agent

sleep 2
if systemctl is-active --quiet capi-agent; then
    echo "✅ Agent is ACTIVE."
else
    echo "❌ Agent failed to start. Logs:"
    sudo journalctl -u capi-agent -n 20 --no-pager
fi

