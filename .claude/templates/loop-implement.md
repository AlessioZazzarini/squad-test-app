# AgentSquad LOOP SUPER PROMPT — {{FEATURE_NAME}} Implementation

## FILE LOCATIONS (READ THIS IF YOU GET LOST)

| File | Location | Purpose |
|------|----------|---------|
| **This super prompt** | `.claude/plans/loop-{{TASK_NAME}}.md` | The HOW — execution order, git workflow, tests, acceptance gates |
| **The implementation plan** | `.claude/plans/{{PLAN_FILE_PATH}}` | The WHAT — every code change, line by line. Your single source of truth. |
| **Execution log** (you maintain this) | `.claude/plans/execution-log-{{TASK_NAME}}.md` | The TRACE — timestamped log of every action you take. |

**If stuck on WHICH PHASE:** Re-read this file.
**If stuck on WHAT CODE TO WRITE:** Re-read `.claude/plans/{{PLAN_FILE_PATH}}`.

---

## MISSION

You are implementing the **{{FEATURE_NAME}}** for {{PRODUCT_NAME}} ({{PRODUCT_DESCRIPTION}}). The full implementation plan is at `.claude/plans/{{PLAN_FILE_PATH}}`. That plan is your **single source of truth** — follow it exactly, do not redesign or reinterpret any change.

Execute all phases end-to-end. After each phase, commit to the feature branch. Do NOT stop between phases.

---

## GIT WORKFLOW (MANDATORY — DO THIS FIRST)

```bash
git checkout -b {{BRANCH_NAME}}
```

ALL work on this branch. **Never commit to main.** After each phase:

```
git add -A && git commit -m "Phase X: <short description>"
```

---

## EXECUTION LOG (MANDATORY — CREATE BEFORE ANY OTHER WORK)

Create `.claude/plans/execution-log-{{TASK_NAME}}.md` with this header:

```markdown
# Execution Log — {{TASK_NAME}}
> Started: [current timestamp]
> Branch: {{BRANCH_NAME}}
> Plan: {{PLAN_FILE_PATH}}
```

**From this point forward, append every action to this file:**
- Every file you modify (path + what you changed + why)
- Every build/test run (command + result: pass/fail + error count)
- Every decision that deviates from the plan (what + why)
- Every error you hit and how you resolved it
- Every commit

This is not optional. The execution log is committed alongside your work at every phase.

---

## EXECUTION ORDER

<!-- 
INSTRUCTIONS FOR FILLING IN:
Copy the Implementation Phases from the plan document. For each phase, structure it as:
-->

### Phase 1: {{PHASE_1_TITLE}}
**Changes:** {{Change numbers from plan}}
**Files:** {{Files affected}}
1. Implement each change as specified in the plan
2. Run `npm run build` — must pass with zero errors
3. **Commit:** `git add -A && git commit -m "Phase 1: {{PHASE_1_TITLE}}"`

### Phase 2: {{PHASE_2_TITLE}}
**Changes:** {{Change numbers from plan}}
**Files:** {{Files affected}}
1. Implement each change as specified in the plan
2. Run `npm run build` — must pass with zero errors
3. **Commit:** `git add -A && git commit -m "Phase 2: {{PHASE_2_TITLE}}"`

<!-- Repeat for all phases in the plan... -->

### Phase N-1: Tests
**Goal:** Write all new tests specified in the plan's Verification Matrix.
1. Write all new unit tests
2. Write all new E2E tests
3. Run `npm run build` — must pass
4. Run `npm run test` — ALL tests must pass
5. Run `npm run test:e2e` — ALL tests must pass
6. **Commit:** `git add -A && git commit -m "Phase N-1: All tests passing"`

### Phase N: Merge Report
**Goal:** Document everything for the morning reviewer.
1. Run `npm run build` — capture output
2. Run `npm run test` — capture test count
3. Run `npm run test:e2e` — capture test count
4. Run `git log --oneline` to get commit hashes
5. Create `MERGE-REPORT-{{FEATURE_NAME}}.md` in repo root with:
   - Branch name
   - Summary (1 paragraph)
   - Phase-by-phase log (commit hash, files changed, what was done, build status)
   - Test results (exact counts from actual output)
   - New tests added (list every new test file)
   - New files created
   - Modified files (with 1-line summary per file)
   - How to merge (step-by-step commands)
   - Known considerations
6. **Commit:** `git add -A && git commit -m "Phase N: Merge report"`

---

## ACCEPTANCE CRITERIA

Output `<promise>{{MAGIC_WORD}}</promise>` ONLY when ALL gates pass.

### Gate 1: Compilation
- [ ] `npm run build` exits with code 0 and zero errors

### Gate 2: Unit Tests
- [ ] `npm run test` exits with code 0
- [ ] All pre-existing tests still pass (zero regressions)
- [ ] All new tests specified in the plan are written and passing

### Gate 3: E2E Tests
- [ ] `npm run test:e2e` exits with code 0
- [ ] All pre-existing E2E tests still pass (zero regressions)
- [ ] All new E2E tests specified in the plan are written and passing

### Gate 4: Code Correctness
<!-- 
INSTRUCTIONS: Copy the specific correctness checks from the plan's Verification Matrix.
Each check should be a binary pass/fail condition. Example:
- [ ] `AuthProvider` exports `useAuth` hook
- [ ] `buildQuery()` requires `userId` parameter (not optional)
-->
- [ ] {{CORRECTNESS_CHECK_1}}
- [ ] {{CORRECTNESS_CHECK_2}}
- [ ] {{CORRECTNESS_CHECK_3}}

### Gate 5: Git Hygiene
- [ ] All work is on branch `{{BRANCH_NAME}}`
- [ ] No commits on `main`
- [ ] One commit per phase

### Gate 6: Merge Report
- [ ] `MERGE-REPORT-{{FEATURE_NAME}}.md` exists in repo root
- [ ] Contains all required sections with real data (no fabricated hashes or counts)
- [ ] Test counts match actual `npm run test` output

### Gate 7: Execution Log
- [ ] `.claude/plans/execution-log-{{TASK_NAME}}.md` exists
- [ ] Every phase has timestamped entries
- [ ] Build/test results are logged with actual output
- [ ] Any deviations from the plan are documented with reasons
- [ ] Errors and resolutions are documented

---

## RULES

1. **Follow the plan exactly.** `.claude/plans/{{PLAN_FILE_PATH}}` specifies every code change. Do not redesign or skip any change.
2. **If lost, re-read this file first**, then the relevant Change section in the plan.
3. **Never commit to main.**
4. **Run `npm run build` after every phase.** Fix before moving on.
5. **Run `npm run test` after test-related phases.** Fix before moving on.
6. **When writing tests, test real behavior.** Mock external dependencies but test actual logic.
7. **If a file path or line number in the plan doesn't match,** search for the code patterns described to find the correct location.
8. **Do not modify files outside the plan's scope** unless required to fix build failures caused by your changes.
9. **The merge report must contain real data.** Run commands and capture actual output.
10. **Maintain the execution log continuously.** Every action, every decision, every error. No exceptions.
