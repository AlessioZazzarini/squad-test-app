#!/bin/bash
# Usage: notify.sh "Your message here"
# Sends a notification via the configured channel (telegram, slack, webhook).
# Reads channel from .claude/agentsquad.json → notifications.channel
# Falls back to stdout if no channel is configured or env vars are missing.
#
# Env vars (per channel):
#   telegram — TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   slack    — SLACK_WEBHOOK_URL
#   webhook  — AGENTSQUAD_NOTIFY_WEBHOOK

set -euo pipefail

MESSAGE="${1:?Usage: notify.sh \"message\"}"

# --- Resolve channel from config ---
CHANNEL="none"
CONFIG_FILE=".claude/agentsquad.json"

if [ -f "$CONFIG_FILE" ]; then
  # Extract notifications.channel — lightweight jq-free parsing
  PARSED=$(grep -o '"channel"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*"channel"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
  if [ -n "$PARSED" ]; then
    CHANNEL="$PARSED"
  fi
fi

# --- Locate notification scripts (installed pack or pack source) ---
find_script() {
  local name="$1"
  # Installed location (pack install copies to scripts/agentsquad/)
  if [ -f "scripts/agentsquad/${name}" ]; then
    echo "scripts/agentsquad/${name}"
    return
  fi
  # Pack source location
  if [ -f "packs/notifications/scripts/${name}" ]; then
    echo "packs/notifications/scripts/${name}"
    return
  fi
  echo ""
}

# --- Dispatch based on channel ---
case "$CHANNEL" in
  telegram)
    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
      echo "[agentsquad] TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set, falling back to stdout" >&2
      echo "[agentsquad] ${MESSAGE}"
      exit 0
    fi
    SCRIPT=$(find_script "notify-telegram.sh")
    if [ -n "$SCRIPT" ]; then
      bash "$SCRIPT" "$MESSAGE"
    else
      echo "[agentsquad] notify-telegram.sh not found, falling back to stdout" >&2
      echo "[agentsquad] ${MESSAGE}"
    fi
    ;;
  slack)
    if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
      echo "[agentsquad] SLACK_WEBHOOK_URL not set, falling back to stdout" >&2
      echo "[agentsquad] ${MESSAGE}"
      exit 0
    fi
    SCRIPT=$(find_script "notify-slack.sh")
    if [ -n "$SCRIPT" ]; then
      bash "$SCRIPT" "$MESSAGE"
    else
      echo "[agentsquad] notify-slack.sh not found, falling back to stdout" >&2
      echo "[agentsquad] ${MESSAGE}"
    fi
    ;;
  webhook)
    if [ -z "${AGENTSQUAD_NOTIFY_WEBHOOK:-}" ]; then
      echo "[agentsquad] AGENTSQUAD_NOTIFY_WEBHOOK not set, falling back to stdout" >&2
      echo "[agentsquad] ${MESSAGE}"
      exit 0
    fi
    # Generic webhook — works with Slack, Discord, and most services
    curl -s -X POST "${AGENTSQUAD_NOTIFY_WEBHOOK}" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"${MESSAGE}\", \"content\": \"${MESSAGE}\"}" \
      > /dev/null 2>&1 || echo "WARNING: webhook notification failed" >&2
    echo "[agentsquad] ${MESSAGE}"
    ;;
  none|"")
    echo "[agentsquad] ${MESSAGE}"
    ;;
  *)
    echo "[agentsquad] Unknown channel '${CHANNEL}', falling back to stdout" >&2
    echo "[agentsquad] ${MESSAGE}"
    ;;
esac
