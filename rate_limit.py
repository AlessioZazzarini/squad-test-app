"""In-memory sliding window rate limiter for Flask."""
import os
import time
from collections import defaultdict, deque

from flask import g, jsonify, request

RATE_LIMIT_REQUESTS = int(os.environ.get("RATE_LIMIT_REQUESTS", "60"))
RATE_LIMIT_WINDOW = int(os.environ.get("RATE_LIMIT_WINDOW", "60"))

# key -> deque of request timestamps
_hits: dict[str, deque] = defaultdict(deque)


def _client_key() -> str:
    """Return rate-limit key: per-user if authenticated, else per-IP."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header.split("Bearer ", 1)[1]
        try:
            from auth import verify_token
            payload = verify_token(token)
            return f"user:{payload['sub']}"
        except Exception:
            pass
    return f"ip:{request.remote_addr}"


def _cleanup(dq: deque, now: float, window: int) -> None:
    """Remove timestamps outside the current window."""
    cutoff = now - window
    while dq and dq[0] <= cutoff:
        dq.popleft()


def reset_hits():
    """Clear all rate limit state. Used in tests."""
    _hits.clear()


def init_rate_limiter(app):
    """Register before/after request hooks on the Flask app."""

    @app.before_request
    def check_rate_limit():
        key = _client_key()
        now = time.time()
        dq = _hits[key]
        _cleanup(dq, now, RATE_LIMIT_WINDOW)

        if len(dq) >= RATE_LIMIT_REQUESTS:
            retry_after = int(dq[0] + RATE_LIMIT_WINDOW - now) + 1
            response = jsonify({"error": "rate limit exceeded", "retry_after": retry_after})
            response.status_code = 429
            response.headers["X-RateLimit-Limit"] = str(RATE_LIMIT_REQUESTS)
            response.headers["X-RateLimit-Remaining"] = "0"
            response.headers["X-RateLimit-Reset"] = str(int(dq[0] + RATE_LIMIT_WINDOW))
            return response

        dq.append(now)
        g.rate_limit_remaining = RATE_LIMIT_REQUESTS - len(dq)
        g.rate_limit_reset = int(now + RATE_LIMIT_WINDOW)

    @app.after_request
    def add_rate_limit_headers(response):
        response.headers["X-RateLimit-Limit"] = str(RATE_LIMIT_REQUESTS)
        remaining = getattr(g, "rate_limit_remaining", None)
        if remaining is not None:
            response.headers["X-RateLimit-Remaining"] = str(remaining)
        reset = getattr(g, "rate_limit_reset", None)
        if reset is not None:
            response.headers["X-RateLimit-Reset"] = str(reset)
        return response
