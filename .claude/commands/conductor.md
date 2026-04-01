---
description: "Run the Conductor — the single orchestration engine for AgentSquad"
---

# /conductor — Run the Orchestration Engine

The Conductor is AgentSquad's single orchestration engine. It runs an idempotent tick that manages the full task lifecycle: finalize, review, approve, merge, health check, and spawn.

## Run Modes

```bash
# Single tick (default — run once, exit)
bash scripts/agentsquad/conductor.sh
bash scripts/agentsquad/conductor.sh --once

# Continuous mode (tick every N minutes/seconds)
bash scripts/agentsquad/conductor.sh --loop 3m
bash scripts/agentsquad/conductor.sh --loop 30s

# Dry-run (preview what would happen, no changes)
bash scripts/agentsquad/conductor.sh --dry-run

# Standalone subcommands
bash scripts/agentsquad/conductor.sh status           # JSON summary
bash scripts/agentsquad/conductor.sh finalize <id>     # Finalize specific task
bash scripts/agentsquad/conductor.sh health            # Health check workers
```

### From Claude Code

```bash
# Manual single tick
/conductor

# Continuous (via /loop command)
/loop 5m /conductor
```

## The Tick

Every tick runs these 7 steps in order:

| Step | Function | What it does |
|------|----------|-------------|
| 1 | `cmd_finalize_all` | Find `ready-for-review` tasks, push branch, create PR, set `pr-created` |
| 2 | `cmd_check_reviews` | Find `pr-created` tasks with `pr-review.md`, promote to `review-ready` |
| 3 | `cmd_approve_ready` | Apply approval policy (manual/auto/paused) to `review-ready` tasks |
| 4 | `cmd_merge_approved` | Merge `approved` tasks via `close-task.sh` or `gh pr merge` |
| 5 | `cmd_health` | Check worker health: OK (<20m), WARNING (20-45m), STUCK (>45m). Kill stuck workers. |
| 6 | `cmd_spawn_all` | Loop: spawn workers until at capacity (MAX_WORKERS) or no ready tasks with deps met |
| 7 | `cmd_cycle_summary` | Send notification summary of full cycle |

### Tick Locking

Only one tick runs at a time, enforced via `flock`. If a second invocation arrives while a tick is running, it exits silently. Safe for concurrent `/loop` and manual `/conductor` calls.

## Approval Modes

| Mode | Who approves | When to use |
|------|-------------|-------------|
| `manual` (default) | Human reviews PR, then `update-status.sh <id> status approved` | Production repos |
| `auto` | Conductor auto-approves after CI green + sensitive paths check | Trusted repos |
| `paused` | Nobody — all merges halted | Emergencies, code freezes |

Configure globally in `.claude/agentsquad.json`:
```json
{ "approval": { "default": "manual" } }
```

Per-task override: set `approval_mode` in `status.json`.

## Dry-Run Mode

Every step checks `$DRY_RUN` and logs what it WOULD do without making changes:

```
[14:30:00] === Conductor tick started ===
[14:30:00] --- Step 1: Finalize completed workers ---
[14:30:00] [DRY-RUN] Would finalize issue-42
[14:30:00] --- Step 6: Spawn workers ---
[14:30:00] [DRY-RUN] Would spawn worker for issue-45
[14:30:00] === Conductor tick completed ===
```

## Workflow

### Step 1: Pre-flight
- Verify `.tasks/` directory exists
- Read `.claude/agentsquad.json` for config (approval mode, max workers, etc.)

```bash
bash scripts/agentsquad/conductor.sh --once
```

### Step 2: Report Results

Report what happened during the tick:

```
=== Conductor Cycle ===

Finalize:
  + issue-42: pushed branch, created PR #17

Reviews:
  + issue-40: promoted to review-ready

Approvals:
  Manual approval required: issue-40

Health:
  OK: issue-45 (3m since update)
  WARNING: issue-48 (22m since update)

Spawn:
  Spawned: issue-50
  At capacity (3/3 workers active)

Summary:
  Merged: --
  Review Ready: issue-40 (PR #15)
  Active: issue-45, issue-48, issue-50
  Queued: issue-51, issue-52
  Blocked: --
  Mode: manual
```

## Continuous Mode

For hands-off operation, run the Conductor in a loop:

```bash
# From a tmux session
bash scripts/agentsquad/conductor.sh --loop 3m

# Or via Claude Code
/loop 5m /conductor
```

The loop acquires a tick lock each cycle, runs the tick, releases the lock, then sleeps. Ctrl+C stops cleanly.

## Examples

### Manual Single Tick

```
User: /conductor

Claude:
=== Conductor Cycle ===

Finalize: No tasks to finalize.
Reviews: No tasks to promote.
Approvals: No tasks to approve.
Health: OK: issue-12 (5m since update)
Spawn: Spawned issue-15. At capacity (3/3).
Summary sent.
```

### Dry-Run Preview

```
User: /conductor --dry-run

Claude:
[DRY-RUN] Would finalize issue-42
[DRY-RUN] Would promote issue-40 to review-ready
[DRY-RUN] Would spawn worker for issue-45
```

### Continuous

```
User: /loop 5m /conductor

Claude: Loop started. Running /conductor every 5 minutes.
```
