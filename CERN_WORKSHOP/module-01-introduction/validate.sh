#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-01-introduction
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 01 — Management Cluster Setup"

# --- Stage: Prerequisites ---
require_tool kind --label "kind CLI installed"
require_context kind-capi-mgmt --label "Management cluster context exists"
if [ "$ERRORS" -gt 0 ]; then exit_pending "Prerequisites: not ready"; fi

# --- Stage: CAPI Initialization ---
require_pods_running --pattern "capi|capd|cert-manager" --min-count 1 --label "CAPI/CAPD pods created"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "CAPI Initialization: in progress"; fi

# --- Stage: CAPI Ready ---
require_pods_running --pattern "capi|capd|cert-manager" --grep-status Running --min-count 8 --label "CAPI pods running"
# Script check: No CrashLoopBackOff pods
if ! ( ! kubectl get pods -A | grep CrashLoopBackOff ) &>/dev/null; then
    check_ko "No CrashLoopBackOff pods"
else
    check_ok "No CrashLoopBackOff pods"
fi
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "CAPI Ready: in progress"; fi

finish "MODULE 01 VALIDATED!"
