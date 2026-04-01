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
    assert resp.json == []


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


def test_repository_interface_is_abstract():
    with pytest.raises(TypeError):
        ItemRepository()
