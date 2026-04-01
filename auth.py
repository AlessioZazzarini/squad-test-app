"""JWT and API key authentication module for Squad Test App."""
import datetime
import functools
import os

import jwt
from flask import request, jsonify

SECRET_KEY = "squad-test-secret-key-32bytes!!"
ALGORITHM = "HS256"
TOKEN_EXPIRY_MINUTES = 30

# Hardcoded credentials for demo purposes
VALID_USERNAME = "admin"
VALID_PASSWORD = "secret"

# API key from environment variable
API_SECRET_KEY = os.environ.get("API_SECRET_KEY")


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


def _check_api_key():
    """Check X-API-Key header. Returns (success, error_response) tuple."""
    api_key = request.headers.get("X-API-Key")
    if api_key is None:
        return False, None  # No API key provided, not an error yet
    if not API_SECRET_KEY:
        return False, (jsonify({"error": "API key authentication not configured"}), 500)
    if api_key != API_SECRET_KEY:
        return False, (jsonify({"error": "invalid API key"}), 403)
    return True, None


def _check_jwt():
    """Check JWT Bearer token. Returns (success, error_response) tuple."""
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return False, None  # No JWT provided, not an error yet

    token = auth_header.split("Bearer ", 1)[1]
    try:
        verify_token(token)
    except jwt.ExpiredSignatureError:
        return False, (jsonify({"error": "token expired"}), 403)
    except jwt.InvalidTokenError:
        return False, (jsonify({"error": "invalid token"}), 401)
    return True, None


def require_auth(f):
    """Decorator that requires a valid JWT Bearer token or API key."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        # Try API key first
        api_key_ok, api_key_err = _check_api_key()
        if api_key_ok:
            return f(*args, **kwargs)
        if api_key_err:
            return api_key_err

        # Try JWT
        jwt_ok, jwt_err = _check_jwt()
        if jwt_ok:
            return f(*args, **kwargs)
        if jwt_err:
            return jwt_err

        # Neither provided
        return jsonify({"error": "missing or invalid authorization header"}), 401

    return decorated
