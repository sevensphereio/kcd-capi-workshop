#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Validation Module 06 (Capstone) ==="
ERRORS=0

# 1. Check Fleet
echo -n "Checking Golden Fleet... "
COUNT=$(kubectl get clusters --no-headers | grep -E "gold-01|gold-02" | wc -l)
if [ "$COUNT" -ge 2 ]; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[KO] Found $COUNT/2 clusters (gold-01, gold-02)${NC}"
    ERRORS=$((ERRORS+1))
fi

# 2. Check HA CP
echo -n "Checking HA Control Plane (gold-01)... "
CP_REPLICAS=$(kubectl get kubeadmcontrolplane gold-01-cp -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [ "$CP_REPLICAS" -eq 3 ]; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[KO] Expected 3 replicas, found $CP_REPLICAS${NC}"
    ERRORS=$((ERRORS+1))
fi

# 3. Check Metrics Server (CAAPH)
echo -n "Checking Metrics Server Proxy... "
# Student might name it anything, so we look for any proxy targeting gold-01 with metrics-server chart
PROXY=$(kubectl get helmchartproxies -o json | jq '.items[] | select(.spec.clusterSelector.matchLabels."cluster.x-k8s.io/cluster-name"=="gold-01") | select(.spec.chartName=="metrics-server")')
if [ -n "$PROXY" ]; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[KO] No HelmChartProxy found for metrics-server on gold-01${NC}"
    ERRORS=$((ERRORS+1))
fi

# 4. Check AI (Remote)
echo -n "Checking AI on gold-01... "
if [ ! -f gold-01.kubeconfig ]; then
    clusterctl get kubeconfig gold-01 > gold-01.kubeconfig 2>/dev/null
fi

if [ -f gold-01.kubeconfig ]; then
    if kubectl --kubeconfig=gold-01.kubeconfig get pods -n ollama-system | grep -q Running; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[KO] Ollama operator not running on gold-01${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "${RED}[SKIPPED] Kubeconfig missing${NC}"
    ERRORS=$((ERRORS+1))
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}CAPSTONE PASSED! YOU ARE A CAPI MASTER!${NC}"
    exit 0
else
    exit 1
fi
