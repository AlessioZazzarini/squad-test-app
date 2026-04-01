# Task Plan - Issue #3: Search and filter endpoint with pagination

This file tracks implementation tasks for GitHub Issue #3.

**Source:** https://github.com/AlessioZazzarini/squad-test-app/issues/3
**Generated:** 2026-04-01
**Estimated Total Complexity:** 1 small, 3 medium

## Tasks

```json
[
  {
    "id": 1,
    "category": "feature",
    "epic": "Search and filter endpoint with pagination",
    "description": "Add search/filter/paginate method to repository interface and implement in MemoryRepository",
    "steps": [
      "Step 1: Add abstract method search(query, limit, offset) -> tuple[list, int] to ItemRepository in repository.py",
      "Step 2: Implement search() in MemoryRepository — case-insensitive substring match on name and description fields",
      "Step 3: Apply limit/offset pagination after filtering, return (paginated_items, total_matching_count)",
      "Step 4: Verify with python -c 'from memory_repo import MemoryRepository; r = MemoryRepository(); print(r.search(\"\", 20, 0))'"
    ],
    "acceptance_criteria": [
      "AC 1: ItemRepository ABC has search(query, limit, offset) abstract method",
      "AC 2: MemoryRepository.search returns matching items filtered case-insensitively on name/description",
      "AC 3: Pagination via limit/offset works correctly and total reflects unfiltered match count",
      "AC 4: Empty query string returns all items"
    ],
    "depends_on": [],
    "passes": true,
    "github_issue": 3,
    "estimated_complexity": "medium"
  },
  {
    "id": 2,
    "category": "feature",
    "epic": "Search and filter endpoint with pagination",
    "description": "Update GET /items endpoint with q/limit/offset query params, validation, and response envelope",
    "steps": [
      "Step 1: Parse q, limit, offset query parameters from request.args in the list_items route",
      "Step 2: Validate limit and offset are non-negative integers; return 400 JSON error if invalid",
      "Step 3: Set defaults: limit=20, offset=0, q='' (empty string means no filter)",
      "Step 4: Call repo.search(q, limit, offset) and return response envelope {items, total, limit, offset}",
      "Step 5: Verify endpoint works with curl or python -c test"
    ],
    "acceptance_criteria": [
      "AC 1: GET /items returns {items: [], total: 0, limit: 20, offset: 0} when empty",
      "AC 2: GET /items?q=test filters items by name/description match",
      "AC 3: GET /items?limit=2&offset=0 paginates correctly",
      "AC 4: Invalid limit/offset (negative, non-integer) returns 400 with error message",
      "AC 5: App starts without errors"
    ],
    "depends_on": [1],
    "passes": true,
    "github_issue": 3,
    "estimated_complexity": "medium"
  },
  {
    "id": 3,
    "category": "testing",
    "epic": "Search and filter endpoint with pagination",
    "description": "Write comprehensive pytest tests for search, pagination, edge cases, and invalid parameters",
    "steps": [
      "Step 1: Update test_app.py with tests for the new response envelope format on GET /items",
      "Step 2: Add tests for search — q param matching name, description, case-insensitive",
      "Step 3: Add tests for pagination — limit/offset with multiple items",
      "Step 4: Add tests for edge cases — empty results, no q param returns all, offset beyond total",
      "Step 5: Add tests for invalid params — non-integer limit, negative offset → 400",
      "Step 6: Run pytest and verify all tests pass"
    ],
    "acceptance_criteria": [
      "AC 1: Search filtering tested for name match, description match, and case insensitivity",
      "AC 2: Pagination tested with limit=2 offset=0 and limit=2 offset=2",
      "AC 3: Total count is correct regardless of pagination",
      "AC 4: 400 errors tested for invalid limit/offset values",
      "AC 5: pytest runs with all tests green (exit code 0)"
    ],
    "depends_on": [2],
    "passes": true,
    "github_issue": 3,
    "estimated_complexity": "medium"
  },
  {
    "id": 4,
    "category": "polish",
    "epic": "Search and filter endpoint with pagination",
    "description": "Verify all 7 acceptance criteria from the GitHub issue pass end-to-end",
    "steps": [
      "Step 1: Run full pytest suite and confirm all tests pass",
      "Step 2: Walk through each acceptance criterion from issue #3 manually",
      "Step 3: Ensure existing CRUD tests still pass (no regressions)",
      "Step 4: Ensure no import errors or lint issues"
    ],
    "acceptance_criteria": [
      "AC 1: All 7 acceptance criteria from GitHub issue #3 are satisfied",
      "AC 2: pytest passes with zero failures",
      "AC 3: Existing CRUD tests are not broken"
    ],
    "depends_on": [3],
    "passes": true,
    "github_issue": 3,
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
