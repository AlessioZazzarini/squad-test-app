## Description

Add rate limiting to prevent API abuse. Should work with the auth system.

**Complexity: medium**

depends-on: #8

## Requirements

1. **Rate limiter module** (`rate_limit.py`) — in-memory sliding window counter per IP (or per user if authenticated)
2. **Configurable thresholds** — via env vars: `RATE_LIMIT_REQUESTS=60`, `RATE_LIMIT_WINDOW=60` (requests per window in seconds)
3. **Response headers** — `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` on every response
4. **429 response** — when limit exceeded: `{"error": "rate limit exceeded", "retry_after": N}`
5. **Tests** — test rate limiting triggers, headers present, reset after window

## Acceptance Criteria

- [ ] Rate limit headers present on all responses
- [ ] Exceeding rate limit returns 429
- [ ] Rate limit resets after window expires
- [ ] Authenticated users tracked separately from anonymous
- [ ] RATE_LIMIT_REQUESTS and RATE_LIMIT_WINDOW env vars work
- [ ] All tests pass
