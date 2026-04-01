# /orchestrate — Triage GitHub Issues into the Task Queue

Fetch GitHub issues, parse dependencies, create task directories, then hand off to the Conductor for execution.

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

4. **Create task directories.** For each issue, create `.tasks/<task-id>/` with `status.json` (status: ready) and `acceptance-criteria.md`.

5. **Label queued issues:**
   ```bash
   gh issue edit <number> --add-label "squad:queued" --remove-label "squad:ready"
   ```

### Phase 2: Hand Off to Conductor

Delegate all execution to the Conductor:

```bash
bash scripts/agentsquad/conductor.sh --once
```

The Conductor handles:
- Git worktree isolation per worker
- Spawning workers up to MAX_WORKERS
- Push and PR creation for completed tasks
- Approval policy (manual/auto/paused)
- Merge of approved tasks
- Health monitoring (warn/kill stuck workers)
- Cycle summary notifications

**Do NOT reimplement spawning, worktree, push, or PR logic here.** The Conductor is the single canonical execution engine.

For continuous operation:
```bash
bash scripts/agentsquad/conductor.sh --loop 3m
```

## Rules

- **Fresh Claude session per issue** — never reuse a worker window (prevents context rot)
- **Two-phase workflow** — triage ALL issues before handing off to the Conductor
- **Max 3 concurrent workers** unless overridden by `AGENTSQUAD_MAX_WORKERS`
- **Topological sort** for dependencies — cycle detection is mandatory
- **Label hygiene** — always update labels on state transitions

## Dependencies

Declare dependencies in issue body:
```
depends-on: #42
depends-on: #43
```

Issues with unresolved dependencies stay in `squad:queued` until their dependencies reach a completed status.

$ARGUMENTS
