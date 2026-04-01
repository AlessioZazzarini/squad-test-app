#!/bin/bash
# orchestrate-parallel.sh — Wave-based parallel task execution
#
# Processes tasks from the orchestration manifest in dependency-respecting waves.
# Independent tasks within each wave run in parallel (up to AGENTSQUAD_MAX_PARALLEL).
# Each worker gets an isolated git worktree and namespaced task session files.
#
# Usage:
#   ./scripts/agentsquad/orchestrate-parallel.sh [max_iterations_per_task]
#
# Environment:
#   AGENTSQUAD_MAX_PARALLEL     — max concurrent workers (default: 3)
#   AGENTSQUAD_TMUX_SESSION     — tmux session name (default: basename of pwd)
#   AGENTSQUAD_TASKS_DIR        — task directory (default: .tasks)
#
# This script auto-resumes from manifest state. Safe to interrupt and restart.
#
# Fixes applied from adversarial review (Codex gpt-5.4):
#   1. Git worktrees for parallel isolation (no shared working directory)
#   2. Namespaced session files per issue (.tasks/sessions/issue-<N>/)
#   3. flock + $BASHPID for manifest serialization
#   4. Atomic set_issue_status (single jq call)
#   5. compute_next_wave logs to stderr (no stdout contamination)
#   6. Dependency branches merged into dependent task branches
#   7. Crash recovery: in_progress tasks reset to queued on startup
#   8. PID lockfile prevents duplicate orchestration runs
#   9. wait -n replaces kill -0 polling loop
#  10. loop.sh exit code checked for completion vs max-iterations

set -o pipefail

# ── Load shared config ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/worktree.sh"

# ── Configuration ─────────────────────────────────────────────
MANIFEST_FILE=".tasks/orchestration-manifest.json"
MANIFEST_LOCK=".tasks/orchestration.lock"
LOG_FILE=".tasks/orchestration.log"
PID_FILE=".tasks/orchestration.pid"
MAX_ITERATIONS="${1:-20}"
MAX_PARALLEL="${AGENTSQUAD_MAX_WORKERS:-3}"
TMUX_SESSION="${AGENTSQUAD_TMUX_SESSION:-$(basename "$(pwd)")}"
TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-.tasks}"
MAIN_BRANCH="${AGENTSQUAD_MAIN_BRANCH:-main}"
PROJECT_ROOT="$(pwd)"

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Logging ───────────────────────────────────────────────────
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

log_section() {
    log ""
    log "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    log "${BLUE}  $1${NC}"
    log "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# ── Orchestration lock (prevent duplicate runs) ───────────────
acquire_lock() {
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            echo -e "${RED}Error: Another orchestration is already running (PID $old_pid).${NC}"
            echo "Kill it first or wait for it to finish."
            exit 1
        fi
        # Stale PID file — previous run crashed
        rm -f "$PID_FILE"
    fi
    echo $$ > "$PID_FILE"
}

release_lock() {
    rm -f "$PID_FILE"
}

# ── Manifest helpers (serialized via flock) ───────────────────
# FIX #3: Use flock for serialization and $BASHPID for unique temp files.
# All manifest writes go through this to prevent concurrent corruption.

manifest_write() {
    # $1 = jq filter, rest = jq args
    # Acquires exclusive lock, applies jq transform, writes atomically
    local filter="$1"
    shift
    (
        flock -x 200
        local tmp="${MANIFEST_FILE}.tmp.${BASHPID:-$$}.$(date +%N)"
        jq "$@" "$filter" "$MANIFEST_FILE" > "$tmp" && mv "$tmp" "$MANIFEST_FILE"
    ) 200>"$MANIFEST_LOCK"
}

update_manifest_issue() {
    local issue=$1 field=$2 value=$3
    manifest_write \
        '(.issues[] | select(.number == $num))[$field] = $value' \
        --argjson num "$issue" --arg field "$field" --argjson value "$value"
}

# FIX #4: Atomic status + timestamp update in a single jq call
set_issue_status() {
    local issue=$1 status=$2
    local now
    now="$(date -Iseconds)"

    local jq_filter
    if [[ "$status" == "in_progress" ]]; then
        jq_filter='(.issues[] | select(.number == $num)) |= (.status = $s | .started_at = $now)'
    elif [[ "$status" == "complete" || "$status" == "failed" || "$status" == "skipped" ]]; then
        jq_filter='(.issues[] | select(.number == $num)) |= (.status = $s | .completed_at = $now)'
    else
        jq_filter='(.issues[] | select(.number == $num)).status = $s'
    fi

    manifest_write "$jq_filter" --argjson num "$issue" --arg s "$status" --arg now "$now"
}

update_manifest_status() {
    local status=$1
    manifest_write '.status = $s | .updated_at = (now | todate)' --arg s "$status"
}

# ── Dependency logic ──────────────────────────────────────────

deps_met() {
    local issue=$1
    local deps
    deps=$(jq -r --argjson n "$issue" \
        '(.issues[] | select(.number == $n)).dependencies // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)
    for dep in $deps; do
        [[ -z "$dep" ]] && continue
        local s
        s=$(jq -r --argjson n "$dep" \
            '(.issues[] | select(.number == $n)).status // "unknown"' "$MANIFEST_FILE")
        if [[ "$s" != "complete" ]]; then
            return 1
        fi
    done
    return 0
}

deps_failed() {
    local issue=$1
    local deps
    deps=$(jq -r --argjson n "$issue" \
        '(.issues[] | select(.number == $n)).dependencies // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)
    for dep in $deps; do
        [[ -z "$dep" ]] && continue
        local s
        s=$(jq -r --argjson n "$dep" \
            '(.issues[] | select(.number == $n)).status // "unknown"' "$MANIFEST_FILE")
        if [[ "$s" == "failed" || "$s" == "skipped" ]]; then
            echo "$dep"
            return 0
        fi
    done
    return 1
}

# Get dependency branches for an issue (for merging into dependent branch)
get_dep_branches() {
    local issue=$1
    local deps
    deps=$(jq -r --argjson n "$issue" \
        '(.issues[] | select(.number == $n)).dependencies // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)
    for dep in $deps; do
        [[ -z "$dep" ]] && continue
        local branch
        branch=$(jq -r --argjson n "$dep" \
            '(.issues[] | select(.number == $n)).branch // empty' "$MANIFEST_FILE" 2>/dev/null)
        [[ -n "$branch" ]] && echo "$branch"
    done
}

# FIX #5: compute_next_wave logs to stderr, returns ONLY issue numbers on stdout
compute_next_wave() {
    local queued
    queued=$(jq -r '.issues[] | select(.status == "queued" or .status == "pending") | .number' "$MANIFEST_FILE")

    local wave=()
    for issue in $queued; do
        [[ -z "$issue" ]] && continue

        local blocker
        if blocker=$(deps_failed "$issue"); then
            # Log to STDERR so it doesn't contaminate stdout capture
            log "${YELLOW}⏭  Skipping #$issue — blocked by failed #$blocker${NC}" >&2
            set_issue_status "$issue" "skipped"
            update_manifest_issue "$issue" "error" "\"Blocked by failed #$blocker\""
            continue
        fi

        if deps_met "$issue"; then
            wave+=("$issue")
        fi
    done

    echo "${wave[@]}"
}

# ── Git worktree management ───────────────────────────────────
# FIX #1: Each worker gets an isolated git worktree. No shared working directory.
# Core functions (create_worktree, cleanup_worktree) sourced from lib/worktree.sh.
# Override WORKTREE_BASE to use issue-prefixed paths for the manifest workflow.
WORKTREE_BASE=".tasks/worktrees"

# Override create_worktree for manifest workflow (uses issue-prefixed paths)
create_worktree() {
    local issue=$1 branch=$2
    local wt_path="${WORKTREE_BASE}/issue-${issue}"

    if [[ -d "$wt_path" ]]; then
        git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
    fi

    git branch -D "$branch" 2>/dev/null || true
    git worktree add "$wt_path" -b "$branch" "$MAIN_BRANCH" 2>/dev/null || {
        git worktree add "$wt_path" "$branch" 2>/dev/null || {
            log "${RED}✗ Failed to create worktree for #$issue${NC}" >&2
            return 1
        }
    }

    local dep_branches
    dep_branches=$(get_dep_branches "$issue")
    if [[ -n "$dep_branches" ]]; then
        (
            cd "$wt_path"
            for dep_branch in $dep_branches; do
                if git rev-parse --verify "origin/$dep_branch" &>/dev/null; then
                    log "  Merging dependency branch: $dep_branch" >&2
                    git merge "origin/$dep_branch" --no-edit 2>/dev/null || {
                        log "${YELLOW}  Warning: merge conflict with $dep_branch — continuing without it${NC}" >&2
                        git merge --abort 2>/dev/null || true
                    }
                fi
            done
        )
    fi

    echo "$wt_path"
}

cleanup_worktree() {
    local issue=$1
    local wt_path="${WORKTREE_BASE}/issue-${issue}"
    git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
}

# ── Single task processing (runs in worktree) ────────────────
# FIX #2: Session files namespaced per issue in .tasks/sessions/issue-<N>/

process_issue() {
    local issue=$1
    local title
    title=$(jq -r --argjson n "$issue" '(.issues[] | select(.number == $n)).title' "$MANIFEST_FILE")

    log_section "Processing #$issue: $title"
    set_issue_status "$issue" "in_progress"

    if command -v gh &>/dev/null; then
        gh issue edit "$issue" --remove-label "squad:queued" --add-label "squad:in-progress" 2>/dev/null || true
    fi

    # Create isolated worktree
    local branch="task/issue-$issue"
    local wt_path
    wt_path=$(create_worktree "$issue" "$branch")
    if [[ $? -ne 0 ]] || [[ -z "$wt_path" ]]; then
        handle_failure "$issue" "Worktree creation failed"
        return 1
    fi

    log "Working in worktree: $wt_path"

    # Create namespaced session directory
    local session_dir="${PROJECT_ROOT}/.tasks/sessions/issue-${issue}"
    mkdir -p "$session_dir"

    # Run taskify in the worktree (fresh Claude session)
    log "${CYAN}Running /taskify $issue in worktree...${NC}"
    if ! (cd "$wt_path" && claude -p "/taskify $issue" --dangerously-skip-permissions) 2>&1 | tee -a "$LOG_FILE"; then
        log "${RED}✗ Taskify failed for #$issue${NC}"
        handle_failure "$issue" "Taskify failed"
        cleanup_worktree "$issue"
        return 1
    fi

    # FIX #2: Copy session files to namespaced location for archival
    if [[ -f "$wt_path/.tasks/plan.md" ]]; then
        cp "$wt_path/.tasks/plan.md" "$session_dir/plan.md" 2>/dev/null || true
        cp "$wt_path/.tasks/PROMPT.md" "$session_dir/PROMPT.md" 2>/dev/null || true
        cp "$wt_path/.tasks/activity.md" "$session_dir/activity.md" 2>/dev/null || true
    fi

    # Run task loop in the worktree
    # FIX #10: Check exit code — loop.sh should exit non-zero if not completed
    log "${CYAN}Running task loop ($MAX_ITERATIONS iterations)...${NC}"
    if [[ -x "$wt_path/.tasks/loop.sh" ]]; then
        if ! (cd "$wt_path" && .tasks/loop.sh "$MAX_ITERATIONS") 2>&1 | tee -a "$LOG_FILE"; then
            log "${RED}✗ Task loop failed or did not complete for #$issue${NC}"
            handle_failure "$issue" "Task loop did not complete"
            cleanup_worktree "$issue"
            return 1
        fi
    else
        log "${RED}✗ .tasks/loop.sh not found in worktree${NC}"
        handle_failure "$issue" "loop.sh not found"
        cleanup_worktree "$issue"
        return 1
    fi

    # Commit and push from worktree
    log "Committing and pushing..."
    (
        cd "$wt_path"
        git add -A
        if ! git diff --cached --quiet; then
            git commit -m "feat(#$issue): $title

Implemented via AgentSquad autonomous task loop.

Co-authored-by: Claude <noreply@anthropic.com>"
        fi
        git push -u origin "$branch"
    ) || {
        handle_failure "$issue" "Commit/push failed"
        cleanup_worktree "$issue"
        return 1
    }

    # Create PR
    if command -v gh &>/dev/null; then
        log "Creating pull request..."
        local pr_url
        pr_url=$(gh pr create \
            --head "$branch" \
            --title "feat(#$issue): $title" \
            --body "## Summary

Automated implementation of #$issue via AgentSquad orchestration.

Closes #$issue

---
*Generated by AgentSquad*" 2>&1) || {
            if echo "$pr_url" | grep -q "already exists"; then
                pr_url=$(gh pr view "$branch" --json url --jq '.url' 2>/dev/null) || true
            fi
        }

        local pr_number
        pr_number=$(echo "$pr_url" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || true)
        if [[ -n "$pr_number" ]]; then
            update_manifest_issue "$issue" "pr_number" "$pr_number"
            log "${GREEN}✓ Created PR #$pr_number${NC}"
        fi
    fi

    update_manifest_issue "$issue" "branch" "\"$branch\""

    # Cleanup worktree
    cleanup_worktree "$issue"

    # Mark complete
    set_issue_status "$issue" "complete"
    if command -v gh &>/dev/null; then
        gh issue edit "$issue" --remove-label "squad:in-progress" --add-label "squad:complete" 2>/dev/null || true
    fi

    log "${GREEN}✓ Completed #$issue${NC}"
    return 0
}

handle_failure() {
    local issue=$1 error_msg=$2
    set_issue_status "$issue" "failed"
    update_manifest_issue "$issue" "error" "\"$error_msg\""

    if command -v gh &>/dev/null; then
        gh issue edit "$issue" --remove-label "squad:in-progress" --add-label "squad:failed" 2>/dev/null || true
        gh issue comment "$issue" --body "⚠️ **AgentSquad orchestration failed**

Error: $error_msg

Check \`.tasks/orchestration.log\` for details." 2>/dev/null || true
    fi
}

# ── Wave execution engine ─────────────────────────────────────
# FIX #9: Use wait -n instead of kill -0 polling for cleaner process management

run_wave() {
    local wave=("$@")
    local wave_size=${#wave[@]}
    local completed=0
    local failed=0
    local active=0

    # Associative array: PID → issue number
    declare -A pid_map

    log "Wave size: $wave_size (max parallel: $MAX_PARALLEL)"

    for issue in "${wave[@]}"; do
        # Respect concurrency limit — wait for a slot
        while (( active >= MAX_PARALLEL )); do
            # wait -n waits for any child to exit (bash 4.3+)
            if wait -n 2>/dev/null; then
                :  # Child exited successfully
            fi
            # Recount active by checking which PIDs are still alive
            local new_active=0
            for pid in "${!pid_map[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    ((new_active++))
                else
                    # Harvest exit code
                    wait "$pid" 2>/dev/null
                    local ec=$?
                    local finished_issue="${pid_map[$pid]}"
                    if [[ $ec -eq 0 ]]; then
                        ((completed++))
                        log "${GREEN}✓ Worker for #$finished_issue done${NC}"
                    else
                        ((failed++))
                        log "${RED}✗ Worker for #$finished_issue failed (exit $ec)${NC}"
                    fi
                    unset "pid_map[$pid]"
                fi
            done
            active=$new_active
        done

        # Launch worker in background
        log "${CYAN}Launching worker for #$issue...${NC}"
        process_issue "$issue" &
        pid_map[$!]="$issue"
        ((active++))
    done

    # Wait for all remaining workers
    for pid in "${!pid_map[@]}"; do
        wait "$pid" 2>/dev/null
        local ec=$?
        local finished_issue="${pid_map[$pid]}"
        if [[ $ec -eq 0 ]]; then
            ((completed++))
            log "${GREEN}✓ Worker for #$finished_issue done${NC}"
        else
            ((failed++))
            log "${RED}✗ Worker for #$finished_issue failed (exit $ec)${NC}"
        fi
    done

    log "Wave results: $completed completed, $failed failed"
    return $failed
}

# ── Main ──────────────────────────────────────────────────────

main() {
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo -e "${RED}Error: $MANIFEST_FILE not found.${NC}"
        echo "Run /orchestrate first to generate the manifest."
        exit 1
    fi

    # FIX #8: Prevent duplicate orchestration runs
    acquire_lock

    # FIX #7: Crash recovery — reset in_progress tasks to queued
    local stuck
    stuck=$(jq '[.issues[] | select(.status == "in_progress")] | length' "$MANIFEST_FILE")
    if [[ "$stuck" -gt 0 ]]; then
        log "${YELLOW}Recovering $stuck tasks stuck in 'in_progress' from previous run...${NC}"
        manifest_write \
            '(.issues[] | select(.status == "in_progress")).status = "queued"'
    fi

    # Create worktree and session directories
    mkdir -p "$WORKTREE_BASE" ".tasks/sessions"

    log ""
    log "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    log "${BLUE}║          AgentSquad Parallel Orchestration — Starting                  ║${NC}"
    log "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    log ""
    log "Max iterations per task: $MAX_ITERATIONS"
    log "Max parallel workers:    $MAX_PARALLEL"
    log "Git worktrees:           $WORKTREE_BASE"
    log ""

    update_manifest_status "in_progress"

    local total_completed=0
    local total_failed=0
    local wave_num=0

    while true; do
        wave_num=$((wave_num + 1))

        local wave_str
        wave_str=$(compute_next_wave)

        local remaining
        remaining=$(jq '[.issues[] | select(.status == "queued" or .status == "pending")] | length' "$MANIFEST_FILE")

        if [[ -z "$wave_str" ]]; then
            if [[ "$remaining" -gt 0 ]]; then
                log "${YELLOW}$remaining tasks remain but all are blocked by failed dependencies${NC}"
            fi
            break
        fi

        local wave=($wave_str)

        log_section "Wave $wave_num: ${#wave[@]} tasks [${wave[*]}]"

        run_wave "${wave[@]}"

        # Count results from this wave
        for issue in "${wave[@]}"; do
            local s
            s=$(jq -r --argjson n "$issue" '(.issues[] | select(.number == $n)).status' "$MANIFEST_FILE")
            case "$s" in
                complete) ((total_completed++)) ;;
                failed)   ((total_failed++)) ;;
            esac
        done
    done

    local total_skipped
    total_skipped=$(jq '[.issues[] | select(.status == "skipped")] | length' "$MANIFEST_FILE")

    # Clean up worktree directory
    rmdir "$WORKTREE_BASE" 2>/dev/null || true

    # Final summary
    log ""
    log "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    log "${BLUE}║          AgentSquad Parallel Orchestration — Complete                   ║${NC}"
    log "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    log ""
    log "Waves executed: $wave_num"
    log "Results:"
    log "  ${GREEN}✓ Completed: $total_completed${NC}"
    log "  ${RED}✗ Failed:    $total_failed${NC}"
    log "  ${YELLOW}⏭ Skipped:   $total_skipped${NC}"
    log ""

    jq -r '.issues | sort_by(.priority) | .[] |
        "  \(if .status == "complete" then "✓" elif .status == "failed" then "✗" elif .status == "skipped" then "⏭" else "○" end) #\(.number) - \(.title)\(if .pr_number then " → PR #\(.pr_number)" else "" end)\(if .error then " (\(.error))" else "" end)"' "$MANIFEST_FILE" | while read -r line; do
        log "$line"
    done

    if [[ $total_failed -gt 0 ]]; then
        update_manifest_status "failed"
        release_lock
        exit 1
    else
        update_manifest_status "complete"
        release_lock
        log ""
        log "${GREEN}All tasks processed successfully! PRs ready for review.${NC}"
    fi
}

cleanup_on_exit() {
    release_lock
    echo -e "\n${YELLOW}Interrupted. Run this script again to resume from manifest state.${NC}"
    exit 130
}

trap cleanup_on_exit INT TERM

main "$@"
