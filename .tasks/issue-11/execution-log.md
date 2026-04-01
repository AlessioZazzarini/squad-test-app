# Execution Log: issue-11 — API Key Authentication

## Investigation
- **Started:** 2026-04-01
- App already has JWT auth via `@require_auth` decorator in `auth.py`
- POST /items and DELETE /items/<id> are protected with JWT
- GET endpoints are public
- Need to add X-API-Key header support as additional auth method

### Hypothesis
- **H1 (confidence: 95%):** Modify `require_auth` to accept either JWT Bearer token OR X-API-Key header. API key checked against `API_SECRET_KEY` env var. Return 401 if no auth provided, 403 if invalid API key.

## Implementation Plan
1. Add API key validation to `auth.py` — read `API_SECRET_KEY` from env, update `require_auth` to accept both methods
2. Add tests for API key auth in `test_api_key.py`
3. Run tests
4. Use /collab-review
