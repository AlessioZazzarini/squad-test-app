# PR Review: issue-11

## What was done
Added API key authentication via `X-API-Key` header as an alternative to JWT Bearer tokens for write endpoints. The `require_auth` decorator now checks API key first, then falls back to JWT. Also fixed 2 pre-existing broken tests that were missing auth headers.

## Files changed
- `auth.py` — Added `_check_api_key()` and `_check_jwt()` helpers, refactored `require_auth` to support both auth methods, API key read from `API_SECRET_KEY` env var
- `test_api_key.py` — New test file with 9 tests covering API key auth scenarios
- `test_app.py` — Fixed 2 pre-existing tests (`test_list_items_with_data`, `test_list_items_limit_offset`) to include auth headers

## How to verify
1. Set `API_SECRET_KEY` env var
2. Run `python3 -m pytest -v` — all 59 tests should pass
3. Test manually: `curl -H "X-API-Key: $API_SECRET_KEY" -X POST -H "Content-Type: application/json" -d '{"name":"test"}' http://localhost:5000/items`

## Test results
- Build: pass
- Tests: 59 passed, 0 failed
- Lint: pass
