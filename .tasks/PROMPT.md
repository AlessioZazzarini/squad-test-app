# AgentSquad Loop Iteration - Issue #1: App skeleton: repository interface + in-memory CRUD + tests

You are working on a Python Flask REST API project.

## Your Mission

Implement the feature described in GitHub Issue #1.

## Context Files (Read These First)

1. **@.tasks/plan.md** - JSON task list with your current tasks. Find ONE task where `passes: false` and work on it.
2. **@.tasks/activity.md** - Session log of previous iterations. Record what you accomplish.

## Issue Context

### Description

Create the core application structure with a clean repository pattern:

1. **Repository interface** (`repository.py`) — abstract base class with `add()`, `get()`, `list_all()`, `delete()` methods
2. **In-memory implementation** (`memory_repo.py`) — dict-based storage for development/testing
3. **Flask CRUD endpoints** — update `app.py` with full `/items` CRUD using the repository
4. **Tests** — pytest tests for all 4 CRUD operations

### Acceptance Criteria

- `GET /items` returns empty list initially
- `POST /items` with `{"name": "test", "description": "desc"}` creates an item with auto-generated ID
- `GET /items/<id>` returns the created item
- `DELETE /items/<id>` removes the item, returns 204
- `GET /items/<id>` on deleted item returns 404
- `pytest` passes with all tests green
- Repository interface is abstract (ABC) so other implementations can plug in

### Tech Stack

Python 3, Flask, pytest.

## Rules for This Iteration

1. **Read .tasks/plan.md first** - Understand all tasks and their status
2. **Pick ONE task** where `passes: false` (prefer tasks with satisfied dependencies)
3. **Agent Routing (CRITICAL)** - You MUST route the work to the appropriate specialist agent(s):
   - `architect`: For architecture decisions, data flow, domain-specific logic (e.g., repository interface design)
   - `systems`: For API routes, Flask endpoints, backend integration
   - `qa`: For writing tests (unit, integration)
   *If the task touches 1 domain, use a single subagent. If it crosses 2+ domains, spawn an Agent Team with a Lead and `qa`.*
4. **Implement the task completely** - Don't do partial work
5. **Update .tasks/plan.md** - Set `passes: true` for the completed task
6. **Log to .tasks/activity.md** - Record what you did and any issues
7. **Run verification** - Build and tests must pass
8. **When ALL tasks pass** - Output `<promise>COMPLETE</promise>` to signal done

## Tech Stack Commands

```bash
pytest              # Run tests
python -c 'from app import app'  # Verify app imports
python -m py_compile repository.py  # Check syntax
```

## Quality Gates

### Systems Agent Guardrails (for API endpoint tasks)
- [ ] Are Flask routes returning proper HTTP status codes (201, 204, 404)?
- [ ] Is JSON request parsing handled safely (request.get_json)?
- [ ] Does the health check still work after changes?

### QA Agent Guardrails (for testing tasks)
- [ ] No real API calls in tests — use Flask test client only
- [ ] All three states tested: empty state, data-present state, error/404 state
- [ ] Context protection: pipe test output through head/tail, do not flood stdout
- [ ] Tests use pytest fixtures for the Flask test client

### Architect Agent Guardrails (for interface design tasks)
- [ ] Is the repository interface abstract (ABC) and cannot be instantiated?
- [ ] Is domain logic (repository) separated from infrastructure (Flask routes)?
- [ ] Are method signatures clear and consistent?

## Begin

1. Read @.tasks/plan.md
2. Read @.tasks/activity.md for context
3. Find a task to work on
4. Implement it
5. Update plan.md and activity.md
6. Verify with build/tests

When all tasks in plan.md have `passes: true`, output:

```
<promise>COMPLETE</promise>
```
