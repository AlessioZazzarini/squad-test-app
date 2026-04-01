# {{FEATURE_NAME}} — Merge Report

> **Branch:** `{{BRANCH_NAME}}`
> **Product:** {{PRODUCT_NAME}}

---

## Summary

_1 paragraph: what was implemented and why._

---

## Phase-by-Phase Log

### Phase 1: [Title] — `[commit hash]`
- **Files changed:** [list]
- **What was done:** [2-3 sentences]
- **Build status:** PASS

### Phase 2: [Title] — `[commit hash]`
- **Files changed:** [list]
- **What was done:** [2-3 sentences]
- **Build status:** PASS

_Repeat for all phases..._

---

## Test Results

| Suite | Status | Total | New |
|-------|--------|-------|-----|
| `{{BUILD_CMD}}` | PASS | — | — |
| `{{TEST_CMD}}` | PASS | | |
| `{{E2E_CMD}}` | PASS | | |

---

## New Tests Added

| Test File | What It Tests |
|-----------|--------------|
| | |

---

## New Files Created

| File | Purpose |
|------|---------|
| | |

---

## Modified Files

| File | Change Summary |
|------|--------------|
| | |

---

## How to Merge

```bash
git checkout main
git merge {{BRANCH_NAME}}
{{BUILD_CMD}}
{{TEST_CMD}}
{{E2E_CMD}}
```

---

## Known Considerations

_Anything the reviewer should know — edge cases, things to manually verify, etc._
