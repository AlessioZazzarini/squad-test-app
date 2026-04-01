## Description

Add tagging support to items — each item can have multiple tags.

**Complexity: medium**

depends-on: #14

## Requirements

1. **Tag model** — tags are strings, stored as a list on each item
2. **POST /items** — accept optional `tags` field: `{"name": "test", "tags": ["python", "api"]}`
3. **GET /items/<id>** — include tags in response
4. **GET /items?tag=python** — filter items by tag
5. **PUT /items/<id>/tags** — replace tags: `{"tags": ["new-tag"]}`
6. **Tests** — create with tags, filter by tag, update tags, empty tags

## Acceptance Criteria

- [ ] POST /items with tags creates item with tags
- [ ] GET /items/<id> includes tags array
- [ ] GET /items?tag=python returns only items with that tag
- [ ] PUT /items/<id>/tags replaces the tag list
- [ ] Items without tags have empty array
- [ ] All tests pass
