---
description: "Run one orchestration cycle: finalize completed workers, check health, spawn new workers"
---

# /conductor — Run One Orchestration Cycle

Run a single conductor cycle. Can be invoked manually or via `/loop 5m /conductor` for continuous operation.

## Workflow

### Step 1: Pre-flight
- Verify tmux session exists (use AGENTSQUAD_TMUX_SESSION or basename of pwd)
- Read .claude/agentsquad.json for config
- If no .tasks/ directory, report and exit

```bash
SESSION="${AGENTSQUAD_TMUX_SESSION:-$(basename "$(pwd)")}"
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "ERROR: tmux session '$SESSION' not found"
    exit 1
fi
if [ ! -d ".tasks" ]; then
    echo "No .tasks/ directory — nothing to orchestrate."
    exit 0
fi
```

### Step 2: Finalize completed workers

Run: `bash scripts/agentsquad/conductor.sh finalize-all`

This finds all tasks with status "ready-for-review" and for each one:
- Pushes the branch to origin
- Creates a PR (idempotent — skips if one already exists)
- Updates GitHub labels (squad:in-progress -> squad:complete)
- Cleans the worktree
- Updates task status to "pr-created"

Report what was finalized.

### Step 3: Check review artifacts

Run: `bash scripts/agentsquad/conductor.sh check-reviews`

This finds all tasks with status "pr-created" and checks if `.tasks/<task-id>/pr-review.md` exists. If yes, promotes the task to "review-ready" and sends a notification.

### Step 4: Apply approval policy

Run: `bash scripts/agentsquad/conductor.sh approve-ready`

For tasks with status "review-ready", reads the approval mode (per-task override or global config default):
- **manual**: do nothing — wait for human to set "approved" via update-status.sh
- **auto**: check CI status (`gh pr checks`) + sensitive paths policy. If all gates pass, set "approved".
- **paused**: do nothing — global kill switch, no merges.

### Step 5: Merge approved tasks

Run: `bash scripts/agentsquad/conductor.sh merge-approved`

For tasks with status "approved":
- Runs `close-task.sh` (squash-merge + issue close + archive)
- Sets status to "merged" on success
- Leaves status at "approved" on failure

### Step 6: Health check

Run: `bash scripts/agentsquad/conductor.sh health`

This checks each active worker and reports:
- **OK** — updated within last 20 minutes
- **WARNING** — no update for 20-45 minutes
- **STUCK** — no update for 45+ minutes

For stuck workers: kill the tmux window, mark status "blocked" with reason "stuck — no update for N minutes".

```bash
HEALTH_OUTPUT=$(bash scripts/agentsquad/conductor.sh health)
echo "$HEALTH_OUTPUT"

# Handle stuck workers
echo "$HEALTH_OUTPUT" | grep "^STUCK:" | while read -r line; do
    TASK_ID=$(echo "$line" | awk '{print $2}')
    WINDOW_NAME="task-${TASK_ID}"
    tmux kill-window -t "${SESSION}:${WINDOW_NAME}" 2>/dev/null || true
    bash scripts/agentsquad/update-status.sh "$TASK_ID" status "blocked"
    bash scripts/agentsquad/update-status.sh "$TASK_ID" blocked_reason "stuck — no status update for 45+ minutes"
done
```

### Step 7: Spawn new workers

Run: `bash scripts/agentsquad/conductor.sh spawn-next` (repeat until at capacity or no ready tasks)

```bash
while true; do
    OUTPUT=$(bash scripts/agentsquad/conductor.sh spawn-next 2>&1)
    echo "$OUTPUT"
    # Stop if at capacity or no ready tasks
    if echo "$OUTPUT" | grep -qE "(At capacity|No ready tasks)"; then
        break
    fi
done
```

### Step 8: Cycle summary

Run: `bash scripts/agentsquad/conductor.sh cycle-summary`

Sends a notification with the full cycle summary:

```
📊 Conductor Cycle:
✅ Merged: issue-3 (PR #12)
🔍 Review Ready: issue-5 (PR #14)
⚙️ Active: issue-7, issue-8
📋 Queued: issue-9
🔴 Blocked: —
Mode: manual
```

## Continuous Mode

To run the conductor continuously:

```bash
# In a tmux session with Claude Code:
/loop 5m /conductor
```

This runs one cycle every 5 minutes, continuously watching the queue.

## Examples

### Manual Run

```
User: /conductor

Claude:
=== Conductor Cycle ===

Pre-flight: tmux session 'myproject' OK, .tasks/ found

Finalize:
  + task-42: pushed branch, created PR #17
  No other tasks to finalize

Health:
  OK: task-45 (3m since update)
  WARNING: task-48 (22m since update)

Spawn:
  Spawned: task-50
  At capacity (3/3 workers active)

Summary:
| Status | Count | Tasks |
|--------|-------|-------|
| Active | 3 | task-45, task-48, task-50 |
| Completed | 1 | task-42 (PR #17) |
| Queued | 2 | task-51, task-52 |
| Blocked | 0 | - |
```

### Continuous Mode

```
User: /loop 5m /conductor

Claude: Loop started. Running /conductor every 5 minutes.
```
