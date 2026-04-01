#!/bin/bash
# worktree.sh — Git worktree management for AgentSquad parallel isolation
#
# Provides create_worktree, cleanup_worktree, and get_dep_branches helpers.
# Designed to be sourced by conductor.sh.
#
# Requires: lib/config.sh sourced first (for AGENTSQUAD_MAIN_BRANCH)

WORKTREE_BASE="${AGENTSQUAD_TASKS_DIR:-.tasks}/worktrees"
MAIN_BRANCH="${AGENTSQUAD_MAIN_BRANCH:-main}"

# Get dependency branches for a task by reading status.json files
# Usage: get_dep_branches <task_id>
get_dep_branches() {
  local task_id="$1"
  local tasks_dir="${AGENTSQUAD_TASKS_DIR:-.tasks}"
  local status_file="$tasks_dir/$task_id/status.json"

  [[ -f "$status_file" ]] || return 0

  local deps
  deps=$(jq -r '.dependencies // [] | .[]' "$status_file" 2>/dev/null || true)
  for dep in $deps; do
    [[ -z "$dep" ]] && continue
    local dep_status_file="$tasks_dir/$dep/status.json"
    [[ -f "$dep_status_file" ]] || continue
    local branch
    branch=$(jq -r '.branch // empty' "$dep_status_file" 2>/dev/null)
    [[ -n "$branch" ]] && echo "$branch"
  done
}

# Create an isolated git worktree for a task
# Usage: create_worktree <task_id> <branch_name>
# Outputs: worktree path on stdout
create_worktree() {
  local task_id="$1" branch="$2"
  local wt_path="${WORKTREE_BASE}/${task_id}"

  # Clean up stale worktree if it exists
  if [[ -d "$wt_path" ]]; then
    git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
  fi

  mkdir -p "$(dirname "$wt_path")"

  # Create branch from main
  git branch -D "$branch" 2>/dev/null || true
  git worktree add "$wt_path" -b "$branch" "$MAIN_BRANCH" 2>/dev/null || {
    # Branch might exist remotely
    git worktree add "$wt_path" "$branch" 2>/dev/null || {
      echo "ERROR: Failed to create worktree for $task_id" >&2
      return 1
    }
  }

  # Merge dependency branches so dependent tasks have their code
  local dep_branches
  dep_branches=$(get_dep_branches "$task_id")
  if [[ -n "$dep_branches" ]]; then
    (
      cd "$wt_path"
      for dep_branch in $dep_branches; do
        if git rev-parse --verify "origin/$dep_branch" &>/dev/null; then
          echo "  Merging dependency branch: $dep_branch" >&2
          git merge "origin/$dep_branch" --no-edit 2>/dev/null || {
            echo "  Warning: merge conflict with $dep_branch — continuing without it" >&2
            git merge --abort 2>/dev/null || true
          }
        fi
      done
    )
  fi

  echo "$wt_path"
}

# Remove a task's worktree
# Usage: cleanup_worktree <task_id>
cleanup_worktree() {
  local task_id="$1"
  local wt_path="${WORKTREE_BASE}/${task_id}"
  git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
}
