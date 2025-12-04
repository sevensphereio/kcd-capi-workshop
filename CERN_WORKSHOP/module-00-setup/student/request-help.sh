#!/bin/bash
set -e

# Usage: ./request-help.sh [MODULE_NAME]

MODULE=$1

if [ -z "$MODULE" ]; then
    echo "Usage: $0 <MODULE_NAME>"
    echo "Example: $0 module-02-first-capi-cluster"
    exit 1
fi

if [ -z "$DASHBOARD_URL" ]; then
    echo "Error: DASHBOARD_URL not set."
    exit 1
fi

# Prepare URL
# Extract Base URL (e.g., http://1.2.3.4:8000) by removing everything after the port or /api/
# This covers http://ip:8000/api/report, http://ip:8000/, http://ip:8000
BASE_URL=$(echo "$DASHBOARD_URL" | sed 's|/api/report.*||' | sed 's|/$||')

# Force the correct endpoint
REQ_URL="${BASE_URL}/api/request_solution"
HOSTNAME=$(hostname -f)
IP=$(hostname -I | awk '{print $1}')

echo "📡 Contacting Instructor at $REQ_URL..."

# Send request
# Added Basic Auth just in case, and -L for redirects.
RESPONSE=$(curl -s -L -u admin:kordent2024 -X POST "$REQ_URL" \
     -H "Content-Type: application/json" \
     -d "{\"student_id\": \"$HOSTNAME\", \"module\": \"$MODULE\", \"ip_address\": \"$IP\"}")

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