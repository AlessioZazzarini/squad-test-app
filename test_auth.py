"""Tests for JWT authentication."""
import datetime
import pytest
import jwt

from app import app
from auth import SECRET_KEY, ALGORITHM, create_token


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


@pytest.fixture(autouse=True)
def reset_items():
    """Reset in-memory store between tests."""
    import app as app_module
    app_module.items.clear()
    app_module.next_id = 1


def get_auth_header(token):
    return {"Authorization": f"Bearer {token}"}


# --- Login tests ---

def test_login_valid_credentials(client):
    resp = client.post("/auth/login", json={"username": "admin", "password": "secret"})
    assert resp.status_code == 200
    data = resp.get_json()
    assert "token" in data
    # Verify token is valid JWT
    payload = jwt.decode(data["token"], SECRET_KEY, algorithms=[ALGORITHM])
    assert payload["sub"] == "admin"


def test_login_invalid_password(client):
    resp = client.post("/auth/login", json={"username": "admin", "password": "wrong"})
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "invalid credentials"


def test_login_invalid_username(client):
    resp = client.post("/auth/login", json={"username": "nobody", "password": "secret"})
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "invalid credentials"


def test_login_missing_fields(client):
    resp = client.post("/auth/login", json={})
    assert resp.status_code == 401


# --- Protected POST /items ---

def test_create_item_without_token(client):
    resp = client.post("/items", json={"name": "test"})
    assert resp.status_code == 401


def test_create_item_with_valid_token(client):
    token = create_token("admin")
    resp = client.post("/items", json={"name": "test item"},
                       headers=get_auth_header(token))
    assert resp.status_code == 201
    assert resp.get_json()["name"] == "test item"


def test_create_item_with_malformed_token(client):
    resp = client.post("/items", json={"name": "test"},
                       headers=get_auth_header("not-a-real-token"))
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "invalid token"


def test_create_item_no_auth_header(client):
    resp = client.post("/items", json={"name": "test"})
    assert resp.status_code == 401
    assert resp.get_json()["error"] == "missing or invalid authorization header"


def test_create_item_wrong_auth_scheme(client):
    resp = client.post("/items", json={"name": "test"},
                       headers={"Authorization": "Basic abc123"})
    assert resp.status_code == 401


# --- Protected DELETE /items/<id> ---

def test_delete_item_without_token(client):
    # First create an item with auth
    token = create_token("admin")
    client.post("/items", json={"name": "to delete"}, headers=get_auth_header(token))

    # Try to delete without token
    resp = client.delete("/items/1")
    assert resp.status_code == 401


def test_delete_item_with_valid_token(client):
    token = create_token("admin")
    client.post("/items", json={"name": "to delete"}, headers=get_auth_header(token))

    resp = client.delete("/items/1", headers=get_auth_header(token))
    assert resp.status_code == 204


# --- Public GET endpoints ---

def test_get_items_public(client):
    resp = client.get("/items")
    assert resp.status_code == 200


def test_get_item_public(client):
    token = create_token("admin")
    client.post("/items", json={"name": "public item"}, headers=get_auth_header(token))

    resp = client.get("/items/1")
    assert resp.status_code == 200
    assert resp.get_json()["name"] == "public item"


# --- Expired token ---

def test_expired_token(client):
    payload = {
        "sub": "admin",
        "iat": datetime.datetime.utcnow() - datetime.timedelta(hours=2),
        "exp": datetime.datetime.utcnow() - datetime.timedelta(hours=1),
    }
    expired_token = jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

    resp = client.post("/items", json={"name": "test"},
                       headers=get_auth_header(expired_token))
    assert resp.status_code == 403
    assert resp.get_json()["error"] == "token expired"
