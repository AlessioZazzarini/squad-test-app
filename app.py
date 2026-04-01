"""Squad Test App — Minimal Flask REST API with JWT auth."""
import time
import traceback

from flask import Flask, g, jsonify, request
from flask_cors import CORS
from auth import create_token, require_auth, VALID_USERNAME, VALID_PASSWORD
from rate_limit import init_rate_limiter

app = Flask(__name__)
CORS(app)
init_rate_limiter(app)


@app.before_request
def start_timer():
    g.start_time = time.time()


@app.after_request
def log_request(response):
    start = getattr(g, "start_time", None)
    if start is not None:
        duration_ms = (time.time() - start) * 1000
        print(f"{request.method} {request.path} {response.status_code} {duration_ms:.1f}ms")
    return response

# In-memory store
items = []
next_id = 1


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/auth/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    username = data.get("username")
    password = data.get("password")

    if username != VALID_USERNAME or password != VALID_PASSWORD:
        return jsonify({"error": "invalid credentials"}), 401

    token = create_token(username)
    return jsonify({"token": token})


@app.route("/items", methods=["POST"])
@require_auth
def create_item():
    global next_id
    data = request.get_json(force=True, silent=True) or {}

    name = data.get("name")
    if not name or not isinstance(name, str) or name.strip() == "":
        return jsonify({"error": "name is required"}), 400
    if len(name) > 200:
        return jsonify({"error": "name must be 200 characters or fewer"}), 400

    description = data.get("description", "")
    if not isinstance(description, str):
        return jsonify({"error": "description must be a string"}), 400
    if len(description) > 1000:
        return jsonify({"error": "description must be 1000 characters or fewer"}), 400

    item = {"id": next_id, "name": name.strip(), "description": description}
    items.append(item)
    next_id += 1
    return jsonify(item), 201


@app.route("/items", methods=["GET"])
def list_items():
    try:
        limit = int(request.args.get("limit", 20))
    except (ValueError, TypeError):
        return jsonify({"error": "limit must be an integer"}), 400

    try:
        offset = int(request.args.get("offset", 0))
    except (ValueError, TypeError):
        return jsonify({"error": "offset must be an integer"}), 400

    if limit < 1 or limit > 100:
        return jsonify({"error": "limit must be between 1 and 100"}), 400
    if offset < 0:
        return jsonify({"error": "offset must be >= 0"}), 400

    result = items[offset : offset + limit]
    return jsonify(result)


@app.route("/items/<int:item_id>", methods=["GET"])
def get_item(item_id):
    for item in items:
        if item["id"] == item_id:
            return jsonify(item)
    return jsonify({"error": "item not found"}), 404


@app.route("/items/<int:item_id>", methods=["DELETE"])
@require_auth
def delete_item(item_id):
    global items
    for i, item in enumerate(items):
        if item["id"] == item_id:
            items.pop(i)
            return "", 204
    return jsonify({"error": "item not found"}), 404


@app.route("/boom")
def boom():
    raise RuntimeError("unexpected failure")


@app.errorhandler(Exception)
def handle_exception(e):
    traceback.print_exc()
    return jsonify({"error": "internal server error"}), 500


if __name__ == "__main__":
    app.run(debug=True, port=5000)
