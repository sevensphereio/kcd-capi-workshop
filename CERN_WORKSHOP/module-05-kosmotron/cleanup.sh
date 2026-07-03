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

echo ">>> module-05: tearing down k0smotron HCPs + hybrid CAPI cluster"
# 1. Hybrid CAPI cluster + its k0smotron control plane (Step 3 manifest).
kubectl delete -f 2-capi-kosmo-cluster.yaml --ignore-not-found --wait=false 2>/dev/null
# 2. The multi-tenant hosted control planes (Step 2 manifest).
kubectl delete -f 1-multi-hcp.yaml --ignore-not-found --wait=false 2>/dev/null
# 3. (Optional) remove the k0smotron operator itself. Uncomment for a full reset.
# kubectl delete -f https://docs.k0smotron.io/stable/install.yaml --ignore-not-found 2>/dev/null
# kubectl delete ns k0smotron --ignore-not-found
echo "module-05 cleanup done."
