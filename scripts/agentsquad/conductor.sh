#!/bin/bash
# conductor.sh — Orchestration cycle operations for AgentSquad
#
# Subcommands:
#   status        — JSON summary of all tasks + workers
#   finalize-all  — Push/PR for all ready-for-review tasks
#   finalize <id> — Push/PR for a specific task
#   health        — Check worker health, report warnings/stuck
#   spawn-next    — Find and spawn the next ready task

set -euo pipefail

# Source config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$SCRIPT_DIR/lib/config.sh" ]; then
  source "$SCRIPT_DIR/lib/config.sh"
fi

TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-.tasks}"
MAX_WORKERS="${AGENTSQUAD_MAX_WORKERS:-3}"
MAIN_BRANCH="${AGENTSQUAD_MAIN_BRANCH:-main}"
SESSION="${AGENTSQUAD_TMUX_SESSION:-$(basename "$PROJECT_ROOT")}"

# --- Helpers ---

# Cross-platform epoch conversion (macOS + Linux)
# Usage: parse_epoch "2026-04-01T12:00:00Z"
parse_epoch() {
  local ts="$1"
  # Strip trailing Z and fractional seconds for macOS compatibility
  local clean="${ts%%Z}"
  clean="${clean%%.*}"

  # Try GNU date first (Linux), then BSD date (macOS)
  if date -d "$ts" +%s 2>/dev/null; then
    return
  elif date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null; then
    return
  else
    echo "0"
  fi
}

# --- Subcommands ---

cmd_status() {
  local active=0 completed=0 queued=0 blocked=0
  local active_tasks="" completed_tasks="" queued_tasks="" blocked_tasks=""

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local task_id
    task_id=$(basename "$(dirname "$status_file")")

    # Skip internal dirs
    [[ "$task_id" == _* ]] && continue

    local status
    status=$(jq -r '.status // "unknown"' "$status_file")
    local pr_url
    pr_url=$(jq -r '.pr_url // empty' "$status_file")

    case "$status" in
      in_progress|implementing|testing-local|investigating)
        active=$((active + 1))
        active_tasks="${active_tasks:+$active_tasks, }$task_id"
        ;;
      ready-for-review|pr-created)
        completed=$((completed + 1))
        local pr_info=""
        [ -n "$pr_url" ] && pr_info=" ($pr_url)"
        completed_tasks="${completed_tasks:+$completed_tasks, }${task_id}${pr_info}"
        ;;
      ready)
        queued=$((queued + 1))
        queued_tasks="${queued_tasks:+$queued_tasks, }$task_id"
        ;;
      blocked)
        blocked=$((blocked + 1))
        blocked_tasks="${blocked_tasks:+$blocked_tasks, }$task_id"
        ;;
    esac
  done

  cat <<EOF
{
  "active": $active,
  "completed": $completed,
  "queued": $queued,
  "blocked": $blocked,
  "active_tasks": "${active_tasks:-none}",
  "completed_tasks": "${completed_tasks:-none}",
  "queued_tasks": "${queued_tasks:-none}",
  "blocked_tasks": "${blocked_tasks:-none}"
}
EOF
}

cmd_finalize() {
  local task_id="$1"
  local task_dir="$PROJECT_ROOT/$TASKS_DIR/$task_id"
  local status_file="$task_dir/status.json"

  if [ ! -f "$status_file" ]; then
    echo "ERROR: $status_file not found" >&2
    return 1
  fi

  local branch
  branch=$(jq -r '.branch // empty' "$status_file")
  if [ -z "$branch" ]; then
    echo "ERROR: No branch set for $task_id" >&2
    return 1
  fi

  echo "Finalizing $task_id (branch: $branch)..."

  # Push branch
  (cd "$PROJECT_ROOT" && git push -u origin "$branch" 2>&1) || {
    echo "WARNING: git push failed for $branch" >&2
  }

  # Create PR (idempotent — check if one already exists)
  local pr_url
  pr_url=$(cd "$PROJECT_ROOT" && gh pr view "$branch" --json url --jq '.url' 2>/dev/null || true)

  if [ -z "$pr_url" ]; then
    local title
    title=$(jq -r '.title // "Task: '"$task_id"'"' "$status_file")
    local issue
    issue=$(jq -r '.github_issue // empty' "$status_file")

    local body="Automated implementation by AgentSquad worker."
    [ -n "$issue" ] && body="Closes #${issue}\n\n${body}"

    pr_url=$(cd "$PROJECT_ROOT" && gh pr create \
      --head "$branch" \
      --base "$MAIN_BRANCH" \
      --title "$title" \
      --body "$(echo -e "$body")" 2>&1) || {
      echo "WARNING: PR creation failed: $pr_url" >&2
      pr_url=""
    }
  fi

  # Update status
  bash "$SCRIPT_DIR/update-status.sh" "$task_id" status "pr-created"
  if [ -n "$pr_url" ]; then
    bash "$SCRIPT_DIR/update-status.sh" "$task_id" pr_url "$pr_url"
  fi

  # Update GitHub labels
  local issue
  issue=$(jq -r '.github_issue // empty' "$status_file")
  if [ -n "$issue" ]; then
    (cd "$PROJECT_ROOT" && gh issue edit "$issue" \
      --remove-label "squad:in-progress" --add-label "squad:complete" 2>/dev/null) || true
  fi

  # Clean up worktree if it exists
  (cd "$PROJECT_ROOT" && git worktree remove "$TASKS_DIR/worktrees/$task_id" --force 2>/dev/null) || true

  # Notify
  bash "$SCRIPT_DIR/notify.sh" "PR created for $task_id: ${pr_url:-unknown}" 2>/dev/null || true

  echo "Finalized $task_id${pr_url:+ -> $pr_url}"
}

cmd_finalize_all() {
  local found=0

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$status_file")
    [ "$status" = "ready-for-review" ] || continue

    local task_id
    task_id=$(basename "$(dirname "$status_file")")
    cmd_finalize "$task_id"
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    echo "No tasks with status 'ready-for-review' to finalize."
  else
    echo "Finalized $found task(s)."
  fi
}

cmd_health() {
  local now
  now=$(date +%s)
  local found=0

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$status_file")

    # Only check active statuses
    case "$status" in
      in_progress|implementing|testing-local|investigating) ;;
      *) continue ;;
    esac

    local task_id
    task_id=$(basename "$(dirname "$status_file")")
    local updated_at
    updated_at=$(jq -r '.updated_at // empty' "$status_file")

    local age=0
    if [ -n "$updated_at" ]; then
      local updated_epoch
      updated_epoch=$(parse_epoch "$updated_at")
      if [ "$updated_epoch" -gt 0 ] 2>/dev/null; then
        age=$((now - updated_epoch))
      fi
    fi

    local age_min=$((age / 60))

    if [ "$age" -gt 2700 ]; then  # 45 min
      echo "STUCK: $task_id (${age_min}m since update, status=$status)"
    elif [ "$age" -gt 1200 ]; then  # 20 min
      echo "WARNING: $task_id (${age_min}m since update, status=$status)"
    else
      echo "OK: $task_id (${age_min}m since update, status=$status)"
    fi
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    echo "No active workers."
  fi
}

cmd_spawn_next() {
  # Count active workers
  local active
  active=$(bash "$SCRIPT_DIR/check-workers.sh" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)

  if [ "$active" -ge "$MAX_WORKERS" ]; then
    echo "At capacity ($active/$MAX_WORKERS workers active)"
    return 0
  fi

  # Find next ready task (with dependency check)
  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$status_file")
    [ "$status" = "ready" ] || continue

    local task_id
    task_id=$(basename "$(dirname "$status_file")")

    # Check dependencies are met
    local deps_met=true
    local deps
    deps=$(jq -r '.dependencies // [] | .[]' "$status_file" 2>/dev/null || true)
    for dep in $deps; do
      [ -z "$dep" ] && continue
      local dep_file="$PROJECT_ROOT/$TASKS_DIR/$dep/status.json"
      if [ -f "$dep_file" ]; then
        local dep_status
        dep_status=$(jq -r '.status // "unknown"' "$dep_file")
        if [ "$dep_status" != "pr-created" ] && [ "$dep_status" != "complete" ] && [ "$dep_status" != "ready-for-review" ]; then
          deps_met=false
          break
        fi
      fi
    done

    if [ "$deps_met" = false ]; then
      continue
    fi

    echo "Spawning: $task_id"
    bash "$SCRIPT_DIR/spawn-worker.sh" "$task_id"
    return 0
  done

  echo "No ready tasks"
}

# --- Main dispatch ---

case "${1:-}" in
  status)
    cmd_status
    ;;
  finalize-all)
    cmd_finalize_all
    ;;
  finalize)
    if [ -z "${2:-}" ]; then
      echo "Usage: conductor.sh finalize <task-id>" >&2
      exit 1
    fi
    cmd_finalize "$2"
    ;;
  health)
    cmd_health
    ;;
  spawn-next)
    cmd_spawn_next
    ;;
  *)
    echo "Usage: conductor.sh <status|finalize-all|finalize <id>|health|spawn-next>" >&2
    exit 1
    ;;
esac
