"""Tests for API key authentication."""
import pytest

from app import app, items


TEST_API_KEY = "test-secret-api-key-12345"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("API_SECRET_KEY", TEST_API_KEY)
    # Reload the API_SECRET_KEY in auth module
    import auth
    monkeypatch.setattr(auth, "API_SECRET_KEY", TEST_API_KEY)

    app.config["TESTING"] = True
    with app.test_client() as c:
        items.clear()
        yield c


@pytest.fixture(autouse=True)
def reset_items():
    import app as app_module
    app_module.items.clear()
    app_module.next_id = 1


# --- POST /items with API key ---

def test_post_items_without_api_key(client):
    """POST /items without X-API-Key returns 401."""
    resp = client.post("/items", json={"name": "test"})
    assert resp.status_code == 401


def test_post_items_with_wrong_key(client):
    """POST /items with wrong key returns 403."""
    resp = client.post("/items", json={"name": "test"},
                       headers={"X-API-Key": "wrong-key"})
    assert resp.status_code == 403
    assert resp.get_json()["error"] == "invalid API key"


def test_post_items_with_correct_key(client):
    """POST /items with correct key succeeds (201)."""
    resp = client.post("/items", json={"name": "test item"},
                       headers={"X-API-Key": TEST_API_KEY})
    assert resp.status_code == 201
    assert resp.get_json()["name"] == "test item"


# --- GET /items stays public ---

def test_get_items_without_key(client):
    """GET /items works without any key."""
    resp = client.get("/items")
    assert resp.status_code == 200


def test_get_item_without_key(client):
    """GET /items/<id> works without any key."""
    # Create an item first
    client.post("/items", json={"name": "public item"},
                headers={"X-API-Key": TEST_API_KEY})
    resp = client.get("/items/1")
    assert resp.status_code == 200
    assert resp.get_json()["name"] == "public item"


# --- DELETE /items/<id> with API key ---

def test_delete_items_without_key(client):
    """DELETE /items/<id> without key returns 401."""
    client.post("/items", json={"name": "to delete"},
                headers={"X-API-Key": TEST_API_KEY})
    resp = client.delete("/items/1")
    assert resp.status_code == 401


def test_delete_items_with_wrong_key(client):
    """DELETE /items/<id> with wrong key returns 403."""
    client.post("/items", json={"name": "to delete"},
                headers={"X-API-Key": TEST_API_KEY})
    resp = client.delete("/items/1", headers={"X-API-Key": "wrong"})
    assert resp.status_code == 403


def test_delete_items_with_correct_key(client):
    """DELETE /items/<id> with correct key succeeds."""
    client.post("/items", json={"name": "to delete"},
                headers={"X-API-Key": TEST_API_KEY})
    resp = client.delete("/items/1", headers={"X-API-Key": TEST_API_KEY})
    assert resp.status_code == 204


# --- Health endpoint stays public ---

def test_health_no_key_needed(client):
    """Health endpoint works without any auth."""
    resp = client.get("/health")
    assert resp.status_code == 200
