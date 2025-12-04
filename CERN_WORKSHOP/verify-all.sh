#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration ---
MODULE_DIRS=(
    "module-01-introduction"
    "module-02-first-capi-cluster"
    "module-03-templating"
    "module-04-caaph"
    "module-05-ai"
    "module-06-capstone"
    "module-07-observability"
    "module-08-sveltos"
    "module-09-kordent"
    "module-10-kosmotron"
)

# --- Helper Functions ---

run_validation() {
    local module_path=$1
    local module_name=$(basename "$module_path")
    local validate_script="$module_path/validate.sh"
    
    echo -e "\n${BLUE}=== Running validation for ${module_name} ===${NC}"
    
    if [ -f "$validate_script" ]; then
        # Run the script and capture output/exit code
        cd "$module_path" > /dev/null
        ./validate.sh
        local exit_code=$?
        cd - > /dev/null # Go back to original directory
        
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✅ ${module_name} PASSED${NC}"
            return 0
        elif [ $exit_code -eq 100 ]; then
            echo -e "${YELLOW}⏳ ${module_name} PENDING (Not started yet)${NC}"
            return 1 # Consider as non-passing for overall script
        elif [ $exit_code -eq 101 ]; then
            echo -e "${YELLOW}🔄 ${module_name} IN_PROGRESS (Still working)${NC}"
            return 1 # Consider as non-passing for overall script
        else
            echo -e "${RED}❌ ${module_name} FAILED (Exit Code: ${exit_code})${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  No validate.sh script found for ${module_name}. Skipping.${NC}"
        return 1
    fi
}

# --- Main Execution ---

clear
echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}🚀 Starting Full Workshop Validation${NC}"
echo -e "${BLUE}==============================================${NC}"

# Auto-configure Context
MGMT_KUBECONFIG="$(pwd)/module-01-introduction/capi-mgmt.kubeconfig"
if [ -f "$MGMT_KUBECONFIG" ]; then
    echo "Found Management Cluster config: $MGMT_KUBECONFIG"
    export KUBECONFIG=$MGMT_KUBECONFIG
else
    echo -e "${YELLOW}⚠️  Management Cluster config not found at $MGMT_KUBECONFIG.${NC}"
    echo "Using default kubectl context."
fi

overall_status=0 # 0 for success, 1 for failure

for dir in "${MODULE_DIRS[@]}"; do
    run_validation "$dir"
    if [ $? -ne 0 ]; then
        overall_status=1
    fi
done

echo -e "\n${BLUE}==============================================${NC}"
if [ $overall_status -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL WORKSHOP MODULES PASSED!${NC}"
else
    echo -e "${RED}❌ Some modules did not pass. Check output above.${NC}"
fi
echo -e "${BLUE}==============================================${NC}"

exit $overall_status
