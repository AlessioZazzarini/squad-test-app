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

### Phase 2: Generate Manifest

Generate `.tasks/orchestration-manifest.json` with the triaged issues, their dependencies, priorities, and initial status of `queued`.

### Phase 3: Run Parallel Orchestration

Delegate all spawning, worktree isolation, push, and PR creation to the canonical orchestration script:

```bash
bash scripts/agentsquad/orchestrate-parallel.sh <max_iterations>
```

This script handles:
- Git worktree isolation per worker (no shared working directories)
- Wave-based parallel execution respecting dependency order
- Commit, push, and PR creation for each completed task
- Label updates (`squad:in-progress`, `squad:complete`, `squad:failed`)
- Crash recovery and resume from manifest state

**Do NOT reimplement spawning, worktree, push, or PR logic here.** The parallel script is the single canonical path.

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
