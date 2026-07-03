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

echo ">>> module-03: uninstalling helm fleet + CRS objects"
helm uninstall my-fleet 2>/dev/null
kubectl delete clusterresourceset calico-crs security-policy --ignore-not-found
kubectl delete configmap calico-cni company-banner --ignore-not-found
echo "module-03 cleanup done."
