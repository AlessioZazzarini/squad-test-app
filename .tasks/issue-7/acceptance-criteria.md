## Description

Add comprehensive input validation and proper error handling across all API endpoints.

**Complexity: medium**

## Requirements

1. **POST /items validation** — name is required (non-empty string, max 200 chars), description is optional (max 1000 chars). Return 400 with clear error message on invalid input.
2. **Query param validation** — GET /items: limit must be 1-100 (default 20), offset must be >= 0. Return 400 on invalid values.
3. **Global error handler** — catch unhandled exceptions, return JSON `{"error": "internal server error"}` with 500, log the traceback.
4. **Tests** — test every validation rule (valid input, missing field, too long, wrong type, boundary values).

## Acceptance Criteria

- [ ] POST /items with empty name returns 400 with `{"error": "name is required"}`
- [ ] POST /items with name > 200 chars returns 400
- [ ] GET /items?limit=0 returns 400
- [ ] GET /items?limit=101 returns 400
- [ ] GET /items?offset=-1 returns 400
- [ ] Unhandled exceptions return 500 JSON (not HTML)
- [ ] All new validation tests pass
- [ ] Existing tests still pass
