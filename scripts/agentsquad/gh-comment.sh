#!/bin/bash
# gh-comment.sh — Post a comment to a GitHub issue (graceful failure)
#
# Usage: gh-comment.sh <issue_number> "message"
#
# Fails silently — if gh is unavailable or the API call fails,
# logs to stderr and exits 0. Never blocks the worker.

set -euo pipefail

ISSUE="${1:-}"
MSG="${2:-}"

# Skip if no issue linked
if [ -z "$ISSUE" ] || [ "$ISSUE" = "none" ] || [ "$ISSUE" = "null" ]; then
  exit 0
fi

# Skip if no message
if [ -z "$MSG" ]; then
  echo "[gh-comment] No message provided" >&2
  exit 0
fi

# Skip if gh not available
if ! command -v gh &>/dev/null; then
  echo "[gh-comment] gh CLI not found — skipping" >&2
  exit 0
fi

# Post comment (fail silently)
if ! gh issue comment "$ISSUE" --body "$MSG" 2>/dev/null; then
  echo "[gh-comment] Failed to post to #$ISSUE — continuing" >&2
fi
