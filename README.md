# Squad Test App

A simple Flask REST API for testing the AgentSquad autonomous development toolkit.

## Setup

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
python app.py
```

## Test

```bash
pytest
```

## API Endpoints

- `GET /health` — Health check
- `GET /items` — List all items
- `POST /items` — Create an item
- `GET /items/<id>` — Get a single item
- `DELETE /items/<id>` — Delete an item
