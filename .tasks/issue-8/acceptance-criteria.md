## Description

Implement JWT-based authentication. This is security-sensitive — use /collab for review.

**Complexity: high**

depends-on: #7

## Requirements

1. **Auth module** (`auth.py`) — JWT token creation and verification using PyJWT library
2. **Login endpoint** (`POST /auth/login`) — accepts `{"username": "admin", "password": "secret"}`, returns `{"token": "jwt..."}`
3. **Auth middleware** — decorator `@require_auth` that validates Bearer token from Authorization header
4. **Protected routes** — POST /items, DELETE /items/<id> require auth. GET endpoints stay public.
5. **Error responses** — 401 for missing/invalid token, 403 for expired token
6. **Tests** — test login, protected routes with/without token, expired token, malformed token
7. **IMPORTANT: Use /collab-review before marking ready-for-review** — this is security-sensitive code

## Acceptance Criteria

- [ ] POST /auth/login with valid credentials returns JWT token
- [ ] POST /auth/login with invalid credentials returns 401
- [ ] POST /items without token returns 401
- [ ] POST /items with valid token succeeds (201)
- [ ] DELETE /items/<id> without token returns 401
- [ ] GET /items works without token (public)
- [ ] Expired token returns 403
- [ ] All tests pass
- [ ] /collab-review was used before completion (check execution log)
