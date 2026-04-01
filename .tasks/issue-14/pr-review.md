# PR Review: issue-14

## What was done
Enhanced the /health endpoint to return system information including version (read from a VERSION file), uptime in seconds (computed from app start time), and total items count. Added comprehensive tests verifying all new fields.

## Files changed
- `VERSION` — new file, contains "1.0.0"
- `app.py` — added APP_START_TIME and APP_VERSION at startup, enhanced /health response
- `test_app.py` — added 3 new tests for health endpoint fields (updated existing test_health, added test_health_uptime_increases and test_health_items_count)

## How to verify
1. Run `python3 -m pytest -v` — all 61 tests should pass
2. Start the app and `curl http://localhost:5000/health` — response should include status, version, uptime_seconds, items_count
3. Create some items and verify items_count increases
4. Wait a few seconds between /health calls and verify uptime_seconds increases

## Test results
- Build: pass
- Tests: 61 passed, 0 failed
- Lint: pass
