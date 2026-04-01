"""Tests for rate limiting middleware."""
import time
from unittest.mock import patch

import pytest

from app import app, items
from auth import create_token
from rate_limit import reset_hits, _hits, RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        items.clear()
        reset_hits()
        yield c


def _auth_header(username="admin"):
    token = create_token(username)
    return {"Authorization": f"Bearer {token}"}


# --- Headers present on all responses ---

def test_rate_limit_headers_on_get(client):
    resp = client.get("/health")
    assert "X-RateLimit-Limit" in resp.headers
    assert "X-RateLimit-Remaining" in resp.headers
    assert "X-RateLimit-Reset" in resp.headers


def test_rate_limit_headers_on_post(client):
    headers = _auth_header()
    resp = client.post("/items", json={"name": "test"}, headers=headers)
    assert "X-RateLimit-Limit" in resp.headers
    assert "X-RateLimit-Remaining" in resp.headers


def test_rate_limit_headers_values(client):
    resp = client.get("/health")
    assert resp.headers["X-RateLimit-Limit"] == str(RATE_LIMIT_REQUESTS)
    remaining = int(resp.headers["X-RateLimit-Remaining"])
    assert remaining == RATE_LIMIT_REQUESTS - 1


# --- Exceeding rate limit returns 429 ---

@patch("rate_limit.RATE_LIMIT_REQUESTS", 3)
def test_rate_limit_exceeded(client):
    reset_hits()
    for _ in range(3):
        resp = client.get("/health")
        assert resp.status_code == 200

    resp = client.get("/health")
    assert resp.status_code == 429
    data = resp.json
    assert data["error"] == "rate limit exceeded"
    assert "retry_after" in data
    assert resp.headers["X-RateLimit-Remaining"] == "0"


# --- Rate limit resets after window ---

@patch("rate_limit.RATE_LIMIT_REQUESTS", 2)
@patch("rate_limit.RATE_LIMIT_WINDOW", 1)
def test_rate_limit_resets_after_window(client):
    reset_hits()
    for _ in range(2):
        client.get("/health")

    resp = client.get("/health")
    assert resp.status_code == 429

    time.sleep(1.1)

    resp = client.get("/health")
    assert resp.status_code == 200


# --- Authenticated users tracked separately ---

@patch("rate_limit.RATE_LIMIT_REQUESTS", 2)
def test_authenticated_tracked_separately(client):
    reset_hits()
    # Exhaust anonymous limit
    for _ in range(2):
        client.get("/health")
    resp = client.get("/health")
    assert resp.status_code == 429

    # Authenticated user should still work
    headers = _auth_header("admin")
    resp = client.get("/health", headers=headers)
    assert resp.status_code == 200


# --- Env var config ---

def test_env_var_defaults():
    assert RATE_LIMIT_REQUESTS == 60
    assert RATE_LIMIT_WINDOW == 60


@patch.dict("os.environ", {"RATE_LIMIT_REQUESTS": "100", "RATE_LIMIT_WINDOW": "30"})
def test_env_var_override():
    import importlib
    import rate_limit
    importlib.reload(rate_limit)
    assert rate_limit.RATE_LIMIT_REQUESTS == 100
    assert rate_limit.RATE_LIMIT_WINDOW == 30
    # Reload back to defaults
    import os
    os.environ.pop("RATE_LIMIT_REQUESTS", None)
    os.environ.pop("RATE_LIMIT_WINDOW", None)
    importlib.reload(rate_limit)
