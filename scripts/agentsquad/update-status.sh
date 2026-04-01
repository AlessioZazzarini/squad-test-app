#!/bin/bash
# Usage: update-status.sh <task_id> <field> <value>
# Example: update-status.sh migrate-auth status "testing-local"
# Example: update-status.sh migrate-auth attempts 2
#
# Safe jq-based JSON updates with path traversal validation.
# Optionally notifies via AGENTSQUAD_NOTIFY_WEBHOOK on key status transitions.

set -euo pipefail

# Resolve project root — prefer AGENTSQUAD_PROJECT_ROOT (set by conductor
# when running in a worktree) over script-relative resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${AGENTSQUAD_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-.tasks}"

TASK_ID="$1"
FIELD="$2"
VALUE="$3"

# Validate task_id — reject path traversal and non-slug characters
if [[ "$TASK_ID" == *".."* ]] || [[ "$TASK_ID" == *"/"* ]] || [[ ! "$TASK_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: invalid task_id '${TASK_ID}' — must be a slug (alphanumeric, hyphens, underscores)" >&2
  exit 1
fi

STATUS_FILE="$PROJECT_ROOT/${TASKS_DIR}/${TASK_ID}/status.json"

if [ ! -f "$STATUS_FILE" ]; then
  echo "ERROR: ${STATUS_FILE} not found" >&2
  exit 1
fi

# Determine if value is numeric, boolean, or string
if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
  jq --arg f "$FIELD" --argjson v "$VALUE" '.[$f] = $v | .updated_at = (now | todate)' \
    "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
elif [[ "$VALUE" == "true" || "$VALUE" == "false" ]]; then
  jq --arg f "$FIELD" --argjson v "$VALUE" '.[$f] = $v | .updated_at = (now | todate)' \
    "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
else
  jq --arg f "$FIELD" --arg v "$VALUE" '.[$f] = $v | .updated_at = (now | todate)' \
    "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
fi

echo "Updated ${TASK_ID}: ${FIELD} = ${VALUE}"

# --- Auto-notify on key status transitions ---
if [ "$FIELD" = "status" ]; then
  NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
  case "$VALUE" in
    investigating)
      "$NOTIFY_SCRIPT" "Investigating *${TASK_ID}*" 2>/dev/null || true
      ;;
    implementing)
      "$NOTIFY_SCRIPT" "Implementing fix for *${TASK_ID}*" 2>/dev/null || true
      ;;
    pr-created)
      PR_URL=$(jq -r '.pr_url // empty' "$STATUS_FILE")
      "$NOTIFY_SCRIPT" "PR created for *${TASK_ID}*: ${PR_URL:-pending}" 2>/dev/null || true
      ;;
    testing-local)
      "$NOTIFY_SCRIPT" "Testing *${TASK_ID}* locally" 2>/dev/null || true
      ;;
    testing-preview)
      PREVIEW=$(jq -r '.preview_url // empty' "$STATUS_FILE")
      "$NOTIFY_SCRIPT" "Testing *${TASK_ID}* on preview: ${PREVIEW:-pending}" 2>/dev/null || true
      ;;
    ready-for-review)
      PR_URL=$(jq -r '.pr_url // empty' "$STATUS_FILE")
      "$NOTIFY_SCRIPT" "*${TASK_ID}* ready for review: ${PR_URL:-check GitHub}" 2>/dev/null || true
      ;;
    blocked)
      REASON=$(jq -r '.blocked_reason // "unknown"' "$STATUS_FILE")
      "$NOTIFY_SCRIPT" "*${TASK_ID}* blocked: ${REASON}" 2>/dev/null || true
      ;;
  esac
fi
