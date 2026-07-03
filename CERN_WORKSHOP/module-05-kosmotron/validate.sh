#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-05-kosmotron
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 05 — Kosmotron Hosted Control Planes"

# --- Stage: Operator Ready ---
require_pods_running --namespace k0smotron --grep-status Running --min-count 1 --label "Kosmotron (k0smotron) operator running"
if [ "$ERRORS" -gt 0 ]; then exit_pending "Operator Ready: not ready"; fi

# --- Stage: Tenants Created ---
# Script check: Hosted control planes (tenant-a, tenant-b)
if ! ( [ $(kubectl get clusters.k0smotron.io -n default 2>/dev/null | grep -E 'tenant-a|tenant-b' | wc -l) -ge 2 ] ) &>/dev/null; then
    check_ko "Hosted control planes (tenant-a, tenant-b)"
else
    check_ok "Hosted control planes (tenant-a, tenant-b)"
fi
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Tenants Created: in progress"; fi

# --- Stage: Hybrid Cluster ---
require_resource cluster kosmo-hybrid --label "Hybrid cluster exists"
# Script check: Hybrid cluster has workers
if ! ( kubectl get machinedeployment -l cluster.x-k8s.io/cluster-name=kosmo-hybrid -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q . ) &>/dev/null; then
    check_ko "Hybrid cluster has workers"
else
    check_ok "Hybrid cluster has workers"
fi
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Hybrid Cluster: in progress"; fi

finish "MODULE 05 VALIDATED!"
