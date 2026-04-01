# AgentSquad LOOP SUPER PROMPT — {{FEATURE_NAME}} Planning

## FILE LOCATIONS (READ THIS IF YOU GET LOST)

| File | Location | Purpose |
|------|----------|---------|
| **This super prompt** | `.claude/plans/loop-{{TASK_NAME}}.md` | The HOW — what to do, in what order, how to know you're done |
| **The plan document** (you write this) | `.claude/plans/{{TASK_NAME}}.md` | The WHAT — your output. A bulletproof implementation plan. |
| **Execution log** (you maintain this) | `.claude/plans/execution-log-{{TASK_NAME}}.md` | The TRACE — timestamped log of every action you take. |

**If stuck:** Re-read `.claude/plans/loop-{{TASK_NAME}}.md` to find which phase you're on.

---

## MISSION

You are designing and planning the **{{FEATURE_NAME}}** feature for {{PRODUCT_NAME}} ({{PRODUCT_DESCRIPTION}}). You will produce a **bulletproof implementation plan** — NOT code. The plan must be detailed enough that a developer can implement it without asking a single clarifying question.

### Requirements

{{PROBLEM_DESCRIPTION}}

### What Success Looks Like

A debate-hardened plan with: Changes Overview table -> numbered Changes with file paths and pseudocode -> Implementation Phases ordered by risk -> Verification Matrix.

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
- Every decision you make (what + why)
- Every debate invocation (which model was ACTUALLY used, not just requested)
- Every error or dead end
- Every commit

This is not optional. The execution log is committed alongside your work at every phase.

---

## EXECUTION ORDER

### Phase 1: Research & Architecture
**Goal:** Understand the existing codebase and design where the new feature fits.

1. Map the existing codebase areas the feature will touch:
   ```bash
   grep -r "{{RELEVANT_KEYWORDS}}" --include="*.ts" --include="*.tsx" -l
   ```
2. Read all relevant files. For each, note: what it does, what it exports, what DB tables it uses.
3. Design the feature architecture:
   - What new files/modules are needed?
   - What existing files need modification?
   - What new database tables or columns are needed?
   - What API routes are needed?
   - What UI components are needed?
4. Write the **Architecture** section in `.claude/plans/{{TASK_NAME}}.md`:
   - File Map (existing files to modify + new files to create)
   - Data Flow Diagram (text-based)
   - Database Schema changes
   - API Routes
5. **Commit:** `git add -A && git commit -m "Phase 1: Research and architecture"`

### Phase 2: Detailed Change Specification
**Goal:** Write every change as a numbered spec with file paths and pseudocode.

1. Write the **Changes Overview** table listing every change.
2. For EACH change, create a dedicated section with:
   - **File:** exact path (existing) or new file path
   - **Why:** what this change accomplishes
   - **Current Code:** what exists now (if modifying existing file)
   - **New Code:** pseudocode describing the logic — detailed enough to implement without questions
   - **Key design decisions:** why this approach
3. Add **Implementation Phases** ordered by risk with rollback steps.
4. Add **Verification Matrix** with specific test commands and pass criteria.
5. **Commit:** `git add -A && git commit -m "Phase 2: Detailed change specification"`

### Phase 3: Adversarial Debate (5 Rounds)
**Goal:** Harden the plan through 5 rounds of adversarial review.

For each round (1 through 5):
1. Invoke the debate skill. Use `/debate` for adversarial review. Choose a different model family than the one running the loop for maximum diversity of perspective.
   
   Ask the reviewer to:
   - Find holes, missed edge cases, incorrect assumptions
   - Check for security, resilience, and data integrity concerns
   - Identify changes that could introduce new bugs
   - Verify the proposed tests would actually catch regressions
2. For each issue: Accept (incorporate + log) or Reject (log with specific reason).
3. Update the plan.
4. **Commit:** `git add -A && git commit -m "Phase 3: Debate round X complete (Y accepted, Z rejected)"`

After all 5 rounds, add the Debate Provenance summary table.

### Phase 4: Final Review
**Goal:** Ensure the plan is complete and self-contained.

1. Verify ALL required sections exist (see Gate 4).
2. Check consistency: file paths, function names, line numbers all accurate.
3. Check completeness: could a developer implement this without questions?
4. **Commit:** `git add -A && git commit -m "Phase 4: Final plan complete"`

---

## ACCEPTANCE CRITERIA

Output `<promise>{{MAGIC_WORD}}</promise>` ONLY when ALL gates pass.

### Gate 1: Architecture
- [ ] All existing files the feature touches are identified
- [ ] All new files/modules are specified with their roles
- [ ] Database schema changes are documented
- [ ] Data flow is mapped end-to-end

### Gate 2: Plan Quality
- [ ] Changes Overview table exists with all changes numbered
- [ ] Every change has: file path, pseudocode, design decisions
- [ ] Implementation Phases exist ordered by risk with rollback steps
- [ ] Verification Matrix exists with specific commands and pass criteria
- [ ] NO actual implementation code — only pseudocode and descriptions

### Gate 3: Debate Rigor
- [ ] 5 debate rounds completed using `/debate` with an adversarial reviewer from a different model family
- [ ] Debate Log with accept/reject decisions and reasons
- [ ] Debate Provenance summary table
- [ ] At least 1 critical issue found and addressed

### Gate 4: Document Completeness
- [ ] All sections present: Executive Summary, Architecture, File Map, Data Flow, DB Schema, Changes Overview, numbered Changes, Implementation Phases, Verification Matrix, Debate Log, Debate Provenance, Known Follow-Ups
- [ ] No "TBD" or "TODO" placeholders remain

### Gate 5: Git Hygiene
- [ ] All work on `{{BRANCH_NAME}}`
- [ ] No commits on `main`

### Gate 6: Execution Log
- [ ] `.claude/plans/execution-log-{{TASK_NAME}}.md` exists
- [ ] Every phase has timestamped entries
- [ ] Debate rounds log the ACTUAL model used
- [ ] Dead ends and errors are documented, not just successes

---

## RULES

1. **Do NOT write implementation code.** Pseudocode and descriptions only.
2. **If lost, re-read this file.**
3. **Never commit to main.**
4. **Use `/debate` for all 5 rounds. Do not simulate. Use a different model family than the one running the loop.**
5. **Be specific.** Every finding must include exact file paths and evidence.
6. **The plan must stand alone.** A developer unfamiliar with the codebase should be able to implement it.
7. **Maintain the execution log continuously.** Every action, every decision, every dead end. No exceptions.
