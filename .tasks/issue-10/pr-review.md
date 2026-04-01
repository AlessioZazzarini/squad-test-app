# PR Review: issue-10

## What was done
Added CORS support using flask-cors (all origins allowed for development) and request logging that prints method, path, status code, and duration for each request to stdout.

## Files changed
- `app.py` — Added CORS initialization, before_request timer, after_request logger
- `requirements.txt` — Added flask-cors>=4.0
- `test_app.py` — Added 3 new tests: CORS headers, preflight OPTIONS, request logging

## How to verify
1. Run `python3 -m pytest -v` — all new tests should pass (2 pre-existing failures on main unrelated to this change)
2. Start app with `python3 app.py` and verify:
   - `curl -i -X OPTIONS http://localhost:5000/items -H "Origin: http://example.com" -H "Access-Control-Request-Method: POST"` returns CORS headers
   - `curl -i http://localhost:5000/health -H "Origin: http://example.com"` includes `Access-Control-Allow-Origin` header
   - Each request prints a log line to stdout

## Test results
- Build: pass
- Tests: 48 passed, 2 failed (pre-existing on main — unrelated auth-missing tests)
- Lint: pass
