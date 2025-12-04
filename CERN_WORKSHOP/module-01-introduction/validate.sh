#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Validation Module 01 ==="

# 0. Check Start (Pending)
if ! command -v kind &> /dev/null; then
    echo "Tools not installed yet."
    exit 100 # PENDING
fi

if ! kubectl config get-contexts kind-capi-mgmt &> /dev/null; then
    echo "Cluster 'capi-mgmt' does not exist yet."
    exit 100 # PENDING
fi

# 1. Check Progress (Cluster exists, but pods initializing)
# Check if CAPI pods are created but not ready
POD_COUNT=$(kubectl get pods -A | grep -E 'capi|capd|cert-manager' | wc -l)

if [ "$POD_COUNT" -eq 0 ]; then
    echo "Cluster exists but CAPI is not initialized."
    exit 101 # IN_PROGRESS
fi

# 2. Check Success
RUNNING_PODS=$(kubectl get pods -A | grep -E 'capi|capd|cert-manager' | grep "Running" | wc -l)
TOTAL_EXPECTED=8 # Approx

if [ "$RUNNING_PODS" -ge 4 ]; then
     # At least some pods running
     if [ "$RUNNING_PODS" -ge "$TOTAL_EXPECTED" ]; then
         echo -e "${GREEN}MODULE 01 VALIDATED!${NC}"
         exit 0
     else
         echo "CAPI is initializing ($RUNNING_PODS/$TOTAL_EXPECTED pods running)..."
         exit 101 # IN_PROGRESS
     fi
else
    # Pods exist but failing/pending for too long?
    # Simple check: If they are CrashLoopBackOff -> FAIL
    if kubectl get pods -A | grep "CrashLoopBackOff"; then
        exit 1 # FAIL
    fi
    exit 101 # IN_PROGRESS
fi
