#!/bin/bash
# Usage: notify.sh "Your message here"
# Sends a notification via webhook (Slack, Discord, or generic) if configured.
# Falls back to stdout if no webhook is set.
#
# Env vars:
#   AGENTSQUAD_NOTIFY_WEBHOOK — URL to POST the message to (optional)

set -euo pipefail

MESSAGE="${1:?Usage: notify.sh \"message\"}"

if [ -z "${AGENTSQUAD_NOTIFY_WEBHOOK:-}" ]; then
  echo "[agentsquad] ${MESSAGE}"
  exit 0
fi

# Send via webhook — works with Slack, Discord, and most generic webhooks
curl -s -X POST "${AGENTSQUAD_NOTIFY_WEBHOOK}" \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"${MESSAGE}\", \"content\": \"${MESSAGE}\"}" \
  > /dev/null 2>&1 || echo "WARNING: webhook notification failed" >&2

echo "[agentsquad] ${MESSAGE}"
