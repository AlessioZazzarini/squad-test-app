#!/bin/bash
# Usage: check-workers.sh
# Outputs JSON array of active worker windows in the tmux session.
# Each entry includes age_seconds from the task's status.json updated_at field.

set -euo pipefail

SESSION="${AGENTSQUAD_TMUX_SESSION:-$(basename "$(pwd)")}"

# Resolve project root and tasks dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-.tasks}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "WARNING: tmux session '${SESSION}' not found — returning empty worker list" >&2
  echo "[]"
  exit 0
fi

# Cross-platform epoch conversion (macOS + Linux)
parse_epoch() {
  local ts="$1"
  local clean="${ts%%Z}"
  clean="${clean%%.*}"
  if date -u -d "$ts" +%s 2>/dev/null; then
    return
  elif date -u -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null; then
    return
  else
    echo "0"
  fi
}

NOW=$(date +%s)

echo "["
FIRST=true
for WINDOW in $(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null); do
  if [[ "$WINDOW" == task-* ]]; then
    TASK_ID="${WINDOW#task-}"
    DEAD=$(tmux list-panes -t "${SESSION}:${WINDOW}" -F '#{pane_dead}' 2>/dev/null | head -1)

    # Compute age from status.json updated_at
    AGE_SECONDS=0
    STATUS_FILE="$PROJECT_ROOT/$TASKS_DIR/$TASK_ID/status.json"
    if [ -f "$STATUS_FILE" ]; then
      UPDATED_AT=$(jq -r '.updated_at // empty' "$STATUS_FILE" 2>/dev/null || true)
      if [ -n "$UPDATED_AT" ]; then
        UPDATED_EPOCH=$(parse_epoch "$UPDATED_AT")
        if [ "$UPDATED_EPOCH" -gt 0 ] 2>/dev/null; then
          AGE_SECONDS=$((NOW - UPDATED_EPOCH))
        fi
      fi
    fi

    if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
    echo "  {\"window\": \"${WINDOW}\", \"task_id\": \"${TASK_ID}\", \"alive\": $([ \"$DEAD\" = \"0\" ] && echo true || echo false), \"age_seconds\": ${AGE_SECONDS}}"
  fi
done
echo "]"
