#!/bin/bash
# validate-lib.sh — Shared validation library for CAPI Workshop modules
# Sourced by generated validate.sh scripts.
# Do not execute directly.

# --- Colors & State ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'
ERRORS=0

# --- Output Helpers ---
mod_header() {
    echo "=== Validation $1 ==="
}

check_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

check_ko() {
    echo -e "${RED}[KO] $1${NC}"
    ERRORS=$((ERRORS + 1))
}

# --- Exit Helpers ---
finish() {
    if [ "$ERRORS" -eq 0 ]; then
        echo -e "${GREEN}${1:-VALIDATED!}${NC}"
        exit 0
    else
        echo -e "${RED}FAILURE: $ERRORS error(s) detected.${NC}"
        exit 1
    fi
}

exit_pending() {
    echo "${1:-Not started yet.}"
    exit 100
}

exit_in_progress() {
    echo "${1:-Still in progress...}"
    exit 101
}

# --- Check Functions ---

# require_tool TOOL [--label LABEL]
require_tool() {
    local tool="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) tool="$1"; shift ;;
        esac
    done
    label="${label:-$tool installed}"
    if command -v "$tool" &>/dev/null; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_context CONTEXT [--label LABEL]
require_context() {
    local context="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) context="$1"; shift ;;
        esac
    done
    label="${label:-Context $context exists}"
    if kubectl config get-contexts "$context" &>/dev/null; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_resource KIND NAME [NAME2 ...] [--label LABEL]
# All named resources must exist (AND logic).
require_resource() {
    local kind="" label="" names=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *)
                if [ -z "$kind" ]; then
                    kind="$1"
                else
                    names+=("$1")
                fi
                shift ;;
        esac
    done
    label="${label:-$kind ${names[*]} exists}"
    local ok=true
    for name in "${names[@]}"; do
        if ! kubectl get "$kind" "$name" &>/dev/null; then
            ok=false
            break
        fi
    done
    if $ok; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_field_equals --kind KIND --name NAME --jsonpath PATH --expected VAL [--label LABEL]
# Optional: --in-progress-values "val1|val2" — if current value matches, return 1 without incrementing ERRORS
require_field_equals() {
    local kind="" name="" jsonpath="" expected="" label="" in_progress_values=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kind) kind="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            --jsonpath) jsonpath="$2"; shift 2 ;;
            --expected) expected="$2"; shift 2 ;;
            --in-progress-values) in_progress_values="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-$kind $name field check}"
    local actual
    actual=$(kubectl get "$kind" "$name" -o jsonpath="$jsonpath" 2>/dev/null)
    if [ "$actual" == "$expected" ]; then
        check_ok "$label"
    else
        if [ -n "$in_progress_values" ] && echo "$actual" | grep -qE "$in_progress_values"; then
            echo -e "${YELLOW}[..] $label ($actual)${NC}"
            return 1
        fi
        check_ko "$label (got: $actual, expected: $expected)"
        return 1
    fi
}

# require_pods_running [--namespace NS] [--selector SEL] [--pattern PAT] [--grep-status STATUS] [--min-count N] [--label LABEL]
require_pods_running() {
    local namespace="" selector="" pattern="" grep_status="Running" min_count=1 label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --selector) selector="$2"; shift 2 ;;
            --pattern) pattern="$2"; shift 2 ;;
            --grep-status) grep_status="$2"; shift 2 ;;
            --min-count) min_count="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-Pods running}"

    local cmd="kubectl get pods"
    if [ -n "$namespace" ]; then
        cmd="$cmd -n $namespace"
    else
        cmd="$cmd -A"
    fi
    if [ -n "$selector" ]; then
        cmd="$cmd -l $selector"
    fi

    local output
    output=$(eval "$cmd" 2>/dev/null)
    if [ -n "$pattern" ]; then
        output=$(echo "$output" | grep -E "$pattern")
    fi
    if [ -n "$grep_status" ]; then
        output=$(echo "$output" | grep "$grep_status")
    fi

    local count=0
    if [ -n "$output" ]; then
        count=$(printf '%s\n' "$output" | grep -c .)
    fi

    if [ "$count" -ge "$min_count" ]; then
        check_ok "$label ($count pods)"
    else
        check_ko "$label ($count/$min_count pods)"
        return 1
    fi
}

# require_resource_count --kind KIND [--pattern PAT] --min-count N [--label LABEL]
require_resource_count() {
    local kind="" pattern="" min_count=1 label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kind) kind="$2"; shift 2 ;;
            --pattern) pattern="$2"; shift 2 ;;
            --min-count) min_count="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-$kind count check}"

    local output
    output=$(kubectl get "$kind" --no-headers 2>/dev/null)
    if [ -n "$pattern" ]; then
        output=$(echo "$output" | grep -E "$pattern")
    fi

    local count=0
    if [ -n "$output" ]; then
        count=$(printf '%s\n' "$output" | grep -c .)
    fi

    if [ "$count" -ge "$min_count" ]; then
        check_ok "$label ($count found)"
    else
        check_ko "$label ($count/$min_count)"
        return 1
    fi
}

# require_nodes_ready [--kubeconfig FILE] [--min-count N] [--label LABEL]
require_nodes_ready() {
    local kubeconfig="" min_count=1 label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kubeconfig) kubeconfig="$2"; shift 2 ;;
            --min-count) min_count="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-Nodes ready}"

    local cmd="kubectl"
    if [ -n "$kubeconfig" ]; then
        cmd="$cmd --kubeconfig=$kubeconfig"
    fi
    cmd="$cmd get nodes"

    local count
    count=$(eval "$cmd" 2>/dev/null | grep " Ready" | wc -l)

    if [ "$count" -ge "$min_count" ]; then
        check_ok "$label ($count nodes)"
    else
        check_ko "$label ($count/$min_count nodes)"
        return 1
    fi
}

# ensure_kubeconfig --cluster CLUSTER --output FILE [--label LABEL]
# Fetches kubeconfig if not already present. Returns 1 if it cannot be fetched.
ensure_kubeconfig() {
    local cluster="" output="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="$2"; shift 2 ;;
            --output) output="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-Kubeconfig for $cluster}"

    if [ ! -f "$output" ]; then
        clusterctl get kubeconfig "$cluster" > "$output" 2>/dev/null
    fi

    if [ -f "$output" ] && [ -s "$output" ]; then
        check_ok "$label"
    else
        check_ko "$label (could not fetch)"
        rm -f "$output"
        return 1
    fi
}

# require_remote_resource --kubeconfig FILE KIND NAME [--label LABEL]
require_remote_resource() {
    local kubeconfig="" kind="" name="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kubeconfig) kubeconfig="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *)
                if [ -z "$kind" ]; then
                    kind="$1"
                else
                    name="$1"
                fi
                shift ;;
        esac
    done
    label="${label:-Remote $kind $name}"

    if [ ! -f "$kubeconfig" ]; then
        check_ko "$label (kubeconfig missing)"
        return 1
    fi

    if kubectl --kubeconfig="$kubeconfig" get "$kind" "$name" &>/dev/null; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_remote_pods --kubeconfig FILE [--namespace NS] [--selector SEL] [--pattern PAT] [--grep-status STATUS] [--min-count N] [--label LABEL]
require_remote_pods() {
    local kubeconfig="" namespace="" selector="" pattern="" grep_status="" min_count=1 label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kubeconfig) kubeconfig="$2"; shift 2 ;;
            --namespace) namespace="$2"; shift 2 ;;
            --selector) selector="$2"; shift 2 ;;
            --pattern) pattern="$2"; shift 2 ;;
            --grep-status) grep_status="$2"; shift 2 ;;
            --min-count) min_count="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-Remote pods running}"

    if [ ! -f "$kubeconfig" ]; then
        check_ko "$label (kubeconfig missing)"
        return 1
    fi

    local cmd="kubectl --kubeconfig=$kubeconfig get pods"
    if [ -n "$namespace" ]; then
        cmd="$cmd -n $namespace"
    fi
    if [ -n "$selector" ]; then
        cmd="$cmd -l $selector"
    fi

    local output
    output=$(eval "$cmd" 2>/dev/null)
    if [ -n "$pattern" ]; then
        output=$(echo "$output" | grep -E "$pattern")
    fi
    if [ -n "$grep_status" ]; then
        output=$(echo "$output" | grep "$grep_status")
    fi

    local count=0
    if [ -n "$output" ]; then
        count=$(printf '%s\n' "$output" | grep -c .)
    fi

    if [ "$count" -ge "$min_count" ]; then
        check_ok "$label ($count pods)"
    else
        check_ko "$label ($count/$min_count pods)"
        return 1
    fi
}

# --- New Check Functions ---

# require_helm_release --release NAME --namespace NS [--status STATUS] [--label LABEL]
require_helm_release() {
    local release="" namespace="" expected_status="deployed" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release) release="$2"; shift 2 ;;
            --namespace) namespace="$2"; shift 2 ;;
            --status) expected_status="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-Helm release $release in $namespace}"

    if ! command -v helm &>/dev/null; then
        check_ko "$label (helm not installed)"
        return 1
    fi

    local actual_status
    actual_status=$(helm status "$release" -n "$namespace" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ "$actual_status" == "$expected_status" ]; then
        check_ok "$label"
    else
        check_ko "$label (status: ${actual_status:-not found}, expected: $expected_status)"
        return 1
    fi
}

# require_namespace NAMESPACE [--label LABEL]
require_namespace() {
    local namespace="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) namespace="$1"; shift ;;
        esac
    done
    label="${label:-Namespace $namespace exists}"

    if kubectl get namespace "$namespace" &>/dev/null; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_crds CRD_NAME [CRD_NAME2 ...] [--label LABEL]
require_crds() {
    local label="" crds=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) crds+=("$1"); shift ;;
        esac
    done
    label="${label:-CRDs ${crds[*]} exist}"

    local ok=true
    for crd in "${crds[@]}"; do
        if ! kubectl get crd "$crd" &>/dev/null; then
            ok=false
            break
        fi
    done

    if $ok; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_file_exists FILE_PATH [--label LABEL]
require_file_exists() {
    local file_path="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) file_path="$1"; shift ;;
        esac
    done
    label="${label:-File $file_path exists}"

    if [ -f "$file_path" ]; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}

# require_http_reachable --url URL [--timeout SECONDS] [--label LABEL]
require_http_reachable() {
    local url="" timeout=10 label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url) url="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    label="${label:-$url reachable}"

    if curl -sf --max-time "$timeout" "$url" &>/dev/null; then
        check_ok "$label"
    else
        check_ko "$label"
        return 1
    fi
}
