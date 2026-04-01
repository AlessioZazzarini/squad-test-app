#!/bin/bash
# notify-slack.sh — Send notification via Slack Incoming Webhook
# Usage: notify-slack.sh "Your message here"
# Env: SLACK_WEBHOOK_URL
# Falls back to stdout if env var not set.

set -euo pipefail

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: notify-slack.sh 'message'" >&2
  exit 1
fi

WEBHOOK="${SLACK_WEBHOOK_URL:-}"

if [ -z "$WEBHOOK" ]; then
  echo "[slack] $MESSAGE"
  exit 0
fi

curl -sf -X POST "$WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"$MESSAGE\"}" >/dev/null 2>&1 || {
  echo "[slack] Failed to send, falling back to stdout: $MESSAGE" >&2
}
