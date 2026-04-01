#!/bin/bash
# conductor.sh — The single orchestration engine for AgentSquad
#
# Usage:
#   conductor.sh                   Single tick (default)
#   conductor.sh --once            Single tick (explicit)
#   conductor.sh --loop 3m         Continuous tick (interval: Nm or Ns)
#   conductor.sh --dry-run         Preview only, no changes
#   conductor.sh status            JSON summary of all tasks + workers
#   conductor.sh finalize <id>     Finalize a specific task (push + PR)
#   conductor.sh health            Health check all workers
#
# The tick function runs these steps in order:
#   1. Finalize completed workers (push + PR)
#   2. Check review artifacts (pr-review.md)
#   3. Apply approval policy (manual/auto/paused)
#   4. Merge approved tasks
#   5. Health check active workers
#   6. Spawn workers until at capacity or no ready tasks
#   7. Send cycle summary notification

set -euo pipefail

# ── Source shared libs ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$SCRIPT_DIR/lib/config.sh" ]; then
  source "$SCRIPT_DIR/lib/config.sh"
fi
if [ -f "$SCRIPT_DIR/lib/worktree.sh" ]; then
  source "$SCRIPT_DIR/lib/worktree.sh"
fi

# ── Configuration ────────────────────────────────────────────
TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-.tasks}"
MAX_WORKERS="${AGENTSQUAD_MAX_WORKERS:-3}"
MAIN_BRANCH="${AGENTSQUAD_MAIN_BRANCH:-main}"
SESSION="${AGENTSQUAD_TMUX_SESSION:-$(basename "$PROJECT_ROOT")}"
CONFIG_FILE="$PROJECT_ROOT/.claude/agentsquad.json"
LOCK_FILE="$PROJECT_ROOT/$TASKS_DIR/.conductor.lock"

# ── Parse arguments ──────────────────────────────────────────
MODE="once"
INTERVAL_SECONDS=""
DRY_RUN=false
SUBCMD=""
SUBCMD_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      MODE="once"; shift ;;
    --loop)
      MODE="loop"
      # Parse interval: Nm for minutes, Ns for seconds, plain number = seconds
      local_interval="${2:-5m}"
      if [[ "$local_interval" =~ ^([0-9]+)m$ ]]; then
        INTERVAL_SECONDS=$(( ${BASH_REMATCH[1]} * 60 ))
      elif [[ "$local_interval" =~ ^([0-9]+)s$ ]]; then
        INTERVAL_SECONDS="${BASH_REMATCH[1]}"
      elif [[ "$local_interval" =~ ^[0-9]+$ ]]; then
        INTERVAL_SECONDS="$local_interval"
      else
        echo "ERROR: Invalid interval '$local_interval'. Use Nm (minutes) or Ns (seconds)." >&2
        exit 1
      fi
      shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    status|health)
      SUBCMD="$1"; shift; break ;;
    finalize)
      SUBCMD="finalize"; SUBCMD_ARG="${2:-}"; shift; shift 2>/dev/null || true; break ;;
    -*)
      echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      shift ;;
  esac
done

# ── Logging ──────────────────────────────────────────────────
log() {
  echo "[$(date '+%H:%M:%S')] $1"
}

# ── Helpers ──────────────────────────────────────────────────

# Cross-platform epoch conversion (macOS + Linux)
parse_epoch() {
  local ts="$1"
  local clean="${ts%%Z}"
  clean="${clean%%.*}"

  if date -d "$ts" +%s 2>/dev/null; then
    return
  elif date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null; then
    return
  else
    echo "0"
  fi
}

# Check if all dependencies are met for a task
check_deps_met() {
  local task_id="$1"
  local status_file="$PROJECT_ROOT/$TASKS_DIR/$task_id/status.json"

  local deps
  deps=$(jq -r '.dependencies // [] | .[]' "$status_file" 2>/dev/null || true)
  for dep in $deps; do
    [ -z "$dep" ] && continue
    local dep_file="$PROJECT_ROOT/$TASKS_DIR/$dep/status.json"
    if [ ! -f "$dep_file" ]; then
      return 1
    fi
    local dep_status
    dep_status=$(jq -r '.status // "unknown"' "$dep_file")
    if [ "$dep_status" = "blocked" ] || [ "$dep_status" = "failed" ]; then
      # Cascade blocking
      echo "blocked"
      return 1
    fi
    if [ "$dep_status" != "pr-created" ] && [ "$dep_status" != "complete" ] && \
       [ "$dep_status" != "review-ready" ] && [ "$dep_status" != "approved" ] && \
       [ "$dep_status" != "merged" ]; then
      return 1
    fi
  done
  return 0
}

# ── Tick locking (cross-platform: mkdir is atomic on all POSIX systems) ──
LOCK_DIR="${LOCK_FILE}.d"

acquire_tick_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Check if the lock holder is still alive (stale lock detection)
    local lock_pid=""
    [ -f "$LOCK_DIR/pid" ] && lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      echo "Another conductor tick is running (PID $lock_pid). Skipping." >&2
      exit 0
    fi
    # Stale lock — previous run crashed. Clean up and retry.
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "Failed to acquire lock" >&2; exit 1; }
  fi
  echo $$ > "$LOCK_DIR/pid"
}

release_tick_lock() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}

# ── Approval helpers ─────────────────────────────────────────

# Read the approval mode: per-task override > global config > "manual"
get_approval_mode() {
  local task_id="$1"
  local status_file="$PROJECT_ROOT/$TASKS_DIR/$task_id/status.json"

  # Per-task override (skip for __global__ or missing files)
  if [ "$task_id" != "__global__" ] && [ -f "$status_file" ]; then
    local task_mode
    task_mode=$(jq -r '.approval_mode // empty' "$status_file" 2>/dev/null)
    if [ -n "$task_mode" ]; then
      echo "$task_mode"
      return
    fi
  fi

  # Global config
  if [ -f "$CONFIG_FILE" ]; then
    local global_mode
    global_mode=$(jq -r '.approval.default // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$global_mode" ]; then
      echo "$global_mode"
      return
    fi
  fi

  echo "manual"
}

# Read sensitive_paths from config, return newline-separated list
get_sensitive_paths() {
  if [ -f "$CONFIG_FILE" ]; then
    jq -r '.approval.auto_merge.sensitive_paths // [] | .[]' "$CONFIG_FILE" 2>/dev/null
  fi
}

# Check if any changed files match sensitive paths
has_sensitive_changes() {
  local branch="$1"
  local sensitive_paths
  sensitive_paths=$(get_sensitive_paths)
  [ -z "$sensitive_paths" ] && return 1

  local changed_files
  changed_files=$(cd "$PROJECT_ROOT" && git diff --name-only "$MAIN_BRANCH...$branch" 2>/dev/null)
  [ -z "$changed_files" ] && return 1

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if echo "$changed_files" | grep -q "$pattern"; then
      return 0
    fi
  done <<< "$sensitive_paths"

  return 1
}

# ── Subcommands (used both standalone and inside tick) ───────

cmd_status() {
  local active=0 completed=0 queued=0 blocked=0 review_ready=0 approved=0 merged=0
  local active_tasks="" completed_tasks="" queued_tasks="" blocked_tasks=""
  local review_ready_tasks="" approved_tasks="" merged_tasks=""

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
      review-ready)
        review_ready=$((review_ready + 1))
        local pr_info=""
        [ -n "$pr_url" ] && pr_info=" ($pr_url)"
        review_ready_tasks="${review_ready_tasks:+$review_ready_tasks, }${task_id}${pr_info}"
        ;;
      approved)
        approved=$((approved + 1))
        approved_tasks="${approved_tasks:+$approved_tasks, }$task_id"
        ;;
      merged)
        merged=$((merged + 1))
        merged_tasks="${merged_tasks:+$merged_tasks, }$task_id"
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
  "review_ready": $review_ready,
  "approved": $approved,
  "merged": $merged,
  "queued": $queued,
  "blocked": $blocked,
  "active_tasks": "${active_tasks:-none}",
  "completed_tasks": "${completed_tasks:-none}",
  "review_ready_tasks": "${review_ready_tasks:-none}",
  "approved_tasks": "${approved_tasks:-none}",
  "merged_tasks": "${merged_tasks:-none}",
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

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Would finalize $task_id (branch: $branch)"
    return 0
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

  # Only set pr-created if we have a valid PR URL
  if echo "$pr_url" | grep -q "github.com"; then
    bash "$SCRIPT_DIR/update-status.sh" "$task_id" status "pr-created"
    bash "$SCRIPT_DIR/update-status.sh" "$task_id" pr_url "$pr_url"
  else
    echo "ERROR: No valid PR URL obtained for $task_id (got: ${pr_url:-empty})" >&2
    return 1
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

    if [ "$DRY_RUN" = true ]; then
      log "[DRY-RUN] Would finalize $task_id"
      found=$((found + 1))
      continue
    fi

    cmd_finalize "$task_id"
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    echo "No tasks with status 'ready-for-review' to finalize."
  else
    echo "Finalized $found task(s)."
    # Clean up worktrees only for tasks that were finalized (status = ready-for-review → pr-created)
    # Each task's worktree is already cleaned in cmd_finalize; only rmdir if empty
    if [ "$DRY_RUN" = false ] && [ -d "$PROJECT_ROOT/$TASKS_DIR/worktrees" ]; then
      rmdir "$PROJECT_ROOT/$TASKS_DIR/worktrees" 2>/dev/null || true
    fi
  fi
}

cmd_check_reviews() {
  local found=0

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$status_file")
    [ "$status" = "pr-created" ] || continue

    local task_id
    task_id=$(basename "$(dirname "$status_file")")
    local review_file="$PROJECT_ROOT/$TASKS_DIR/$task_id/pr-review.md"

    if [ -f "$review_file" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would promote $task_id to review-ready"
        found=$((found + 1))
        continue
      fi

      bash "$SCRIPT_DIR/update-status.sh" "$task_id" status "review-ready"
      bash "$SCRIPT_DIR/notify.sh" "$(printf '\xF0\x9F\x93\x8B') *${task_id}* ready for review — see pr-review.md" 2>/dev/null || true
      echo "Review ready: $task_id"
      found=$((found + 1))
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "No tasks with pr-review.md to promote."
  else
    echo "Promoted $found task(s) to review-ready."
  fi
}

cmd_approve_ready() {
  local found=0

  # Check for global paused mode
  local global_mode
  global_mode=$(get_approval_mode "__global__")
  if [ "$global_mode" = "paused" ]; then
    echo "Approval paused globally — skipping all approvals."
    return 0
  fi

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$status_file")
    [ "$status" = "review-ready" ] || continue

    local task_id
    task_id=$(basename "$(dirname "$status_file")")
    local mode
    mode=$(get_approval_mode "$task_id")

    case "$mode" in
      manual)
        echo "Manual approval required: $task_id"
        ;;
      paused)
        echo "Approval paused: $task_id"
        ;;
      auto)
        local branch
        branch=$(jq -r '.branch // empty' "$status_file")
        local pr_number
        pr_number=$(jq -r '.pr_url // empty' "$status_file" | grep -o '[0-9]*$' || echo "")

        if [ -z "$pr_number" ]; then
          echo "WARNING: No PR number for $task_id — skipping auto-approve" >&2
          continue
        fi

        if [ "$DRY_RUN" = true ]; then
          log "[DRY-RUN] Would auto-approve $task_id (PR #$pr_number)"
          found=$((found + 1))
          continue
        fi

        # Check sensitive paths
        if [ -n "$branch" ] && has_sensitive_changes "$branch"; then
          echo "Sensitive paths changed: $task_id — forcing manual review"
          continue
        fi

        # Check CI status
        local ci_ok=true
        if ! (cd "$PROJECT_ROOT" && gh pr checks "$pr_number" --required 2>&1 | grep -q "pass\|All checks were successful") 2>/dev/null; then
          local checks_output
          checks_output=$(cd "$PROJECT_ROOT" && gh pr checks "$pr_number" --required 2>&1 || true)
          if echo "$checks_output" | grep -qi "fail\|error"; then
            ci_ok=false
          fi
        fi

        if [ "$ci_ok" = true ]; then
          bash "$SCRIPT_DIR/update-status.sh" "$task_id" status "approved"
          bash "$SCRIPT_DIR/notify.sh" "$(printf '\xF0\x9F\xA4\x96') Auto-approved *${task_id}*" 2>/dev/null || true
          echo "Auto-approved: $task_id"
          found=$((found + 1))
        else
          echo "CI failing: $task_id — waiting for green"
        fi
        ;;
      *)
        echo "Unknown approval mode '$mode' for $task_id — skipping"
        ;;
    esac
  done

  if [ "$found" -eq 0 ]; then
    echo "No tasks auto-approved this cycle."
  fi
}

cmd_merge_approved() {
  local found=0

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$status_file")
    [ "$status" = "approved" ] || continue

    local task_id
    task_id=$(basename "$(dirname "$status_file")")
    local pr_url
    pr_url=$(jq -r '.pr_url // empty' "$status_file")
    local pr_number
    pr_number=$(echo "$pr_url" | grep -o '[0-9]*$' || echo "")

    if [ "$DRY_RUN" = true ]; then
      log "[DRY-RUN] Would merge $task_id (PR #${pr_number:-?})"
      found=$((found + 1))
      continue
    fi

    echo "Merging $task_id..."

    # Find close-task.sh (pack or installed)
    local close_script=""
    if [ -f "$PROJECT_ROOT/scripts/agentsquad/close-task.sh" ]; then
      close_script="$PROJECT_ROOT/scripts/agentsquad/close-task.sh"
    elif [ -f "$PROJECT_ROOT/packs/github/scripts/close-task.sh" ]; then
      close_script="$PROJECT_ROOT/packs/github/scripts/close-task.sh"
    elif [ -f "$SCRIPT_DIR/../../packs/github/scripts/close-task.sh" ]; then
      close_script="$SCRIPT_DIR/../../packs/github/scripts/close-task.sh"
    fi

    if [ -n "$close_script" ]; then
      # Set status to "merged" BEFORE close-task.sh, which archives/deletes the task dir
      bash "$SCRIPT_DIR/update-status.sh" "$task_id" status "merged"
      if (cd "$PROJECT_ROOT" && bash "$close_script" "$task_id" 2>&1); then
        bash "$SCRIPT_DIR/notify.sh" "$(printf '\xE2\x9C\x85') *${task_id}* merged (PR #${pr_number:-?})" 2>/dev/null || true
        echo "Merged: $task_id (PR #${pr_number:-?})"
        found=$((found + 1))
      else
        echo "WARNING: close-task.sh failed for $task_id but status already set to merged" >&2
        found=$((found + 1))
      fi
    else
      # No close-task.sh — try direct merge via gh
      if [ -n "$pr_number" ]; then
        if (cd "$PROJECT_ROOT" && gh pr merge "$pr_number" --squash --delete-branch 2>&1); then
          bash "$SCRIPT_DIR/update-status.sh" "$task_id" status "merged"
          bash "$SCRIPT_DIR/notify.sh" "$(printf '\xE2\x9C\x85') *${task_id}* merged (PR #${pr_number})" 2>/dev/null || true
          echo "Merged: $task_id (PR #${pr_number})"
          found=$((found + 1))
        else
          echo "ERROR: Merge failed for $task_id — leaving status at approved" >&2
        fi
      else
        echo "ERROR: No PR number and no close-task.sh for $task_id" >&2
      fi
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "No tasks merged this cycle."
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

    # Only check active statuses — skip completed/finalized/ready-for-review
    case "$status" in
      in_progress|implementing|testing-local|investigating|spawned) ;;
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

cmd_spawn_all() {
  local spawned=0
  local -a failed_tasks=()
  local spawn_attempts=0
  local MAX_SPAWN_ATTEMPTS=$((MAX_WORKERS + 2))  # allow headroom for failures

  while true; do
    spawn_attempts=$((spawn_attempts + 1))
    if [ "$spawn_attempts" -gt "$MAX_SPAWN_ATTEMPTS" ]; then
      log "Reached max spawn attempts ($MAX_SPAWN_ATTEMPTS) this tick — stopping"
      break
    fi
    # Count active workers
    local active
    active=$(bash "$SCRIPT_DIR/check-workers.sh" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)

    if [ "$active" -ge "$MAX_WORKERS" ]; then
      log "At capacity ($active/$MAX_WORKERS workers)"
      break
    fi

    # Find next ready task with all deps met
    local next=""
    for sf in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
      [ -f "$sf" ] || continue
      local s
      s=$(jq -r '.status // "unknown"' "$sf")
      [ "$s" = "ready" ] || continue

      local tid
      tid=$(basename "$(dirname "$sf")")

      # Check dependencies
      local dep_result
      dep_result=$(check_deps_met "$tid" 2>&1) || {
        if [ "$dep_result" = "blocked" ]; then
          if [ "$DRY_RUN" = true ]; then
            log "[DRY-RUN] Would block $tid (dependency blocked/failed)"
          else
            echo "Blocking $tid (dependency blocked/failed)"
            bash "$SCRIPT_DIR/update-status.sh" "$tid" status "blocked" 2>/dev/null || true
          fi
        fi
        continue
      }

      # Skip tasks that already failed in this tick
      local is_failed=false
      for f in "${failed_tasks[@]+"${failed_tasks[@]}"}"; do
        if [ "$f" = "$tid" ]; then is_failed=true; break; fi
      done
      [ "$is_failed" = true ] && continue

      next="$tid"
      break
    done

    if [ -z "$next" ]; then
      log "No more ready tasks with deps met"
      break
    fi

    if [ "$DRY_RUN" = true ]; then
      log "[DRY-RUN] Would spawn worker for $next"
      ((spawned++))
      # In dry-run, break after first to avoid infinite loop (no actual state change)
      break
    fi

    # Create worktree and spawn
    local branch="task/$next"
    local wt_path
    wt_path=$(cd "$PROJECT_ROOT" && create_worktree "$next" "$branch") || {
      echo "ERROR: Failed to create worktree for $next" >&2
      failed_tasks+=("$next")
      continue
    }

    echo "Spawning: $next (worktree: $wt_path)"
    AGENTSQUAD_WORKDIR="$PROJECT_ROOT/$wt_path" AGENTSQUAD_PROJECT_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/spawn-worker.sh" "$next"
    ((spawned++))
  done

  if [ "$spawned" -gt 0 ]; then
    log "Spawned $spawned worker(s)"
  fi
}

cmd_cycle_summary() {
  local merged="" review_ready="" active="" queued="" blocked=""
  local approval_mode="manual"

  # Read global approval mode
  if [ -f "$CONFIG_FILE" ]; then
    local mode
    mode=$(jq -r '.approval.default // empty' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$mode" ] && approval_mode="$mode"
  fi

  for status_file in "$PROJECT_ROOT/$TASKS_DIR"/*/status.json; do
    [ -f "$status_file" ] || continue
    local task_id
    task_id=$(basename "$(dirname "$status_file")")
    [[ "$task_id" == _* ]] && continue

    local status pr_url pr_number
    status=$(jq -r '.status // "unknown"' "$status_file")
    pr_url=$(jq -r '.pr_url // empty' "$status_file")
    pr_number=$(echo "$pr_url" | grep -o '[0-9]*$' || echo "")

    case "$status" in
      merged)
        merged="${merged:+$merged, }${task_id}${pr_number:+ (PR #$pr_number)}"
        ;;
      review-ready)
        review_ready="${review_ready:+$review_ready, }${task_id}${pr_number:+ (PR #$pr_number)}"
        ;;
      in_progress|implementing|testing-local|investigating|approved|ready-for-review|pr-created)
        active="${active:+$active, }$task_id"
        ;;
      ready)
        queued="${queued:+$queued, }$task_id"
        ;;
      blocked)
        blocked="${blocked:+$blocked, }$task_id"
        ;;
    esac
  done

  local summary
  summary=$(cat <<EOF
$(printf '\xF0\x9F\x93\x8A') Conductor Cycle:
$(printf '\xE2\x9C\x85') Merged: ${merged:-\xe2\x80\x94}
$(printf '\xF0\x9F\x94\x8D') Review Ready: ${review_ready:-\xe2\x80\x94}
$(printf '\xE2\x9A\x99\xEF\xB8\x8F') Active: ${active:-\xe2\x80\x94}
$(printf '\xF0\x9F\x93\x8B') Queued: ${queued:-\xe2\x80\x94}
$(printf '\xF0\x9F\x94\xB4') Blocked: ${blocked:-\xe2\x80\x94}
Mode: ${approval_mode}
EOF
  )

  echo "$summary"

  if [ "$DRY_RUN" = false ]; then
    bash "$SCRIPT_DIR/notify.sh" "$summary" 2>/dev/null || true
  fi
}

# ── The tick ─────────────────────────────────────────────────
run_tick() {
  log "=== Conductor tick started ==="

  log "--- Step 1: Finalize completed workers ---"
  cmd_finalize_all

  log "--- Step 2: Check review artifacts ---"
  cmd_check_reviews

  log "--- Step 3: Apply approval policy ---"
  cmd_approve_ready

  log "--- Step 4: Merge approved tasks ---"
  cmd_merge_approved

  log "--- Step 5: Health check ---"
  local health_output
  health_output=$(cmd_health)
  echo "$health_output"

  # Handle stuck workers (kill tmux window, mark blocked)
  echo "$health_output" | { grep "^STUCK:" || true; } | while read -r line; do
    local stuck_task
    stuck_task=$(echo "$line" | awk '{print $2}')
    if [ "$DRY_RUN" = true ]; then
      log "[DRY-RUN] Would kill stuck worker: $stuck_task"
    else
      local window_name="task-${stuck_task}"
      tmux kill-window -t "${SESSION}:${window_name}" 2>/dev/null || true
      bash "$SCRIPT_DIR/update-status.sh" "$stuck_task" status "blocked" 2>/dev/null || true
      bash "$SCRIPT_DIR/update-status.sh" "$stuck_task" blocked_reason "stuck — no status update for 45+ minutes" 2>/dev/null || true
      log "Killed stuck worker: $stuck_task"
    fi
  done

  log "--- Step 6: Spawn workers ---"
  cmd_spawn_all

  log "--- Step 7: Cycle summary ---"
  cmd_cycle_summary

  log "=== Conductor tick completed ==="
}

# ── Loop mode ────────────────────────────────────────────────
run_loop() {
  log "Conductor loop started (interval: ${INTERVAL_SECONDS}s)"

  trap 'log "Conductor stopped"; release_tick_lock; exit 0' INT TERM

  while true; do
    acquire_tick_lock
    run_tick
    release_tick_lock
    sleep "$INTERVAL_SECONDS"
  done
}

# ── Main dispatch ────────────────────────────────────────────

# Handle standalone subcommands first
if [ -n "$SUBCMD" ]; then
  case "$SUBCMD" in
    status)
      cmd_status
      ;;
    finalize)
      if [ -z "$SUBCMD_ARG" ]; then
        echo "Usage: conductor.sh finalize <task-id>" >&2
        exit 1
      fi
      cmd_finalize "$SUBCMD_ARG"
      ;;
    health)
      cmd_health
      ;;
  esac
  exit 0
fi

# Handle run modes
case "$MODE" in
  once)
    acquire_tick_lock
    run_tick
    release_tick_lock
    ;;
  loop)
    run_loop
    ;;
esac
