"""Tests for the Flask CRUD API."""
import pytest
from app import app
from memory_repo import MemoryRepository
from repository import ItemRepository


@pytest.fixture
def client():
    """Provide a fresh test client with an empty repository each test."""
    import app as app_module
    app_module.repo = MemoryRepository()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json["status"] == "ok"


def test_list_items_empty(client):
    resp = client.get("/items")
    assert resp.status_code == 200
    assert resp.json == {"items": [], "total": 0, "limit": 20, "offset": 0}


def test_create_item(client):
    resp = client.post("/items", json={"name": "test", "description": "desc"})
    assert resp.status_code == 201
    data = resp.json
    assert "id" in data
    assert data["name"] == "test"
    assert data["description"] == "desc"


def test_get_item(client):
    create_resp = client.post("/items", json={"name": "test", "description": "desc"})
    item_id = create_resp.json["id"]
    resp = client.get(f"/items/{item_id}")
    assert resp.status_code == 200
    assert resp.json["id"] == item_id
    assert resp.json["name"] == "test"


def test_get_item_not_found(client):
    resp = client.get("/items/nonexistent")
    assert resp.status_code == 404


def test_delete_item(client):
    create_resp = client.post("/items", json={"name": "test", "description": "desc"})
    item_id = create_resp.json["id"]
    resp = client.delete(f"/items/{item_id}")
    assert resp.status_code == 204


def test_delete_item_not_found(client):
    resp = client.delete("/items/nonexistent")
    assert resp.status_code == 404


def test_get_item_after_delete(client):
    create_resp = client.post("/items", json={"name": "test", "description": "desc"})
    item_id = create_resp.json["id"]
    client.delete(f"/items/{item_id}")
    resp = client.get(f"/items/{item_id}")
    assert resp.status_code == 404


def _seed_items(client):
    """Helper to create a few items for search/pagination tests."""
    items = [
        {"name": "Alpha Widget", "description": "A first widget"},
        {"name": "Beta Gadget", "description": "A second gadget"},
        {"name": "Gamma Widget", "description": "Third item"},
        {"name": "Delta", "description": "Contains widget in description"},
    ]
    for item in items:
        client.post("/items", json=item)


# --- Search tests ---

def test_search_by_name(client):
    _seed_items(client)
    resp = client.get("/items?q=widget")
    assert resp.status_code == 200
    data = resp.json
    assert data["total"] == 3  # Alpha Widget, Gamma Widget, Delta (description)
    assert all("widget" in i["name"].lower() or "widget" in i["description"].lower()
               for i in data["items"])


def test_search_by_description(client):
    _seed_items(client)
    resp = client.get("/items?q=gadget")
    data = resp.json
    assert data["total"] == 1
    assert data["items"][0]["name"] == "Beta Gadget"


def test_search_case_insensitive(client):
    _seed_items(client)
    resp = client.get("/items?q=WIDGET")
    assert resp.json["total"] == 3


def test_empty_search_returns_all(client):
    _seed_items(client)
    resp = client.get("/items")
    assert resp.json["total"] == 4


def test_search_no_match(client):
    _seed_items(client)
    resp = client.get("/items?q=nonexistent")
    data = resp.json
    assert data["total"] == 0
    assert data["items"] == []


# --- Pagination tests ---

def test_pagination_limit(client):
    _seed_items(client)
    resp = client.get("/items?limit=2&offset=0")
    data = resp.json
    assert len(data["items"]) == 2
    assert data["total"] == 4
    assert data["limit"] == 2
    assert data["offset"] == 0


def test_pagination_offset(client):
    _seed_items(client)
    resp1 = client.get("/items?limit=2&offset=0")
    resp2 = client.get("/items?limit=2&offset=2")
    ids1 = {i["id"] for i in resp1.json["items"]}
    ids2 = {i["id"] for i in resp2.json["items"]}
    assert len(ids1) == 2
    assert len(ids2) == 2
    assert ids1.isdisjoint(ids2)


def test_pagination_offset_beyond_total(client):
    _seed_items(client)
    resp = client.get("/items?limit=20&offset=100")
    data = resp.json
    assert data["items"] == []
    assert data["total"] == 4


def test_search_with_pagination(client):
    _seed_items(client)
    resp = client.get("/items?q=widget&limit=1&offset=0")
    data = resp.json
    assert len(data["items"]) == 1
    assert data["total"] == 3


# --- Invalid parameter tests ---

def test_invalid_limit_non_integer(client):
    resp = client.get("/items?limit=abc")
    assert resp.status_code == 400
    assert "error" in resp.json


def test_invalid_offset_non_integer(client):
    resp = client.get("/items?offset=xyz")
    assert resp.status_code == 400
    assert "error" in resp.json


def test_negative_limit(client):
    resp = client.get("/items?limit=-1")
    assert resp.status_code == 400
    assert "error" in resp.json


def test_negative_offset(client):
    resp = client.get("/items?offset=-5")
    assert resp.status_code == 400
    assert "error" in resp.json


def test_repository_interface_is_abstract():
    with pytest.raises(TypeError):
        ItemRepository()
