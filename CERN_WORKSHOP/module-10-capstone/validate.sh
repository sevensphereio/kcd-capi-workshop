#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-10-capstone
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 10 — Capstone Challenge"

require_resource_count --kind clusters --pattern "gold-01|gold-02" --min-count 2 --label "Golden fleet clusters (gold-01, gold-02)"

require_field_equals --kind kubeadmcontrolplane --name gold-01-cp --jsonpath '{.spec.replicas}' --expected "3" --label "HA Control Plane (3 replicas)"

# Script check: Metrics Server HelmChartProxy for the gold fleet
if ! ( kubectl get helmchartproxies -o json | jq -e '.items[] | select(.spec.clusterSelector.matchLabels.env=="gold") | select(.spec.chartName=="metrics-server")' ) &>/dev/null; then
    check_ko "Metrics Server HelmChartProxy for the gold fleet"
else
    check_ok "Metrics Server HelmChartProxy for the gold fleet"
fi

# Script check: Ollama running on gold-01
if ! ( if [ ! -f gold-01.kubeconfig ]; then
  clusterctl get kubeconfig gold-01 > gold-01.kubeconfig 2>/dev/null
fi
if [ -f gold-01.kubeconfig ]; then
  kubectl --kubeconfig=gold-01.kubeconfig get pods -n ollama-operator-system | grep Running
else
  false
fi ) &>/dev/null; then
    check_ko "Ollama running on gold-01"
else
    check_ok "Ollama running on gold-01"
fi

# Script check: Kosmotron hosted control plane for the gold env (gold-hcp)
if ! ( # gold-hcp is a k0smotron standalone Cluster (hosted CP = pods, no workers needed)
kubectl get clusters.k0smotron.io gold-hcp -n default >/dev/null 2>&1 && \
kubectl get pods -n default | grep -E 'kmc-gold-hcp' | grep -q Running ) &>/dev/null; then
    check_ko "Kosmotron hosted control plane for the gold env (gold-hcp)"
else
    check_ok "Kosmotron hosted control plane for the gold env (gold-hcp)"
fi

# Script check: Gold fleet observed by dNation (optional: observability)
if ! ( if [ -f ../module-07-observability/.disabled ]; then exit 0; fi
kubectl get pods -n monitoring | grep -q Running ) &>/dev/null; then
    check_ko "Gold fleet observed by dNation (optional: observability)"
else
    check_ok "Gold fleet observed by dNation (optional: observability)"
fi

# Script check: Sveltos profile targets the gold env (optional: sveltos)
if ! ( if [ -f ../module-08-sveltos/.disabled ]; then exit 0; fi
kubectl get clusterprofiles -A 2>/dev/null | grep -q . ) &>/dev/null; then
    check_ko "Sveltos profile targets the gold env (optional: sveltos)"
else
    check_ok "Sveltos profile targets the gold env (optional: sveltos)"
fi

# Script check: KCM manages the gold fleet (optional: kordent)
if ! ( if [ -f ../module-09-kordent/.disabled ]; then exit 0; fi
kubectl get pods -n kcm-system 2>/dev/null | grep -q Running ) &>/dev/null; then
    check_ko "KCM manages the gold fleet (optional: kordent)"
else
    check_ok "KCM manages the gold fleet (optional: kordent)"
fi

finish "MODULE 10 VALIDATED!"
