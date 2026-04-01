# AgentSquad LOOP SUPER PROMPT — {{FEATURE_NAME}} Debug Investigation

## FILE LOCATIONS (READ THIS IF YOU GET LOST)

| File | Location | Purpose |
|------|----------|---------|
| **This super prompt** | `.claude/plans/loop-{{TASK_NAME}}.md` | The HOW — what to do, in what order, how to know you're done |
| **The investigation plan** (you write this) | `.claude/plans/{{TASK_NAME}}.md` | The WHAT — your output. A bulletproof, debate-hardened fix plan. |
| **Execution log** (you maintain this) | `.claude/plans/execution-log-{{TASK_NAME}}.md` | The TRACE — timestamped log of every action you take. |
| **Format reference** (optional) | `.claude/plans/{{FORMAT_REFERENCE}}` | How your final plan should look. Mirror this structure. |

**If stuck:** Re-read `.claude/plans/loop-{{TASK_NAME}}.md` to find which phase you're on.

---

## MISSION

You are investigating a broken feature in {{PRODUCT_NAME}} ({{PRODUCT_DESCRIPTION}}) and producing a **bulletproof implementation plan** to fix it. You will NOT write implementation code. Your deliverable is a plan so detailed that a developer can pick it up and implement every fix without asking a single clarifying question.

The investigation is the means. The implementation plan is the end.

### Known Problems

{{PROBLEM_DESCRIPTION}}

### What Success Looks Like

A debate-hardened plan with: Changes Overview table -> numbered Changes with file paths, line numbers, current vs. replacement pseudocode -> Implementation Phases ordered by risk -> Verification Matrix. Structured the same way as the format reference.

---

## GIT WORKFLOW (MANDATORY — DO THIS FIRST)

```bash
git checkout -b {{BRANCH_NAME}}
```

ALL work on this branch. **Never commit to main.**

---

## EXECUTION LOG (MANDATORY — CREATE BEFORE ANY OTHER WORK)

Create `.claude/plans/execution-log-{{TASK_NAME}}.md` with this header:

```markdown
# Execution Log — {{TASK_NAME}}
> Started: [current timestamp]
> Branch: {{BRANCH_NAME}}
```

**From this point forward, append every action to this file:**
- Every file you read (path + line count + what you learned)
- Every grep/search you run (query + result count)
- Every diagnostic query (query + what it revealed)
- Every decision you make (what + why)
- Every debate invocation (which model was ACTUALLY used, not just requested)
- Every error or dead end
- Every commit

This is not optional. The execution log is committed alongside your work at every phase.

---

## EXECUTION ORDER

### Phase 1: Codebase Discovery (Read Only)
**Goal:** Map the entire feature — every file, every function, every data flow.

1. Search the codebase:
   ```bash
   grep -r "{{KEYWORD_1}}" --include="*.ts" --include="*.tsx" -l
   grep -r "{{KEYWORD_2}}" --include="*.ts" --include="*.tsx" -l
   grep -r "{{KEYWORD_3}}" --include="*.ts" --include="*.tsx" -l
   ```
2. Read every relevant file. For each, note: what it does, what it exports, what DB tables it uses.
3. Map the complete data flow end-to-end.
4. Write the File Map, Data Flow Diagram, and Database Tables sections in `.claude/plans/{{TASK_NAME}}.md`.
5. **Commit:** `git add -A && git commit -m "Phase 1: Codebase discovery and data flow mapping"`

### Phase 2: Diagnostics
**Goal:** Find the root cause of each known problem with evidence.

For EACH known problem:
1. Trace the code path end-to-end (which functions, which API routes, which DB queries).
2. Run diagnostic queries against the database to gather evidence.
3. Identify the exact point of failure with file path and line numbers.
4. Document findings with evidence in `.claude/plans/{{TASK_NAME}}.md`.

Look for common failure patterns:
- Status/state mismatches between write and read paths
- Missing or incorrect filters (date, user_id, status)
- Timezone inconsistencies
- Race conditions (read before write completes)
- Response format mismatches (API shape vs frontend expectation)
- Pagination or limit issues

5. **Commit:** `git add -A && git commit -m "Phase 2: Diagnostics complete — root causes identified"`

### Phase 3: Draft the Implementation Plan
**Goal:** Write a concrete, actionable implementation plan.

1. Write the **Changes Overview** table listing every fix with: change number, description, file(s), risk level, phase.
2. For EACH change, create a dedicated section with:
   - **File:** exact path
   - **Lines:** line numbers in current code
   - **Why:** 1-2 sentences explaining the root cause
   - **Current Code:** what the code does now (pseudocode showing the logic)
   - **Replace with:** what it should do (pseudocode — NOT actual implementation, but detailed enough to implement without questions)
   - **Key design decisions:** why this approach over alternatives
3. Add **Implementation Phases** ordered by risk, each with: changes included, files affected, test command, rollback steps.
4. Add **Verification Matrix** with specific commands and binary pass/fail criteria.
5. **Commit:** `git add -A && git commit -m "Phase 3: Draft implementation plan complete"`

### Phase 4: Adversarial Debate (5 Rounds)
**Goal:** Harden the plan through 5 rounds of adversarial review.

For each round (1 through 5):
1. Invoke the debate skill. Use `/debate` for adversarial review. Choose a different model family than the one running the loop for maximum diversity of perspective.
   
   Ask the reviewer to:
   - Find holes, missed edge cases, incorrect assumptions
   - Challenge the root cause analysis — could there be a deeper issue?
   - Check for security, resilience, and data integrity concerns
   - Identify any fix that could introduce NEW bugs
   - Verify that the proposed verification steps would actually catch regressions
2. For each issue: Accept (incorporate into plan + log) or Reject (log with specific reason — "not relevant" is not acceptable).
3. Update `.claude/plans/{{TASK_NAME}}.md` with accepted improvements.
4. **Commit:** `git add -A && git commit -m "Phase 4: Debate round X complete (Y accepted, Z rejected)"`

After all 5 rounds, add the **Debate Provenance** summary table.

### Phase 5: Final Review
**Goal:** Ensure the plan is complete and self-contained.

1. Verify ALL required sections exist (see Gate 5 below).
2. Check consistency: file paths and line numbers match the actual codebase.
3. Check completeness: could a developer implement this without asking questions?
4. Write the Executive Summary (1 paragraph).
5. **Commit:** `git add -A && git commit -m "Phase 5: Final investigation plan complete"`

---

## ACCEPTANCE CRITERIA

Output `<promise>{{MAGIC_WORD}}</promise>` ONLY when ALL gates pass.

### Gate 1: Codebase Coverage
- [ ] Every file related to the feature is identified in the File Map
- [ ] Data flow mapped end-to-end
- [ ] All database tables documented with key columns

### Gate 2: Root Cause Diagnosis
- [ ] Each known problem has an identified root cause with exact file path and line numbers
- [ ] Evidence provided for each diagnosis (code references + diagnostic query results)
- [ ] The full chain for each problem is traced end-to-end

### Gate 3: Implementation Plan Quality
- [ ] Changes Overview table exists with all fixes numbered
- [ ] Every change has: file path, line numbers, current code, replacement pseudocode, design decisions
- [ ] Pseudocode detailed enough to implement without clarifying questions
- [ ] Implementation Phases ordered by risk with rollback steps
- [ ] Verification Matrix with specific commands and binary pass/fail criteria
- [ ] NO actual implementation code — only pseudocode and descriptions

### Gate 4: Debate Rigor
- [ ] 5 debate rounds completed using `/debate` with an adversarial reviewer from a different model family
- [ ] Debate Log with accept/reject decisions and specific reasons
- [ ] Debate Provenance summary table with counts per round
- [ ] At least 1 critical issue found and addressed

### Gate 5: Document Completeness
- [ ] `.claude/plans/{{TASK_NAME}}.md` contains ALL sections: Executive Summary, File Map, Data Flow Diagram, Database Tables, Analysis per problem, Changes Overview, numbered Changes, Implementation Phases, Verification Matrix, Debate Log, Debate Provenance, Known Follow-Ups
- [ ] File paths and line numbers match the actual codebase
- [ ] No "TBD" or "TODO" placeholders remain

### Gate 6: Git Hygiene
- [ ] All work on `{{BRANCH_NAME}}`
- [ ] No commits on `main`

### Gate 7: Execution Log
- [ ] `.claude/plans/execution-log-{{TASK_NAME}}.md` exists
- [ ] Every phase has timestamped entries
- [ ] Debate rounds log the ACTUAL model used
- [ ] Diagnostic queries and their results are logged
- [ ] Dead ends and errors are documented, not just successes

---

## RULES

1. **Do NOT write implementation code.** Pseudocode and descriptions only.
2. **If lost, re-read this file.**
3. **Never commit to main.**
4. **Run diagnostics fearlessly.** Read files, grep the codebase, query the database. Evidence, not guesses.
5. **Use `/debate` for all 5 rounds. Do not simulate. Use a different model family than the one running the loop.**
6. **Be specific.** Every finding must include exact file, function, line number, and evidence.
7. **Document everything.** If you investigated something and it was fine, document that too.
8. **The plan must stand alone.** A developer unfamiliar with the codebase should understand what's broken and how to fix it.
9. **Maintain the execution log continuously.** Every action, every decision, every dead end. No exceptions.
