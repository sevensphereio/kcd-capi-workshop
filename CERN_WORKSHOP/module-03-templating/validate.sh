#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-03-templating
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 03 — Templating with Helm"

# --- Stage: Prerequisites ---
require_tool helm --label "helm CLI installed"
require_context kind-capi-mgmt --label "Management context active"
require_resource configmap calico-cni --label "calico-cni ConfigMap created"
if [ "$ERRORS" -gt 0 ]; then exit_pending "Prerequisites: not ready"; fi

# --- Stage: ClusterResourceSets created ---
require_resource clusterresourceset calico-crs --label "calico-crs"
require_resource clusterresourceset security-policy --label "security-policy CRS"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "ClusterResourceSets created: in progress"; fi

# --- Stage: Fleet provisioned ---
require_resource_count --kind clusters --pattern "cluster-blue|cluster-green|cluster-red" --min-count 3 --label "blue/green/red clusters present"
# Script check: all 3 fleet clusters Provisioned
if ! ( phases=$(kubectl get clusters -o json 2>/dev/null \
  | jq -r '.items[] | select(.metadata.name | test("^cluster-(blue|green|red)$")) | .status.phase' 2>/dev/null)
test "$(echo "$phases" | grep -c Provisioned)" -ge 3 ) &>/dev/null; then
    check_ko "all 3 fleet clusters Provisioned"
else
    check_ok "all 3 fleet clusters Provisioned"
fi
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Fleet provisioned: in progress"; fi

finish "MODULE 03 VALIDATED!"
