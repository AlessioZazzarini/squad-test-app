#!/bin/bash
# gh-create-followup.sh — Create a follow-up issue with duplicate check
#
# Usage: gh-create-followup.sh <parent_issue> "title" "body"
#
# Creates the issue with label squad:triage (NOT squad:ready).
# Discovered issues need human triage before becoming executable.
# Comments on the parent issue with a link to the new issue.
# Checks for duplicate titles before creating.

set -euo pipefail

PARENT="${1:-}"
TITLE="${2:-}"
BODY="${3:-}"

if [ -z "$TITLE" ]; then
  echo "Usage: gh-create-followup.sh <parent_issue> 'title' 'body'" >&2
  exit 1
fi

# Skip if gh not available
if ! command -v gh &>/dev/null; then
  echo "[gh-followup] gh CLI not found — skipping" >&2
  exit 0
fi

# Duplicate check — search for similar open issues
SEARCH_TERM=$(echo "$TITLE" | head -c 60)  # Truncate for search
EXISTING=$(gh issue list --search "$SEARCH_TERM" --state open --json number --jq 'length' 2>/dev/null || echo 0)

if [ "$EXISTING" -gt 0 ]; then
  echo "[gh-followup] Similar issue already exists for: $TITLE — skipping" >&2
  exit 0
fi

# Build the issue body with parent context
FULL_BODY="Discovered while implementing #${PARENT:-unknown}.

${BODY}

---
*Auto-created by AgentSquad worker*"

# Create the issue with squad:triage label
NEW_URL=$(gh issue create \
  --title "$TITLE" \
  --body "$FULL_BODY" \
  --label "squad:triage" 2>&1) || {
  echo "[gh-followup] Failed to create issue: $TITLE" >&2
  exit 0
}

echo "Created follow-up: $NEW_URL"

# Comment on parent issue with link (if parent exists)
if [ -n "$PARENT" ] && [ "$PARENT" != "none" ] && [ "$PARENT" != "null" ]; then
  gh issue comment "$PARENT" --body "Filed follow-up: $NEW_URL" 2>/dev/null || true
fi
