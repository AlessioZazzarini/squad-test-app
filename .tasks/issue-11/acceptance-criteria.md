## Description

Add simple API key authentication to protect write endpoints. This is security-sensitive — use /collab-review.

**Complexity: high**

depends-on: #10

## Requirements

1. **API key validation** — Check X-API-Key header against configured key (env var API_SECRET_KEY)
2. **Protected routes** — POST /items and DELETE /items/<id> require valid API key
3. **Public routes** — GET endpoints stay public (no auth needed)
4. **Error responses** — 401 for missing key, 403 for invalid key
5. **Tests** — Test with/without key, invalid key, protected vs public routes
6. **IMPORTANT: Use /collab-review before completing** — this is security code

## Acceptance Criteria

- [ ] POST /items without X-API-Key returns 401
- [ ] POST /items with wrong key returns 403
- [ ] POST /items with correct key succeeds (201)
- [ ] GET /items works without any key
- [ ] DELETE /items/<id> without key returns 401
- [ ] All tests pass
- [ ] /collab-review was used (check execution log)
