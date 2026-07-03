#!/bin/bash
set -e

# Usage: ./request-help.sh [MODULE_NAME]

MODULE=$1

if [ -z "$MODULE" ]; then
    echo "Usage: $0 <MODULE_NAME>"
    echo "Example: $0 module-02-first-capi-cluster"
    exit 1
fi

# Validate module name BEFORE it is used in a filesystem path or sent to the
# dashboard. Matches the server-side MODULE_NAME_RE; blocks path traversal
# (e.g. ../../etc/passwd) into the validation_output read below.
if ! printf '%s' "$MODULE" | grep -qE '^module-[0-9]{2}-[a-z-]+$'; then
    echo "Error: Invalid module name '$MODULE' (expected e.g. module-02-first-capi-cluster)."
    exit 1
fi

if [ -z "$DASHBOARD_URL" ]; then
    echo "Error: DASHBOARD_URL not set."
    exit 1
fi

if [ -z "$DASHBOARD_API_TOKEN" ]; then
    echo "Error: DASHBOARD_API_TOKEN not set."
    echo "Please ensure DASHBOARD_API_TOKEN is exported in your environment."
    exit 1
fi

# Prepare URL
# Extract Base URL (e.g., http://1.2.3.4:8000) by removing everything after the port or /api/
# This covers http://ip:8000/api/report, http://ip:8000/, http://ip:8000
BASE_URL=$(echo "$DASHBOARD_URL" | sed 's|/api/report.*||' | sed 's|/$||')

# Force the correct endpoint
REQ_URL="${BASE_URL}/api/request_solution"
# Student identity must match the one the agent reports under (and the one the
# per-student token authorizes). Honor the STUDENT_ID override the agent uses;
# fall back to the hostname only when it is not set. Without this, a VM whose
# hostname differs from its STUDENT_ID (e.g. hostname "student", STUDENT_ID
# "ws1") would file under the wrong id and the per-student token would be
# rejected (403).
STUDENT_ID="${STUDENT_ID:-$(hostname -f)}"
IP=$(hostname -I | awk '{print $1}')

# Attach the validation output the agent captured for THIS module, so the
# instructor sees the exact error you are facing (not just "help needed").
# The agent writes it under $WORKSHOP_ROOT/.capi-agent/validation_output; both
# WORKSHOP_ROOT and this script are configured by setup.sh. Anchoring on
# WORKSHOP_ROOT (rather than this script's own directory) means it works no
# matter where request-help.sh was copied (e.g. ~/request-help.sh). Override
# the location with VALIDATION_OUTPUT_DIR if your setup differs.
VALIDATION_DIR="${VALIDATION_OUTPUT_DIR:-}"
if [ -z "$VALIDATION_DIR" ] && [ -n "${WORKSHOP_ROOT:-}" ]; then
    VALIDATION_DIR="${WORKSHOP_ROOT}/.capi-agent/validation_output"
fi
if [ -n "$VALIDATION_DIR" ] && [ -f "${VALIDATION_DIR}/${MODULE}.txt" ]; then
    ERROR_CONTEXT_RAW=$(cat "${VALIDATION_DIR}/${MODULE}.txt")
else
    ERROR_CONTEXT_RAW=""
    echo "ℹ️  No cached validation output for $MODULE yet (has the agent graded it?)."
    echo "   Sending the request without error details."
fi

echo "📡 Contacting Instructor at $REQ_URL..."

# Build the JSON body with jq so quotes/newlines/control chars in any field
# are escaped — never interpolate untrusted values into a JSON string by hand.
PAYLOAD=$(jq -n \
     --arg student_id "$STUDENT_ID" \
     --arg module "$MODULE" \
     --arg ip_address "$IP" \
     --arg error_context "$ERROR_CONTEXT_RAW" \
     '{student_id: $student_id, module: $module, ip_address: $ip_address, error_context: $error_context}')

# Send request with Bearer token auth
RESPONSE=$(curl -s -L -X POST "$REQ_URL" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $DASHBOARD_API_TOKEN" \
     -d "$PAYLOAD")

STATUS=$(echo $RESPONSE | jq -r '.status')

if [ "$STATUS" == "queued_for_hints" ]; then
    echo "✅ Request sent! Instructor notified for HINTS."
elif [ "$STATUS" == "escalated_to_solution" ]; then
    echo "🚨 Hints didn't help? Escalating to SOLUTION request."
    echo "   Instructor notified."
elif [ "$STATUS" == "wait" ]; then
    WAIT=$(echo $RESPONSE | jq -r '.wait_seconds')
    echo "⏳ Hold on! You just got the hints."
    echo "   You must try for another $WAIT seconds before requesting the full solution."
elif [ "$STATUS" == "granted" ]; then
    echo "ℹ️  Check your README.md, help has arrived."
else
    echo "Response: $RESPONSE"
fi
