"""JWT authentication module for Squad Test App."""
import datetime
import functools

import jwt
from flask import request, jsonify

SECRET_KEY = "squad-test-secret-key-32bytes!!"
ALGORITHM = "HS256"
TOKEN_EXPIRY_MINUTES = 30

# Hardcoded credentials for demo purposes
VALID_USERNAME = "admin"
VALID_PASSWORD = "secret"


def create_token(username):
    """Create a JWT token for the given username."""
    payload = {
        "sub": username,
        "iat": datetime.datetime.utcnow(),
        "exp": datetime.datetime.utcnow() + datetime.timedelta(minutes=TOKEN_EXPIRY_MINUTES),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token):
    """Verify and decode a JWT token. Returns payload or raises."""
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])


def require_auth(f):
    """Decorator that requires a valid JWT Bearer token."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "missing or invalid authorization header"}), 401

        token = auth_header.split("Bearer ", 1)[1]
        try:
            verify_token(token)
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "token expired"}), 403
        except jwt.InvalidTokenError:
            return jsonify({"error": "invalid token"}), 401

        return f(*args, **kwargs)
    return decorated
