#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Validation Module 02 ==="

# 1. Check Pending
if ! kubectl get cluster first-capi-cluster &> /dev/null; then
    echo "Cluster 'first-capi-cluster' not found."
    exit 100 # PENDING
fi

# 2. Check Progress (Provisioning)
PHASE=$(kubectl get cluster first-capi-cluster -o jsonpath='{.status.phase}')
if [ "$PHASE" == "Provisioning" ]; then
    echo "Cluster is Provisioning..."
    exit 101 # IN_PROGRESS
fi

# 3. Check Machines (Are they Running?)
MACHINES_RUNNING=$(kubectl get machines | grep Running | wc -l)
if [ "$MACHINES_RUNNING" -lt 2 ]; then
    echo "Machines are not yet Running ($MACHINES_RUNNING/2)..."
    exit 101 # IN_PROGRESS
fi

# 4. Check Nodes Ready (CNI installed?)
# We need to use the kubeconfig
if [ ! -f "first-capi-cluster.kubeconfig" ]; then
    # Try to fetch it
    clusterctl get kubeconfig first-capi-cluster > first-capi-cluster.kubeconfig 2>/dev/null
fi

if [ ! -f "first-capi-cluster.kubeconfig" ]; then
     echo "Kubeconfig not found/generated yet."
     exit 101 # IN_PROGRESS
fi

NODES_READY=$(kubectl --kubeconfig=first-capi-cluster.kubeconfig get nodes | grep " Ready" | wc -l)
if [ "$NODES_READY" -lt 2 ]; then
    echo "Nodes are NotReady (CNI missing?)"
    exit 101 # IN_PROGRESS (Because the student is likely installing CNI)
fi

echo -e "${GREEN}MODULE 02 VALIDATED!${NC}"
exit 0