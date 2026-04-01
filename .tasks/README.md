# .tasks/ -- Autonomous Task Pipeline

This directory is the shared blackboard for AgentSquad's autonomous development system. Each subdirectory represents a single task with its status, acceptance criteria, execution logs, and artifacts. Agents communicate exclusively through files in this directory -- no APIs, no IPC, no databases. Status updates are written only via structured JSON to prevent malformed state.

## Directory Structure

```
.tasks/
  _queue.md                       # Priority-ordered task queue
  _interfaces/                    # Shared interface definitions (optional)
  _completed/                     # Archived completed tasks
  archive/                        # Archived session files (per issue)
    issue-42/
      plan.md
      activity.md
      PROMPT.md
      loop.sh
  <task-slug>/                    # Active task directory
    status.json                   # Machine-readable status
    brief.md                      # Human-readable task description
    activity.md                   # Execution log
    acceptance.md                 # Acceptance criteria checklist
```

## Task Lifecycle

```
created -> ready -> in_progress -> verifying -> complete
                        |              |
                        v              v
                     blocked        failed
```

| Status | Meaning |
|--------|---------|
| `created` | Task exists but is not ready for work |
| `ready` | All prerequisites met, can be picked up |
| `in_progress` | An agent is actively working on this |
| `blocked` | Waiting on a dependency or external input |
| `verifying` | Implementation done, running verification |
| `complete` | All acceptance criteria met, tests pass |
| `failed` | Verification failed or task abandoned |

## status.json Schema

```json
{
  "id": "task-slug",
  "kind": "bug | feature | chore | research",
  "title": "Human-readable title",
  "status": "created | ready | in_progress | blocked | verifying | complete | failed",
  "priority": 1,
  "github_issue": 42,
  "created_at": "2025-01-23T10:00:00Z",
  "updated_at": "2025-01-23T12:30:00Z",
  "assigned_agent": "systems | product | qa | architect | null",
  "depends_on": [],
  "blocked_by": null,
  "error": null,
  "iterations": 0
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | URL-safe slug matching directory name |
| `kind` | enum | `bug` (fix), `feature` (new), `chore` (maintenance), `research` (investigation) |
| `title` | string | Short human-readable description |
| `status` | enum | Current lifecycle status |
| `priority` | number | Lower = higher priority (1 is highest) |
| `github_issue` | number/null | Linked GitHub issue number |
| `created_at` | ISO 8601 | When the task was created |
| `updated_at` | ISO 8601 | Last status change |
| `assigned_agent` | string/null | Which agent archetype is working on this |
| `depends_on` | string[] | Array of task IDs that must complete first |
| `blocked_by` | string/null | What is blocking this task (human-readable) |
| `error` | string/null | Error message if failed |
| `iterations` | number | How many loop iterations have been spent |

## Rules

1. **One task at a time**: Only one task should be `in_progress` per agent
2. **Status updates are atomic**: Read -> modify -> write the entire status.json
3. **Activity logs are append-only**: Never delete entries from activity.md
4. **Acceptance criteria are immutable**: Once set, they don't change (add new ones if scope changes)
5. **Archive, don't delete**: Completed tasks move to `_completed/`, never deleted

## Queue Management

The `_queue.md` file is the human-readable priority list. It is updated by the orchestrator and should reflect the current state of all active tasks. Tasks are ordered by priority (lower number = higher priority).

## Integration with GitHub

- Each task can link to a GitHub issue via `github_issue` in status.json
- The `/taskify` command creates task files from GitHub issues
- The `/cleanup` command archives tasks and updates GitHub issues
- The `/orchestrate` command processes multiple issues through the pipeline
