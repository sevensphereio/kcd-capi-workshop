#!/bin/bash
# AUTO-GENERATED from module.yaml by tools/generate-validation.py
# To regenerate: python3 tools/generate-validation.py module-06-ai
source "$(dirname "$0")/../tools/validate-lib.sh"
mod_header "Module 06 — AI Workloads with Ollama"

# --- Stage: Prerequisites ---
ensure_kubeconfig --cluster kosmo-hybrid --output kosmo-hybrid.kubeconfig --label "kubeconfig for kosmo-hybrid cached"
if [ "$ERRORS" -gt 0 ]; then exit_pending "Prerequisites: not ready"; fi

# --- Stage: Ollama operator deployed ---
require_remote_pods --kubeconfig kosmo-hybrid.kubeconfig --namespace ollama-operator-system --grep-status Running --min-count 1 --label "Ollama operator pod Running on kosmo-hybrid"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "Ollama operator deployed: in progress"; fi

# --- Stage: TinyLlama model deployed ---
require_remote_pods --kubeconfig kosmo-hybrid.kubeconfig --selector "model.ollama.ayaka.io/name=tinyllama" --grep-status Running --min-count 1 --label "TinyLlama Model pod Running on kosmo-hybrid"
if [ "$ERRORS" -gt 0 ]; then exit_in_progress "TinyLlama model deployed: in progress"; fi

finish "MODULE 06 VALIDATED!"
