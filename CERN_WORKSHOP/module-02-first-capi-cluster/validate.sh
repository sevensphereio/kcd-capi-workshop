#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-02-first-capi-cluster
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 02 — First Workload Cluster"

# --- Stage: Cluster Created ---
require_resource cluster first-capi-cluster --label "Cluster resource exists"
if [ "$ERRORS" -gt 0 ]; then exit_pending "Cluster Created: not ready"; fi

# --- Stage: Cluster Provisioning ---
require_field_equals --kind cluster --name first-capi-cluster --jsonpath '{.status.phase}' --expected "Provisioned" --in-progress-values "Provisioning|Pending" --label "Cluster phase is Provisioned"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Cluster Provisioning: in progress"; fi

# --- Stage: Machines Running ---
# Script check: At least 2 machines running
if ! ( [ $(kubectl get machines | grep Running | wc -l) -ge 2 ] ) &>/dev/null; then
    check_ko "At least 2 machines running"
else
    check_ok "At least 2 machines running"
fi
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Machines Running: in progress"; fi

# --- Stage: Kubeconfig & CNI ---
ensure_kubeconfig --cluster first-capi-cluster --output first-capi-cluster.kubeconfig --label "Kubeconfig for first-capi-cluster"
require_nodes_ready --kubeconfig first-capi-cluster.kubeconfig --min-count 2 --label "Nodes ready (CNI installed)"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Kubeconfig & CNI: in progress"; fi

finish "MODULE 02 VALIDATED!"
