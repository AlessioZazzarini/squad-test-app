## Description

Enhance the /health endpoint to return system information.

**Complexity: simple**

## Requirements

1. **GET /health** — return `{"status": "ok", "version": "1.0.0", "uptime_seconds": N, "items_count": N}`
2. **Version** — read from a `VERSION` file in project root (create it with "1.0.0")
3. **Uptime** — track app start time, compute delta
4. **Items count** — query the repository for total item count
5. **Tests** — verify all fields present, uptime increases between calls

## Acceptance Criteria

- [ ] GET /health returns status, version, uptime_seconds, items_count
- [ ] version field matches VERSION file content
- [ ] uptime_seconds is a positive number
- [ ] items_count reflects actual item count
- [ ] All tests pass
