#!/bin/bash
# cleanup.sh — reset module state. Idempotent (errors ignored).
# WARNING: destructive. Pass --yes to confirm.
set +e

if [ "${1:-}" != "--yes" ]; then
    cat <<USAGE
Usage: $0 --yes

This script will DELETE the resources this module created. It is
idempotent — re-running it is safe.

  - Always prefer running cleanup BEFORE retrying a module.
  - The kind management cluster is not touched here unless this is
    module-01-introduction's cleanup. Use ../cleanup-all.sh for a
    full reset.
USAGE
    exit 0
fi

echo ">>> module-10: tearing down golden fleet"

# Golden fleet Helm chart (gold-01, gold-02 CAPI clusters)
helm uninstall golden-fleet 2>/dev/null

# CAAPH HelmChartProxies for the gold fleet (metrics-server, local-path storage,
# and — if you took the CAAPH route for the AI stack — Ollama)
kubectl delete helmchartproxy metrics-gold local-path-gold ollama-ai --ignore-not-found

# k0smotron hosted control plane for the gold env
kubectl delete clusters.k0smotron.io gold-hcp -n default --ignore-not-found

# Any gold CAPI clusters that survived the helm uninstall
kubectl delete cluster gold-01 gold-02 --ignore-not-found

rm -rf golden-fleet
rm -f gold-01.kubeconfig gold-02.kubeconfig
echo "module-10 cleanup done."
