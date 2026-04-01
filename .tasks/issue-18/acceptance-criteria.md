## Description

Add the ability to update an existing item (currently only create/delete exist). This requires reading and understanding ALL existing endpoints to ensure consistency.

**Complexity: medium**

## Requirements

1. **PUT /items/<id>** — update an existing item's name, description, and tags
2. **Partial updates** — only update fields that are provided (don't require all fields)
3. **Same validation as POST** — name max 200 chars, description max 1000 chars, tags list of strings
4. **Auth required** — must have valid API key (same as POST and DELETE)
5. **Tests** — test full update, partial update (name only, tags only), validation errors, 404 on missing item, auth required
6. **IMPORTANT: While implementing, review all existing endpoints for consistency issues.** If you find any bugs, missing validation, or inconsistencies — file them as follow-up issues using `gh-create-followup.sh`. Do NOT fix them inline.

## Acceptance Criteria

- [ ] PUT /items/<id> with all fields updates the item
- [ ] PUT /items/<id> with only name updates just the name
- [ ] PUT /items/<id> with only tags updates just the tags
- [ ] PUT /items/<id> with invalid name returns 400
- [ ] PUT /items/<id> without auth returns 401
- [ ] PUT /items/999 returns 404
- [ ] All existing tests still pass
- [ ] New tests for update endpoint pass
- [ ] GitHub issue has progress comments (investigating, implementing, tests passing)
- [ ] Any discovered issues filed as follow-ups (check issue comments)

## Hints for Code Review

While reading the codebase, pay attention to:
- Is the list endpoint returning a proper envelope with total count?
- Are all write endpoints consistently validated?
- Is there a PUT for the item itself (not just tags)?
- Are error responses consistent across endpoints?
