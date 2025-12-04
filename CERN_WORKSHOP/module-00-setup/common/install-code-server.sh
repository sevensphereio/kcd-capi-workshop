#!/bin/bash
set -e

# ==============================================================================
# 📝 Install Code-Server (VS Code for Web)
# ==============================================================================
# Installs code-server as a system service accessible on port 8080.
# Usage: sudo ./install-code-server.sh [PASSWORD] [CERT_FILE] [KEY_FILE]
# ==============================================================================

# 1. Configuration
PORT=8080
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
CONFIG_DIR="$USER_HOME/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
PASSWORD=${1:-"workshop123!"}
CERT_FILE=$2
KEY_FILE=$3

echo ">>> Installing Code-Server..."

# 2. Install (Official Script)
if ! command -v code-server &> /dev/null; then
    curl -fsSL https://code-server.dev/install.sh | sh
else
    echo "Code-Server already installed."
fi

# 3. Configure
echo ">>> Configuring Code-Server..."
mkdir -p "$CONFIG_DIR"

if [ -n "$CERT_FILE" ] && [ -n "$KEY_FILE" ]; then
    echo "Configuring HTTPS with provided certificates..."
    # Copy certs to config dir to avoid permission issues
    cp "$CERT_FILE" "$CONFIG_DIR/server.crt"
    cp "$KEY_FILE" "$CONFIG_DIR/server.key"
    chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$CONFIG_DIR/server.crt" "$CONFIG_DIR/server.key"
    
    cat > "$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $PASSWORD
cert: true
cert: $CONFIG_DIR/server.crt
cert-key: $CONFIG_DIR/server.key
EOF
else
    echo "Configuring HTTP (No cert provided)..."
    cat > "$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $PASSWORD
cert: false
EOF
fi

# Fix permissions
chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$USER_HOME/.config"

# 4. Enable Service
echo ">>> Starting Service..."
sudo systemctl enable --now code-server@${SUDO_USER:-$USER}

# 5. Output Info
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=================================================="
echo "✅ Code-Server Installed Successfully!"
echo "   - URL:      http://$IP:$PORT"
echo "   - Password: $PASSWORD"
echo "=================================================="
