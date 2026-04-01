"""Basic tests for the Flask app."""
import json

import pytest

import app as app_module
from app import app, items
from auth import create_token


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        items.clear()
        app_module.next_id = 1
        yield c


@pytest.fixture
def auth_header():
    token = create_token("admin")
    return {"Authorization": f"Bearer {token}"}


# --- Health ---

def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json
    assert data["status"] == "ok"
    assert data["version"] == "1.0.0"
    assert isinstance(data["uptime_seconds"], (int, float))
    assert data["uptime_seconds"] >= 0
    assert data["items_count"] == 0


def test_health_items_count(client, auth_header):
    client.post("/items", json={"name": "A"}, headers=auth_header)
    client.post("/items", json={"name": "B"}, headers=auth_header)
    resp = client.get("/health")
    assert resp.json["items_count"] == 2


def test_health_uptime_increases(client):
    import time
    r1 = client.get("/health")
    time.sleep(0.05)
    r2 = client.get("/health")
    assert r2.json["uptime_seconds"] >= r1.json["uptime_seconds"]


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


def test_list_items_with_data(client, auth_header):
    client.post("/items", json={"name": "A"}, headers=auth_header)
    client.post("/items", json={"name": "B"}, headers=auth_header)
    resp = client.get("/items")
    assert resp.status_code == 200
    assert len(resp.json) == 2


def test_list_items_limit_offset(client, auth_header):
    for i in range(5):
        client.post("/items", json={"name": f"Item {i}"}, headers=auth_header)
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


# --- CORS ---

def test_cors_headers_on_regular_request(client):
    resp = client.get("/health", headers={"Origin": "http://example.com"})
    assert resp.status_code == 200
    assert resp.headers.get("Access-Control-Allow-Origin") == "http://example.com"


def test_cors_preflight_options(client):
    resp = client.options("/items", headers={
        "Origin": "http://example.com",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "Authorization,Content-Type",
    })
    assert resp.status_code == 200
    assert "Access-Control-Allow-Origin" in resp.headers
    assert "POST" in resp.headers.get("Access-Control-Allow-Methods", "")


# --- Request Logging ---

def test_request_logging(client, capsys):
    client.get("/health")
    captured = capsys.readouterr()
    assert "GET /health" in captured.out
    assert "ms" in captured.out


# --- Tags ---

def test_create_item_with_tags(client, auth_header):
    resp = client.post("/items", json={"name": "Tagged", "tags": ["python", "api"]}, headers=auth_header)
    assert resp.status_code == 201
    assert resp.json["tags"] == ["python", "api"]


def test_create_item_without_tags(client, auth_header):
    resp = client.post("/items", json={"name": "No tags"}, headers=auth_header)
    assert resp.status_code == 201
    assert resp.json["tags"] == []


def test_create_item_invalid_tags(client, auth_header):
    resp = client.post("/items", json={"name": "Bad", "tags": "not-a-list"}, headers=auth_header)
    assert resp.status_code == 400
    assert "tags" in resp.json["error"]


def test_create_item_tags_non_string_elements(client, auth_header):
    resp = client.post("/items", json={"name": "Bad", "tags": [1, 2]}, headers=auth_header)
    assert resp.status_code == 400


def test_get_item_includes_tags(client, auth_header):
    client.post("/items", json={"name": "X", "tags": ["go"]}, headers=auth_header)
    resp = client.get("/items/1")
    assert resp.status_code == 200
    assert resp.json["tags"] == ["go"]


def test_filter_items_by_tag(client, auth_header):
    client.post("/items", json={"name": "A", "tags": ["python"]}, headers=auth_header)
    client.post("/items", json={"name": "B", "tags": ["go"]}, headers=auth_header)
    client.post("/items", json={"name": "C", "tags": ["python", "api"]}, headers=auth_header)
    resp = client.get("/items?tag=python")
    assert resp.status_code == 200
    assert len(resp.json) == 2
    names = [item["name"] for item in resp.json]
    assert "A" in names
    assert "C" in names


def test_filter_items_by_tag_no_match(client, auth_header):
    client.post("/items", json={"name": "A", "tags": ["python"]}, headers=auth_header)
    resp = client.get("/items?tag=rust")
    assert resp.status_code == 200
    assert resp.json == []


# --- PUT /items/<id> (update item) ---

def test_update_item_all_fields(client, auth_header):
    client.post("/items", json={"name": "Original", "description": "Old desc", "tags": ["old"]}, headers=auth_header)
    resp = client.put("/items/1", json={"name": "Updated", "description": "New desc", "tags": ["new"]}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["name"] == "Updated"
    assert resp.json["description"] == "New desc"
    assert resp.json["tags"] == ["new"]


def test_update_item_name_only(client, auth_header):
    client.post("/items", json={"name": "Original", "description": "Keep me", "tags": ["keep"]}, headers=auth_header)
    resp = client.put("/items/1", json={"name": "Changed"}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["name"] == "Changed"
    assert resp.json["description"] == "Keep me"
    assert resp.json["tags"] == ["keep"]


def test_update_item_tags_only(client, auth_header):
    client.post("/items", json={"name": "Keep", "tags": ["old"]}, headers=auth_header)
    resp = client.put("/items/1", json={"tags": ["new1", "new2"]}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["name"] == "Keep"
    assert resp.json["tags"] == ["new1", "new2"]


def test_update_item_description_only(client, auth_header):
    client.post("/items", json={"name": "Keep", "description": "Old"}, headers=auth_header)
    resp = client.put("/items/1", json={"description": "New"}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["name"] == "Keep"
    assert resp.json["description"] == "New"


def test_update_item_invalid_name_empty(client, auth_header):
    client.post("/items", json={"name": "X"}, headers=auth_header)
    resp = client.put("/items/1", json={"name": ""}, headers=auth_header)
    assert resp.status_code == 400


def test_update_item_invalid_name_too_long(client, auth_header):
    client.post("/items", json={"name": "X"}, headers=auth_header)
    resp = client.put("/items/1", json={"name": "a" * 201}, headers=auth_header)
    assert resp.status_code == 400
    assert "200" in resp.json["error"]


def test_update_item_invalid_description_too_long(client, auth_header):
    client.post("/items", json={"name": "X"}, headers=auth_header)
    resp = client.put("/items/1", json={"description": "d" * 1001}, headers=auth_header)
    assert resp.status_code == 400
    assert "1000" in resp.json["error"]


def test_update_item_invalid_tags(client, auth_header):
    client.post("/items", json={"name": "X"}, headers=auth_header)
    resp = client.put("/items/1", json={"tags": "not-a-list"}, headers=auth_header)
    assert resp.status_code == 400
    assert "tags" in resp.json["error"]


def test_update_item_not_found(client, auth_header):
    resp = client.put("/items/999", json={"name": "Nope"}, headers=auth_header)
    assert resp.status_code == 404


def test_update_item_requires_auth(client):
    resp = client.put("/items/1", json={"name": "Nope"})
    assert resp.status_code == 401


def test_update_item_name_strips_whitespace(client, auth_header):
    client.post("/items", json={"name": "X"}, headers=auth_header)
    resp = client.put("/items/1", json={"name": "  Trimmed  "}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["name"] == "Trimmed"


# --- PUT /items/<id>/tags ---

def test_update_tags(client, auth_header):
    client.post("/items", json={"name": "X", "tags": ["old"]}, headers=auth_header)
    resp = client.put("/items/1/tags", json={"tags": ["new-tag"]}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["tags"] == ["new-tag"]


def test_update_tags_empty(client, auth_header):
    client.post("/items", json={"name": "X", "tags": ["old"]}, headers=auth_header)
    resp = client.put("/items/1/tags", json={"tags": []}, headers=auth_header)
    assert resp.status_code == 200
    assert resp.json["tags"] == []


def test_update_tags_not_found(client, auth_header):
    resp = client.put("/items/999/tags", json={"tags": ["x"]}, headers=auth_header)
    assert resp.status_code == 404


def test_update_tags_invalid(client, auth_header):
    client.post("/items", json={"name": "X"}, headers=auth_header)
    resp = client.put("/items/1/tags", json={"tags": "bad"}, headers=auth_header)
    assert resp.status_code == 400


def test_update_tags_requires_auth(client):
    resp = client.put("/items/1/tags", json={"tags": ["x"]})
    assert resp.status_code == 401


# --- Global error handler ---

def test_unhandled_exception_returns_json(client):
    resp = client.get("/boom")
    assert resp.status_code == 500
    assert resp.json["error"] == "internal server error"
