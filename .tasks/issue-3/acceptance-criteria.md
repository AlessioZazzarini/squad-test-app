# Issue #3: Search and filter endpoint with pagination

## Description

Add search, filtering, and pagination to the items API:

1. **Query parameters** — `GET /items?q=search_term&limit=10&offset=0`
2. **Search** — filter items where name or description contains the search term (case-insensitive)
3. **Pagination** — `limit` and `offset` query params with sensible defaults (limit=20, offset=0)
4. **Response envelope** — `{"items": [...], "total": N, "limit": 20, "offset": 0}`
5. **Tests** — pytest tests for search, pagination, edge cases (empty results, invalid params)

depends-on: #1

## Acceptance Criteria

- [ ] `GET /items?q=test` returns only items matching "test" in name or description
- [ ] `GET /items?limit=2&offset=0` returns first 2 items
- [ ] `GET /items?limit=2&offset=2` returns next 2 items
- [ ] Response includes `total` count (unaffected by pagination)
- [ ] Empty search returns all items (with pagination)
- [ ] Invalid limit/offset values return 400 with error message
- [ ] `pytest` passes with all tests green
