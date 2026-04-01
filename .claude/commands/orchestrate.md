# /orchestrate — Multi-Issue Task Orchestration

Orchestrate multiple GitHub issues through the autonomous worker pipeline with label-based state management.

## GitHub Labels

The following labels track task state (create them if missing):

| Label | Meaning |
|-------|---------|
| `squad:ready` | Task has acceptance criteria and is ready to be picked up |
| `squad:queued` | Task is in the queue, waiting for a worker slot |
| `squad:in-progress` | Worker is actively working on this task |
| `squad:complete` | Task is done, PR ready for review |
| `squad:failed` | Worker hit max attempts or was blocked |

## Workflow

### Phase 1: Triage and Queue

1. **Fetch eligible issues:**
   ```bash
   gh issue list --label "squad:ready" --json number,title,labels --limit 20
   ```

2. **Check dependencies.** Read each issue body for `depends-on: #N` lines. Build a dependency graph. Use topological sort with cycle detection — if cycles exist, flag them and skip those issues.

3. **Determine execution order.** Issues with no unresolved dependencies go first. Group by priority label if present.

4. **Label queued issues:**
   ```bash
   gh issue edit <number> --add-label "squad:queued" --remove-label "squad:ready"
   ```

### Phase 2: Spawn Workers

For each issue in order (respecting dependency graph):

1. **Check worker capacity.** Run `check-workers.sh` to count active workers. Default max: 3 concurrent workers (configurable via `AGENTSQUAD_MAX_WORKERS`).

2. **Wait for slot.** If at capacity, poll every 30 seconds until a worker finishes.

3. **Prepare task files.** Create `.tasks/<task-id>/` with:
   - `status.json` — initialized with issue metadata
   - `acceptance-criteria.md` — from issue body
   - `environment.md` — from issue labels or body (if present)

4. **Label in-progress:**
   ```bash
   gh issue edit <number> --add-label "squad:in-progress" --remove-label "squad:queued"
   ```

5. **Spawn worker:**
   ```bash
   bash scripts/agentsquad/spawn-worker.sh <task-id>
   ```

### Phase 3: Monitor and Complete

1. **Poll workers** every 60 seconds via `check-workers.sh`.

2. **When a worker finishes** (window no longer alive):
   - Read `status.json` for final status
   - If `ready-for-review`: label `squad:complete`, remove `squad:in-progress`
   - If `blocked`: label `squad:failed`, remove `squad:in-progress`, post blocked reason as issue comment
   - Check if any dependent issues are now unblocked

3. **Spawn next issue** if a slot opened and queued issues remain.

4. **Completion report.** When all issues are processed, summarize:
   - Completed: list with PR links
   - Failed: list with blocked reasons
   - Skipped: list with dependency issues

## Rules

- **Fresh Claude session per issue** — never reuse a worker window (prevents context rot)
- **Two-phase orchestration** — triage ALL issues before spawning ANY workers
- **Max 3 concurrent workers** unless overridden by `AGENTSQUAD_MAX_WORKERS`
- **Topological sort** for dependencies — cycle detection is mandatory
- **Label hygiene** — always update labels on state transitions

## Dependencies

Declare dependencies in issue body:
```
depends-on: #42
depends-on: #43
```

Issues with unresolved dependencies stay in `squad:queued` until their dependencies reach `squad:complete`.

$ARGUMENTS
