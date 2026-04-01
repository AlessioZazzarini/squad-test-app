#!/bin/bash
# notify-telegram.sh — Send notification via Telegram Bot API
# Usage: notify-telegram.sh "Your message here"
# Env: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
# Falls back to stdout if env vars not set.

set -euo pipefail

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: notify-telegram.sh 'message'" >&2
  exit 1
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT="${TELEGRAM_CHAT_ID:-}"

if [ -z "$TOKEN" ] || [ -z "$CHAT" ]; then
  echo "[telegram] $MESSAGE"
  exit 0
fi

# Telegram Bot API — sendMessage with Markdown
curl -sf -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d chat_id="$CHAT" \
  -d parse_mode="Markdown" \
  -d text="$MESSAGE" >/dev/null 2>&1 || {
  echo "[telegram] Failed to send, falling back to stdout: $MESSAGE" >&2
}
