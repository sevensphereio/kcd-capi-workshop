#!/bin/bash
# verify-all.sh — run every module's validate.sh and aggregate the result.
# Modules are validated in parallel (4-way) for speed; output is interleaved
# in deterministic module order for human readability.

set -u

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Discovery ---
MODULE_DIRS=()
for dir in module-*/validate.sh; do
    [ -f "$dir" ] || continue
    d="$(dirname "$dir")"
    [ -f "$d/.disabled" ] && continue      # module shipped disabled — skip
    MODULE_DIRS+=("$d")
done

if [ ${#MODULE_DIRS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No module-*/validate.sh found.${NC}"
    exit 0
fi

# --- Auto-configure context ---
clear
echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}🚀 Workshop validation (parallel, 4-way)${NC}"
echo -e "${BLUE}==============================================${NC}"

MGMT_KUBECONFIG="$(pwd)/module-01-introduction/capi-mgmt.kubeconfig"
if [ -f "$MGMT_KUBECONFIG" ]; then
    echo "Found Management Cluster config: $MGMT_KUBECONFIG"
    export KUBECONFIG="$MGMT_KUBECONFIG"
else
    echo -e "${YELLOW}⚠️  Management Cluster config not found at $MGMT_KUBECONFIG.${NC}"
    echo "Using default kubectl context."
fi

# --- Parallel execution ---
RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "$RESULTS_DIR"' EXIT

# Each parallel worker runs ./validate.sh in a subshell (subshell scoping
# avoids the SC2103 / SC2164 cd-back pattern), captures stdout+stderr to a
# per-module log, and writes the exit code to a sidecar .rc file.
run_one() {
    local mod_dir=$1
    local mod_name
    mod_name=$(basename "$mod_dir")
    local out="$RESULTS_DIR/$mod_name.log"
    local rc="$RESULTS_DIR/$mod_name.rc"
    ( cd "$mod_dir" && ./validate.sh ) > "$out" 2>&1
    echo $? > "$rc"
}
export -f run_one
export RESULTS_DIR

printf '%s\n' "${MODULE_DIRS[@]}" \
    | xargs -I{} -P 4 bash -c 'run_one "$@"' _ {}

# --- Aggregate in canonical order ---
overall_status=0
for mod_dir in "${MODULE_DIRS[@]}"; do
    mod_name=$(basename "$mod_dir")
    out="$RESULTS_DIR/$mod_name.log"
    rc=$(cat "$RESULTS_DIR/$mod_name.rc")

    echo -e "\n${BLUE}=== ${mod_name} ===${NC}"
    cat "$out"

    case "$rc" in
        0)   echo -e "${GREEN}✅ ${mod_name} PASSED${NC}" ;;
        100) echo -e "${YELLOW}⏳ ${mod_name} PENDING (Not started yet)${NC}";   overall_status=1 ;;
        101) echo -e "${YELLOW}🔄 ${mod_name} IN_PROGRESS (Still working)${NC}"; overall_status=1 ;;
        *)   echo -e "${RED}❌ ${mod_name} FAILED (Exit Code: ${rc})${NC}";      overall_status=1 ;;
    esac
done

echo -e "\n${BLUE}==============================================${NC}"
if [ "$overall_status" -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL WORKSHOP MODULES PASSED!${NC}"
else
    echo -e "${RED}❌ Some modules did not pass. Check output above.${NC}"
fi
echo -e "${BLUE}==============================================${NC}"

exit "$overall_status"
