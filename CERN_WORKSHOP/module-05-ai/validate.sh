#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Validation Module 06 (AI) ==="
ERRORS=0

# 1. Kubeconfig Check
if [ ! -f cluster-red.kubeconfig ]; then
    clusterctl get kubeconfig cluster-red > cluster-red.kubeconfig 2>/dev/null
fi

if [ ! -f cluster-red.kubeconfig ]; then
    echo -e "${RED}[KO] cluster-red.kubeconfig not found (Cluster Red missing?).${NC}"
    exit 1
fi

# 2. Operator Check
echo -n "Checking Ollama Operator... "
if kubectl --kubeconfig=cluster-red.kubeconfig get pods -n ollama-system | grep -q Running; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[KO] Operator not running on Cluster Red.${NC}"
    ERRORS=$((ERRORS+1))
fi

# 3. Model Check
echo -n "Checking Model Pod... "
# Filter for pods controlled by the model
if kubectl --kubeconfig=cluster-red.kubeconfig get pods -l ollama.nekomeowww.com/model-name=tinyllama | grep -q Running; then
    echo -e "${GREEN}[OK] Model Pod Running.${NC}"
else
    echo -e "${RED}[KO] Model Pod not found or not running.${NC}"
    ERRORS=$((ERRORS+1))
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}MODULE 06 VALIDATED!${NC}"
    exit 0
else
    exit 1
fi
