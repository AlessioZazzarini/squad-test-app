# Task Plan - Issue #1: App skeleton: repository interface + in-memory CRUD + tests

This file tracks implementation tasks for GitHub Issue #1.

**Source:** https://github.com/AlessioZazzarini/squad-test-app/issues/1
**Generated:** 2026-04-01
**Estimated Total Complexity:** 2 small, 2 medium, 1 large

## Tasks

```json
[
  {
    "id": 1,
    "category": "setup",
    "epic": "App skeleton: repository interface + in-memory CRUD + tests",
    "description": "Create abstract repository interface with add, get, list_all, and delete methods using Python ABC",
    "steps": [
      "Step 1: Create repository.py in the project root",
      "Step 2: Define ItemRepository as an abstract base class (ABC)",
      "Step 3: Add abstract methods: add(item) -> dict, get(item_id) -> dict, list_all() -> list, delete(item_id) -> bool",
      "Step 4: Verify the module imports cleanly with python -c 'import repository'"
    ],
    "acceptance_criteria": [
      "AC 1: repository.py exists with ItemRepository ABC class",
      "AC 2: All four abstract methods are defined with proper signatures",
      "AC 3: ItemRepository cannot be instantiated directly (raises TypeError)"
    ],
    "depends_on": [],
    "passes": true,
    "github_issue": 1,
    "estimated_complexity": "small"
  },
  {
    "id": 2,
    "category": "feature",
    "epic": "App skeleton: repository interface + in-memory CRUD + tests",
    "description": "Create in-memory repository implementation using a dict for storage that implements the ItemRepository interface",
    "steps": [
      "Step 1: Create memory_repo.py in the project root",
      "Step 2: Implement MemoryRepository class extending ItemRepository",
      "Step 3: Use a dict as internal storage with UUID-based auto-generated IDs",
      "Step 4: Implement add() to store item and return it with generated ID",
      "Step 5: Implement get(), list_all(), delete() methods",
      "Step 6: Verify with python -c 'from memory_repo import MemoryRepository; r = MemoryRepository(); print(r.list_all())'"
    ],
    "acceptance_criteria": [
      "AC 1: MemoryRepository implements all ItemRepository abstract methods",
      "AC 2: add() generates a unique ID and returns the full item dict",
      "AC 3: get() returns None or raises for missing IDs",
      "AC 4: delete() returns True for existing items, False for missing"
    ],
    "depends_on": [1],
    "passes": true,
    "github_issue": 1,
    "estimated_complexity": "small"
  },
  {
    "id": 3,
    "category": "feature",
    "epic": "App skeleton: repository interface + in-memory CRUD + tests",
    "description": "Add full CRUD endpoints to app.py under /items using the in-memory repository",
    "steps": [
      "Step 1: Import MemoryRepository and Flask helpers (request, jsonify) in app.py",
      "Step 2: Instantiate a module-level MemoryRepository as the app's data store",
      "Step 3: Add GET /items endpoint returning JSON list of all items",
      "Step 4: Add POST /items endpoint accepting JSON body, returning created item with 201",
      "Step 5: Add GET /items/<id> endpoint returning single item or 404",
      "Step 6: Add DELETE /items/<id> endpoint returning 204 on success or 404"
    ],
    "acceptance_criteria": [
      "AC 1: GET /items returns [] initially",
      "AC 2: POST /items with {name, description} returns created item with ID and 201 status",
      "AC 3: GET /items/<id> returns the item or 404",
      "AC 4: DELETE /items/<id> returns 204 or 404",
      "AC 5: App starts without errors (python -c 'from app import app')"
    ],
    "depends_on": [2],
    "passes": true,
    "github_issue": 1,
    "estimated_complexity": "medium"
  },
  {
    "id": 4,
    "category": "testing",
    "epic": "App skeleton: repository interface + in-memory CRUD + tests",
    "description": "Write comprehensive pytest tests covering all CRUD operations and edge cases",
    "steps": [
      "Step 1: Update test_app.py with imports and fixtures for the CRUD endpoints",
      "Step 2: Write test for GET /items returning empty list",
      "Step 3: Write test for POST /items creating an item successfully",
      "Step 4: Write test for GET /items/<id> retrieving a created item",
      "Step 5: Write test for DELETE /items/<id> removing an item and returning 204",
      "Step 6: Write test for GET /items/<id> returning 404 after deletion",
      "Step 7: Run pytest and verify all tests pass"
    ],
    "acceptance_criteria": [
      "AC 1: All CRUD operations have at least one test each",
      "AC 2: 404 cases are tested for both GET and DELETE",
      "AC 3: pytest runs with all tests green (exit code 0)"
    ],
    "depends_on": [3],
    "passes": true,
    "github_issue": 1,
    "estimated_complexity": "medium"
  },
  {
    "id": 5,
    "category": "polish",
    "epic": "App skeleton: repository interface + in-memory CRUD + tests",
    "description": "Verify all acceptance criteria from the issue pass end-to-end and ensure clean code",
    "steps": [
      "Step 1: Run full pytest suite and confirm all tests pass",
      "Step 2: Verify repository interface is abstract (cannot instantiate directly)",
      "Step 3: Walk through each acceptance criterion from the issue manually",
      "Step 4: Ensure no lint issues or import errors"
    ],
    "acceptance_criteria": [
      "AC 1: All 7 acceptance criteria from the GitHub issue are satisfied",
      "AC 2: pytest passes with zero failures",
      "AC 3: All files import cleanly without errors"
    ],
    "depends_on": [4],
    "passes": true,
    "github_issue": 1,
    "estimated_complexity": "small"
  }
]
```

## Agent Instructions

When working on this plan:

1. **Read this file first** to understand all tasks
2. **Pick ONE task** where `passes: false` and all `depends_on` tasks have `passes: true`
3. **Implement completely** - no partial work
4. **Update this file** - set `passes: true` when done
5. **Log to activity.md** - record what you did
6. **Verify** - build and tests must pass
7. **Signal completion** - when ALL tasks pass, output `<promise>COMPLETE</promise>`

## Notes

- Tasks should be completed respecting `depends_on` order
- Set `passes: true` only when task is fully verified
- If stuck on a task for >2 iterations, add a note to activity.md
