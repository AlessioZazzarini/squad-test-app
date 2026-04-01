# Issue #2: SQLite persistent storage with config switch

## Description

Add SQLite-based persistence so items survive app restarts:

1. **SQLite repository** (`sqlite_repo.py`) — implements the repository interface using sqlite3
2. **Config switch** — environment variable `STORAGE=sqlite` vs `STORAGE=memory` (default: memory)
3. **Migration** — auto-create the items table on first run
4. **Tests** — pytest tests using a temporary SQLite database

depends-on: #1

## Acceptance Criteria

- [ ] `STORAGE=sqlite python app.py` starts with SQLite backend
- [ ] Items persist across app restarts when using SQLite
- [ ] Default behavior (no env var) still uses in-memory storage
- [ ] SQLite repo passes the same test suite as memory repo
- [ ] Table auto-creates if not present
- [ ] `pytest` passes with all tests green
