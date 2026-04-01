# {{FEATURE_NAME}} — Investigation & Fix Plan

> **Status:** In progress — being populated by automated investigation
> **Branch:** `{{BRANCH_NAME}}`
> **Product:** {{PRODUCT_NAME}} ({{PRODUCT_DESCRIPTION}})

---

## Executive Summary

_To be written after investigation is complete._

---

## File Map

| File | Role |
|------|------|
| | |

---

## Data Flow Diagram

_Text-based diagram showing the full feature flow._

```
[Input] -> [Processing] -> [Storage] -> [Display]
```

---

## Database Tables

| Table | Key Columns | Role |
|-------|-------------|------|
| | | |

---

## Problem 1: [Title]

### Current Behavior
_What is happening now?_

### Expected Behavior
_What should happen?_

### Findings
_Evidence from code review and diagnostic queries._

### Root Cause
_Exact file, function, line number, and evidence._

---

## Problem 2: [Title]

### Current Behavior
_What is happening now?_

### Expected Behavior
_What should happen?_

### Findings
_Evidence from code tracing and diagnostic queries._

### Root Cause
_Exact point of failure, with file path and evidence._

---

_Repeat for each problem..._

---

## Changes Overview

| # | What | File(s) | Risk | Phase |
|---|------|---------|------|-------|
| | | | | |

---

## Change 1: [Title]

**File:** `[exact file path]`
**Lines:** [line numbers]
**Why:** [1-2 sentences explaining the root cause]

### Current Code (lines X-Y):
```
// Pseudocode or description of what the code currently does
```

### Replace with:
```
// Pseudocode or description of what the code SHOULD do
// NOT actual implementation — describe the logic clearly enough
// that a developer can write it without asking questions
```

**Key design decisions:**
- [Why this approach over alternatives]

---

_Repeat for each change..._

---

## Implementation Phases

### Phase 1: [Title] (Low Risk)
**Changes:** [list change numbers]
**Files:** [list files]
**Test:** [specific command + what to check]
**Rollback:** [how to undo]

### Phase 2: [Title] (Medium Risk)
**Changes:** [list change numbers]
**Files:** [list files]
**Test:** [specific command + what to check]
**Rollback:** [how to undo]

_Repeat for each phase..._

---

## Verification Matrix

| Check | Command / Method | Pass Criteria |
|-------|-----------------|---------------|
| Build | `{{BUILD_CMD}}` | Zero errors |
| Unit tests | `{{TEST_CMD}}` | All pass, new tests for: [list] |
| E2E | `{{E2E_CMD}}` | Existing tests pass |
| | | |

---

## Debate Log

### Round 1
| # | Issue | Critical? | Decision | Reason |
|---|-------|-----------|----------|--------|
| | | | | |

### Round 2
| # | Issue | Critical? | Decision | Reason |
|---|-------|-----------|----------|--------|
| | | | | |

### Round 3
| # | Issue | Critical? | Decision | Reason |
|---|-------|-----------|----------|--------|
| | | | | |

### Round 4
| # | Issue | Critical? | Decision | Reason |
|---|-------|-----------|----------|--------|
| | | | | |

### Round 5
| # | Issue | Critical? | Decision | Reason |
|---|-------|-----------|----------|--------|
| | | | | |

---

## Debate Provenance

| Round | Issues Found | Critical | Accepted | Rejected |
|-------|-------------|----------|----------|----------|
| 1     |             |          |          |          |
| 2     |             |          |          |          |
| 3     |             |          |          |          |
| 4     |             |          |          |          |
| 5     |             |          |          |          |
| **Total** |         |          |          |          |

---

## Known Follow-Ups (Out of Scope)

_Items identified during investigation that are deferred._
