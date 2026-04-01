#!/bin/bash
# Usage: check-workers.sh
# Outputs JSON array of active worker windows in the tmux session.

set -euo pipefail

SESSION="${AGENTSQUAD_TMUX_SESSION:-$(basename "$(pwd)")}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "WARNING: tmux session '${SESSION}' not found — returning empty worker list" >&2
  echo "[]"
  exit 0
fi

echo "["
FIRST=true
for WINDOW in $(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null); do
  if [[ "$WINDOW" == task-* ]]; then
    TASK_ID="${WINDOW#task-}"
    DEAD=$(tmux list-panes -t "${SESSION}:${WINDOW}" -F '#{pane_dead}' 2>/dev/null | head -1)
    if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
    echo "  {\"window\": \"${WINDOW}\", \"task_id\": \"${TASK_ID}\", \"alive\": $([ \"$DEAD\" = \"0\" ] && echo true || echo false)}"
  fi
done
echo "]"
