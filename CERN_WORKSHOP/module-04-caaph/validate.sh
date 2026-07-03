#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-04-caaph
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 04 — Cluster API Add-on Provider Helm"

# --- Stage: Prerequisites ---
require_tool helm --label "helm CLI installed"
require_context kind-capi-mgmt --label "Management context active"
require_crds helmchartproxies.addons.cluster.x-k8s.io helmreleaseproxies.addons.cluster.x-k8s.io --label "CAAPH CRDs installed"
if [ "$ERRORS" -gt 0 ]; then exit_pending "Prerequisites: not ready"; fi

# --- Stage: HelmChartProxies declared ---
require_resource helmchartproxy metrics-server-blue --label "metrics-server-blue HelmChartProxy"
require_resource helmchartproxy local-path-blue --label "local-path-blue HelmChartProxy"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "HelmChartProxies declared: in progress"; fi

# --- Stage: Add-ons reconciled on cluster-blue ---
ensure_kubeconfig --cluster cluster-blue --output cluster-blue.kubeconfig --label "kubeconfig for cluster-blue cached"
require_remote_pods --kubeconfig cluster-blue.kubeconfig --namespace kube-system --selector "app.kubernetes.io/name=metrics-server" --min-count 1 --label "metrics-server pods running on cluster-blue"
require_remote_resource --kubeconfig cluster-blue.kubeconfig storageclass local-path --label "local-path StorageClass exists on cluster-blue"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Add-ons reconciled on cluster-blue: in progress"; fi

finish "MODULE 04 VALIDATED!"
