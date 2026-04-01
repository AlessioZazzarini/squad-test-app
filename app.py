"""Squad Test App — Minimal Flask REST API."""
from flask import Flask, request, jsonify

from memory_repo import MemoryRepository

app = Flask(__name__)
repo = MemoryRepository()


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/items", methods=["GET"])
def list_items():
    q = request.args.get("q", "")
    raw_limit = request.args.get("limit", "20")
    raw_offset = request.args.get("offset", "0")

    try:
        limit = int(raw_limit)
        offset = int(raw_offset)
    except (ValueError, TypeError):
        return jsonify({"error": "limit and offset must be integers"}), 400

    if limit < 0 or offset < 0:
        return jsonify({"error": "limit and offset must be non-negative"}), 400

    items, total = repo.search(q, limit, offset)
    return jsonify({"items": items, "total": total, "limit": limit, "offset": offset})


@app.route("/items", methods=["POST"])
def create_item():
    data = request.get_json()
    item = repo.add(data)
    return jsonify(item), 201


@app.route("/items/<item_id>", methods=["GET"])
def get_item(item_id):
    item = repo.get(item_id)
    if item is None:
        return jsonify({"error": "not found"}), 404
    return jsonify(item)


@app.route("/items/<item_id>", methods=["DELETE"])
def delete_item(item_id):
    if repo.delete(item_id):
        return "", 204
    return jsonify({"error": "not found"}), 404


if __name__ == "__main__":
    app.run(debug=True, port=5000)
