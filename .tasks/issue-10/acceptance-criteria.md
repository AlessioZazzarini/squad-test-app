## Description

Add CORS support and basic request logging to the Flask app.

**Complexity: simple**

## Requirements

1. **CORS middleware** — Allow all origins for development. Use `flask-cors` or manual headers.
2. **Request logging** — Log each request (method, path, status code, duration) to stdout.
3. **Tests** — Verify CORS headers present, verify logging doesn't break existing tests.

## Acceptance Criteria

- [ ] OPTIONS preflight requests return correct CORS headers
- [ ] Access-Control-Allow-Origin header present on all responses
- [ ] Request log line printed for each request (method, path, status, ms)
- [ ] All existing tests still pass
- [ ] New CORS tests pass
