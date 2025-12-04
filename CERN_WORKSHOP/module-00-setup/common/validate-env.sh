#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Environment Validation ==="

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}[KO] $1 is not installed or not in PATH.${NC}"
        return 1
    else
        VERSION=$($1 version --client --short 2>/dev/null || $1 version 2>/dev/null || echo "Detected")
        echo -e "${GREEN}[OK] $1 is present.${NC} ($VERSION)"
        return 0
    fi
}

ERRORS=0

# 1. Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[KO] Docker is not installed.${NC}"
    ERRORS=$((ERRORS+1))
else
    if docker ps > /dev/null 2>&1; then
         echo -e "${GREEN}[OK] Docker is running and user has permissions.${NC}"
    else
         echo -e "${RED}[KO] Docker is installed but cannot contact daemon. (Did you run 'newgrp docker'?)${NC}"
         ERRORS=$((ERRORS+1))
    fi
fi

# 2. Check Tools
check_command kubectl || ERRORS=$((ERRORS+1))
check_command kind || ERRORS=$((ERRORS+1))
check_command clusterctl || ERRORS=$((ERRORS+1))
check_command helm || ERRORS=$((ERRORS+1))

# 3. Check Cockpit
if systemctl is-active --quiet cockpit.socket || systemctl is-active --quiet cockpit; then
    echo -e "${GREEN}[OK] Cockpit is active.${NC}"
else
    echo -e "${RED}[KO] Cockpit is not active (systemctl status cockpit.socket).${NC}"
    ERRORS=$((ERRORS+1))
fi

# 4. Result
echo "-------------------------------------"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}ALL SYSTEMS OPERATIONAL!${NC}"
    echo "You can start Module 01."
else
    echo -e "${RED}There are $ERRORS error(s) to fix before starting.${NC}"
    exit 1
fi
