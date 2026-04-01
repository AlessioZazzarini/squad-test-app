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

### Step 3: Health check

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

### Step 4: Spawn new workers

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

### Step 5: Report

Run: `bash scripts/agentsquad/conductor.sh status`

Output a summary table:

```
| Status | Count | Tasks |
|--------|-------|-------|
| Active | N | issue-1, issue-3 |
| Completed | N | issue-2 (PR #5) |
| Queued | N | issue-4 |
| Blocked | N | - |
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
