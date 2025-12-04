#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Validation Module 05 ==="
ERRORS=0

# 1. HCP Objects
if kubectl get helmchartproxy metrics-server-blue &> /dev/null && kubectl get helmchartproxy local-path-blue &> /dev/null; then
    echo -e "${GREEN}[OK] HelmChartProxies found.${NC}"
else
    echo -e "${RED}[KO] Missing HelmChartProxies.${NC}"
    ERRORS=$((ERRORS+1))
fi

# 2. Remote Check (Optional if kubeconfig exists)
if [ -f cluster-blue.kubeconfig ]; then
    if kubectl --kubeconfig=cluster-blue.kubeconfig get sc local-path &> /dev/null; then
        echo -e "${GREEN}[OK] StorageClass found on Cluster Blue.${NC}"
    else
        echo -e "${RED}[KO] StorageClass 'local-path' missing on Cluster Blue.${NC}"
        ERRORS=$((ERRORS+1))
    fi
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}MODULE 05 VALIDATED!${NC}"
    exit 0
else
    exit 1
fi