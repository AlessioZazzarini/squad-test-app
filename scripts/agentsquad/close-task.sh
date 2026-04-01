#!/bin/bash
# Usage: close-task.sh <task_id>
# Post-approval pipeline: archive task, close GitHub issue, clean up.
#
# Derives branch and PR from task ID convention (task/<task_id>).
# Does NOT depend on status.json for branch/PR info.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-.tasks}"

TASK_ID="${1:?Usage: close-task.sh <task_id>}"
TASK_DIR="$PROJECT_ROOT/${TASKS_DIR}/${TASK_ID}"
BRANCH="task/${TASK_ID}"

# --- Dirty tree check ---
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "ERROR: Working tree is dirty. Commit or stash changes first." >&2
  git status --short >&2
  exit 1
fi

# --- Derive PR from branch name ---
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null || echo "")
if [ -z "$PR_NUMBER" ]; then
  # No open PR — already merged or never created. Archive and exit cleanly.
  echo "No open PR for ${BRANCH} — already merged or never created. Archiving." >&2
  if [ -d "$TASK_DIR" ]; then
    mkdir -p "$PROJECT_ROOT/${TASKS_DIR}/_completed"
    mv "$TASK_DIR" "$PROJECT_ROOT/${TASKS_DIR}/_completed/${TASK_ID}"
    git add "${TASKS_DIR}/" 2>/dev/null || true
    git commit -m "chore: archive ${TASK_ID} (already merged)" 2>/dev/null || true
    echo "  Archived to ${TASKS_DIR}/_completed/${TASK_ID}"
  fi
  exit 0
fi

# --- Derive issue from PR body (looks for "Fixes #X") ---
ISSUE_NUMBER=$(gh pr view "$PR_NUMBER" --json body -q '.body' 2>/dev/null | grep -o 'Fixes #[0-9]*' | grep -o '[0-9]*' || echo "")

echo "=== Closing task: ${TASK_ID} ==="
echo "  Branch: ${BRANCH}"
echo "  PR: #${PR_NUMBER}"
echo "  Issue: ${ISSUE_NUMBER:+#$ISSUE_NUMBER}${ISSUE_NUMBER:-none}"
echo ""

# --- Step 1: Squash-merge ---
echo "Step 1: Squash-merging PR #${PR_NUMBER}..."
if ! gh pr merge "$PR_NUMBER" --squash --delete-branch 2>&1; then
  echo "STOPPED: Merge failed. Check GitHub for details."
  exit 1
fi
echo "  Merged and branch deleted."

# --- Step 2: Pull latest main ---
echo "Step 2: Pulling latest main..."
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
git checkout "$MAIN_BRANCH" 2>/dev/null || true
git pull origin "$MAIN_BRANCH" 2>/dev/null || true

# --- Step 3: Post completion comment to GitHub issue ---
if [ -n "$ISSUE_NUMBER" ]; then
  echo "Step 3: Posting completion comment..."
  gh issue comment "$ISSUE_NUMBER" --body "Task completed. PR #${PR_NUMBER} merged." 2>/dev/null || true
fi

# --- Step 4: Archive task + clean up ---
echo "Step 4: Archiving task..."
if [ -d "$TASK_DIR" ]; then
  mkdir -p "$PROJECT_ROOT/${TASKS_DIR}/_completed"
  mv "$TASK_DIR" "$PROJECT_ROOT/${TASKS_DIR}/_completed/${TASK_ID}"
  git add "${TASKS_DIR}/" 2>/dev/null || true
  git commit -m "chore: archive ${TASK_ID} after merge" 2>/dev/null || true
  git push origin "$MAIN_BRANCH" 2>/dev/null || true
  echo "  Archived to ${TASKS_DIR}/_completed/${TASK_ID}"
else
  echo "  Task dir not found (already archived)"
fi

# --- Step 5: Close GitHub issue if not auto-closed ---
if [ -n "$ISSUE_NUMBER" ]; then
  gh issue close "$ISSUE_NUMBER" 2>/dev/null || true
  echo "  Issue #${ISSUE_NUMBER} closed."
fi

# --- Done ---
echo ""
echo "=== Task ${TASK_ID} closed ==="
echo "  PR #${PR_NUMBER} merged"
[ -n "$ISSUE_NUMBER" ] && echo "  Issue #${ISSUE_NUMBER} closed"
echo "  Archived to ${TASKS_DIR}/_completed/"

# Notify if webhook is configured
NOTIFY_SCRIPT="$(cd "$SCRIPT_DIR/../../core/scripts" && pwd)/notify.sh"
if [ -f "$NOTIFY_SCRIPT" ]; then
  bash "$NOTIFY_SCRIPT" "Task *${TASK_ID}* merged (PR #${PR_NUMBER})" 2>/dev/null || true
fi
