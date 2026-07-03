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

echo ">>> module-06: removing Ollama Model + operator from kosmo-hybrid"
if [ -f kosmo-hybrid.kubeconfig ]; then
    kubectl --kubeconfig=kosmo-hybrid.kubeconfig delete model tinyllama --ignore-not-found
    kubectl --kubeconfig=kosmo-hybrid.kubeconfig delete ns ollama-operator-system --ignore-not-found
fi
rm -f kosmo-hybrid.kubeconfig
echo "module-06 cleanup done."
