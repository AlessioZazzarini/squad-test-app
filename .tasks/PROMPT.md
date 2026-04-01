# AgentSquad Loop Iteration - Issue #3: Search and filter endpoint with pagination

You are working on this project's codebase.

## Your Mission

Implement the feature described in GitHub Issue #3.

## Context Files (Read These First)

1. **@.tasks/plan.md** - JSON task list with your current tasks. Find ONE task where `passes: false` and work on it.
2. **@.tasks/activity.md** - Session log of previous iterations. Record what you accomplish.
3. **@.claude/CLAUDE.md** - Codebase guidelines and standards (if exists)

## Issue Context

### Description

Add search, filtering, and pagination to the items API:

1. **Query parameters** — `GET /items?q=search_term&limit=10&offset=0`
2. **Search** — filter items where name or description contains the search term (case-insensitive)
3. **Pagination** — `limit` and `offset` query params with sensible defaults (limit=20, offset=0)
4. **Response envelope** — `{"items": [...], "total": N, "limit": 20, "offset": 0}`
5. **Tests** — pytest tests for search, pagination, edge cases (empty results, invalid params)

### Acceptance Criteria

- [ ] `GET /items?q=test` returns only items matching "test" in name or description
- [ ] `GET /items?limit=2&offset=0` returns first 2 items
- [ ] `GET /items?limit=2&offset=2` returns next 2 items
- [ ] Response includes `total` count (unaffected by pagination)
- [ ] Empty search returns all items (with pagination)
- [ ] Invalid limit/offset values return 400 with error message
- [ ] `pytest` passes with all tests green

### Existing Codebase

- **repository.py** — `ItemRepository` ABC with `add`, `get`, `list_all`, `delete`
- **memory_repo.py** — `MemoryRepository` with dict storage and UUID keys
- **app.py** — Flask CRUD endpoints under `/items` (GET, POST, GET/<id>, DELETE/<id>)
- **test_app.py** — 9 existing tests (health, CRUD ops, 404 cases, ABC check)
- Uses Python typing.Optional for 3.9 compatibility

## Rules for This Iteration

1. **Read .tasks/plan.md first** - Understand all tasks and their status
2. **Pick ONE task** where `passes: false` (prefer tasks with satisfied dependencies)
3. **Agent Routing (CRITICAL)** - You MUST route the work to the appropriate specialist agent(s):
   - `architect`: For architecture decisions, data flow, domain-specific logic
   - `product`: For UI components, pages, forms, accessibility
   - `systems`: For APIs, background jobs, database, external integrations
   - `qa`: For writing tests (unit, E2E, integration)
   *If the task touches 1 domain, use a single subagent. If it crosses 2+ domains, spawn an Agent Team with a Lead and `qa`.*
4. **Implement the task completely** - Don't do partial work
5. **Update .tasks/plan.md** - Set `passes: true` for the completed task
6. **Log to .tasks/activity.md** - Record what you did and any issues
7. **Run verification** - Build and tests must pass
8. **When ALL tasks pass** - Output `<promise>COMPLETE</promise>` to signal done

## Tech Stack Commands

```bash
python -c "from app import app"   # Verify changes compile
pytest                             # Run tests
```

## Quality Gates

### Systems Agent Guardrails (API routes)
- [ ] Query parameter validation returns proper 400 errors with JSON body
- [ ] No breaking changes to existing endpoints (GET/POST/DELETE /items still work)
- [ ] Health check still returns 200

### QA Agent Guardrails (tests)
- [ ] No real API calls in tests — use Flask test client
- [ ] All three states tested: happy path, empty state, error state
- [ ] Context protection: pipe test output through head/tail to avoid flooding context
- [ ] Existing 9 tests must continue to pass (no regressions)

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
