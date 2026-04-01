"""Basic tests for the Flask app."""
import json

import pytest

from app import app, items
from auth import create_token


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        items.clear()
        yield c


@pytest.fixture
def auth_header():
    token = create_token("admin")
    return {"Authorization": f"Bearer {token}"}


# --- Health ---

def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json["status"] == "ok"


# --- POST /items validation ---

def test_create_item_valid(client, auth_header):
    resp = client.post("/items", json={"name": "Test Item", "description": "A desc"}, headers=auth_header)
    assert resp.status_code == 201
    data = resp.json
    assert data["name"] == "Test Item"
    assert data["description"] == "A desc"
    assert "id" in data


def test_create_item_name_only(client, auth_header):
    resp = client.post("/items", json={"name": "Minimal"}, headers=auth_header)
    assert resp.status_code == 201
    assert resp.json["description"] == ""


def test_create_item_missing_name(client, auth_header):
    resp = client.post("/items", json={}, headers=auth_header)
    assert resp.status_code == 400
    assert resp.json["error"] == "name is required"


def test_create_item_empty_name(client, auth_header):
    resp = client.post("/items", json={"name": ""}, headers=auth_header)
    assert resp.status_code == 400
    assert resp.json["error"] == "name is required"


def test_create_item_whitespace_name(client, auth_header):
    resp = client.post("/items", json={"name": "   "}, headers=auth_header)
    assert resp.status_code == 400
    assert resp.json["error"] == "name is required"


def test_create_item_name_too_long(client, auth_header):
    resp = client.post("/items", json={"name": "a" * 201}, headers=auth_header)
    assert resp.status_code == 400
    assert "200" in resp.json["error"]


def test_create_item_name_at_boundary(client, auth_header):
    resp = client.post("/items", json={"name": "a" * 200}, headers=auth_header)
    assert resp.status_code == 201


def test_create_item_description_too_long(client, auth_header):
    resp = client.post("/items", json={"name": "ok", "description": "d" * 1001}, headers=auth_header)
    assert resp.status_code == 400
    assert "1000" in resp.json["error"]


def test_create_item_description_at_boundary(client, auth_header):
    resp = client.post("/items", json={"name": "ok", "description": "d" * 1000}, headers=auth_header)
    assert resp.status_code == 201


def test_create_item_name_wrong_type(client, auth_header):
    resp = client.post("/items", json={"name": 123}, headers=auth_header)
    assert resp.status_code == 400


def test_create_item_description_wrong_type(client, auth_header):
    resp = client.post("/items", json={"name": "ok", "description": 42}, headers=auth_header)
    assert resp.status_code == 400
    assert "string" in resp.json["error"]


def test_create_item_no_body(client, auth_header):
    resp = client.post("/items", content_type="application/json", headers=auth_header)
    assert resp.status_code == 400
    assert resp.json["error"] == "name is required"


# --- GET /items query param validation ---

def test_list_items_default(client):
    resp = client.get("/items")
    assert resp.status_code == 200
    assert resp.json == []


def test_list_items_with_data(client):
    client.post("/items", json={"name": "A"})
    client.post("/items", json={"name": "B"})
    resp = client.get("/items")
    assert resp.status_code == 200
    assert len(resp.json) == 2


def test_list_items_limit_offset(client):
    for i in range(5):
        client.post("/items", json={"name": f"Item {i}"})
    resp = client.get("/items?limit=2&offset=1")
    assert resp.status_code == 200
    assert len(resp.json) == 2
    assert resp.json[0]["name"] == "Item 1"


def test_list_items_limit_zero(client):
    resp = client.get("/items?limit=0")
    assert resp.status_code == 400


def test_list_items_limit_101(client):
    resp = client.get("/items?limit=101")
    assert resp.status_code == 400


def test_list_items_limit_negative(client):
    resp = client.get("/items?limit=-1")
    assert resp.status_code == 400


def test_list_items_limit_1(client):
    resp = client.get("/items?limit=1")
    assert resp.status_code == 200


def test_list_items_limit_100(client):
    resp = client.get("/items?limit=100")
    assert resp.status_code == 200


def test_list_items_offset_negative(client):
    resp = client.get("/items?offset=-1")
    assert resp.status_code == 400


def test_list_items_limit_not_int(client):
    resp = client.get("/items?limit=abc")
    assert resp.status_code == 400


def test_list_items_offset_not_int(client):
    resp = client.get("/items?offset=xyz")
    assert resp.status_code == 400


# --- Global error handler ---

def test_unhandled_exception_returns_json(client):
    resp = client.get("/boom")
    assert resp.status_code == 500
    assert resp.json["error"] == "internal server error"
