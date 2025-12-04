#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Validation Module 04 ==="
ERRORS=0

# 1. CRS
if kubectl get clusterresourceset calico-crs &> /dev/null && kubectl get clusterresourceset security-policy &> /dev/null; then
    echo -e "${GREEN}[OK] CRS objects found.${NC}"
else
    echo -e "${RED}[KO] Missing CRS (calico-crs or security-policy).${NC}"
    ERRORS=$((ERRORS+1))
fi

# 2. Fleet
CLUSTERS=$(kubectl get clusters --no-headers | grep -E "cluster-blue|cluster-green|cluster-red" | wc -l)
if [ "$CLUSTERS" -eq 3 ]; then
    echo -e "${GREEN}[OK] All 3 clusters found.${NC}"
else
    echo -e "${RED}[KO] Expected 3 clusters (blue/green/red), found $CLUSTERS.${NC}"
    ERRORS=$((ERRORS+1))
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}MODULE 04 VALIDATED!${NC}"
    exit 0
else
    exit 1
fi