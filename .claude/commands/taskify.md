# /taskify - Generate Task Files from GitHub Issue

Transform a GitHub issue into AgentSquad loop files for autonomous development.

## Arguments

- `$ARGUMENTS` - GitHub issue number (e.g., `124`) or full URL (e.g., `https://github.com/owner/repo/issues/124`)

## Skill Reference

**IMPORTANT**: Before generating tasks, read and apply the heuristics from:

```
@.claude/skills/plan-heuristics/SKILL.md
```

This skill file contains:

- Task scoping rules (context window sizing, atomic outcomes)
- JSON schema with required fields
- Decomposition heuristics (5-7 rule, vertical slices)
- Epic to Tasks conversion guidelines
- Validation rules

## Workflow

### Step 1: Parse the Issue Identifier

Extract the issue number from `$ARGUMENTS`:

- If it's a number, use it directly
- If it's a URL, extract the issue number from the path

### Step 2: Fetch the GitHub Issue

Use `gh` CLI to fetch the issue details:

```bash
gh issue view <issue_number> --json title,body,labels,assignees,milestone,state
```

If this is an epic (contains sub-issues), also fetch linked issues:

```bash
gh issue view <issue_number> --json body | grep -oE '#[0-9]+' | sort -u
```

For each sub-issue found, fetch its details too.

### Step 3: Check for Existing Task Session

Before generating, check if `.tasks/plan.md` already exists:

```bash
ls .tasks/plan.md 2>/dev/null
```

If it exists, STOP and ask the user:

> "A task session already exists. Do you want to:
>
> 1. Run `/cleanup` first to archive it
> 2. Overwrite the existing session
> 3. Cancel"

### Step 4: Load Skill and Decompose into Tasks

Read the skill file at `.claude/skills/plan-heuristics/SKILL.md` and apply its heuristics.

Analyze the issue body and any sub-issues to create a task list. Look for:

- Checklist items (`- [ ]` or `- [x]`)
- Acceptance criteria
- Sub-task references
- Implementation sections

Create tasks following the enhanced JSON schema:

```json
{
  "id": 1,
  "category": "setup|feature|testing|polish",
  "epic": "Epic Name from Issue Title",
  "description": "Clear description of what needs to be done",
  "steps": ["Step 1", "Step 2", "Step 3"],
  "acceptance_criteria": ["AC 1", "AC 2"],
  "depends_on": [],
  "passes": false,
  "github_issue": 132,
  "estimated_complexity": "small|medium|large"
}
```

**New Fields (Required):**

- `github_issue` - The source GitHub issue number for traceability
- `estimated_complexity` - One of: `small`, `medium`, `large`

**Complexity Guidelines:**

- `small` - 1 file, <50 LOC, no external deps
- `medium` - 2-3 files, API+UI, some integration
- `large` - 3+ files, database changes, full feature with tests

**Category Guidelines:**

- `setup` - First task, project initialization, infrastructure
- `feature` - Core functionality implementation
- `testing` - Writing tests, QA tasks
- `polish` - Documentation, cleanup, refactoring

**Dependency Rules:**

- First task has `depends_on: []`
- Subsequent tasks depend on logically prerequisite tasks
- Prefer sequential dependencies unless tasks are truly parallel

### Step 5: Validate Generated Tasks

Before generating files, validate against skill rules:

1. **Task count check**: If >7 tasks, output warning
2. **Step count check**: If any task has >7 steps, error and suggest splitting
3. **Description check**: If any description is <10 characters or vague, error
4. **Dependency check**: Verify no circular dependencies
5. **Testing check**: If no testing tasks, output warning

**Validation Output Example:**

```
Validation Results:
  Tasks generated: 6
  Total complexity: 3 small, 2 medium, 1 large

  Warnings:
    - No testing tasks generated. Consider adding test coverage.

  Errors: None

  Proceeding with generation...
```

### Step 6: Generate Task Files

Create the following files in `.tasks/`:

#### `.tasks/loop.sh`

```bash
#!/bin/bash

# loop.sh - AgentSquad Autonomous Build Loop
# =======================================
#
# Usage:
#   .tasks/loop.sh [max_iterations]

set -e

# Navigate to repo root (parent of .tasks)
cd "$(dirname "$0")/.."

# Configuration - files are in .tasks/
MAX_ITERATIONS=${1:-10}
PROMPT_FILE=".tasks/PROMPT.md"
PLAN_FILE=".tasks/plan.md"
ACTIVITY_FILE=".tasks/activity.md"
COMPLETION_SIGNAL="<promise>COMPLETE</promise>"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_dependencies() {
    if ! command -v claude &> /dev/null; then
        echo -e "${RED}Error: Claude Code CLI not found.${NC}"
        exit 1
    fi

    if [ ! -f "$PROMPT_FILE" ]; then
        echo -e "${RED}Error: $PROMPT_FILE not found.${NC}"
        exit 1
    fi

    if [ ! -f "$PLAN_FILE" ]; then
        echo -e "${RED}Error: $PLAN_FILE not found.${NC}"
        exit 1
    fi
}

log_activity() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" >> "$ACTIVITY_FILE"
}

run_loop() {
    local iteration=1

    echo -e "${BLUE}=======================================================${NC}"
    echo -e "${BLUE}           AgentSquad Autonomous Build Loop                  ${NC}"
    echo -e "${BLUE}=======================================================${NC}"
    echo -e "${BLUE}  Max iterations: ${GREEN}$MAX_ITERATIONS${NC}"
    echo -e "${BLUE}  Prompt file:    ${GREEN}$PROMPT_FILE${NC}"
    echo -e "${BLUE}  Plan file:      ${GREEN}$PLAN_FILE${NC}"
    echo -e "${BLUE}=======================================================${NC}"
    echo ""

    log_activity "=== AgentSquad Loop Started (max $MAX_ITERATIONS iterations) ==="

    while [ $iteration -le $MAX_ITERATIONS ]; do
        echo -e "${YELLOW}--- Iteration $iteration of $MAX_ITERATIONS ---${NC}"

        log_activity "--- Iteration $iteration started ---"

        local prompt_content=$(cat "$PROMPT_FILE")
        local output_file="/tmp/squad_output_$$_$iteration.txt"

        claude -p "$prompt_content" --dangerously-skip-permissions 2>&1 | tee "$output_file" || {
            echo -e "${RED}Claude exited with error${NC}"
            log_activity "ERROR: Claude exited with error"
        }

        local output=$(cat "$output_file" 2>/dev/null || echo "")
        rm -f "$output_file"

        local summary=$(echo "$output" | tail -20)
        log_activity "Output summary: $summary"

        if echo "$output" | grep -q "$COMPLETION_SIGNAL"; then
            echo ""
            echo -e "${GREEN}=======================================================${NC}"
            echo -e "${GREEN}                    BUILD COMPLETE!                      ${NC}"
            echo -e "${GREEN}=======================================================${NC}"
            log_activity "=== BUILD COMPLETE - All tasks finished ==="
            exit 0
        fi

        iteration=$((iteration + 1))

        if [ $iteration -le $MAX_ITERATIONS ]; then
            echo -e "${BLUE}Waiting 2 seconds before next iteration...${NC}"
            sleep 2
        fi
    done

    echo ""
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "${YELLOW}   Maximum iterations reached ($MAX_ITERATIONS)         ${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    log_activity "=== Loop ended - Max iterations reached ==="
}

main() {
    check_dependencies
    run_loop
}

trap 'echo -e "\n${YELLOW}Interrupted by user${NC}"; log_activity "=== Interrupted by user ==="; exit 130' INT

main
```

#### `.tasks/PROMPT.md`

Generate a prompt customized for this codebase:

````markdown
# AgentSquad Loop Iteration - Issue #<NUMBER>: <TITLE>

You are working on this project's codebase.

## Your Mission

Implement the feature/fix described in GitHub Issue #<NUMBER>.

## Context Files (Read These First)

1. **@.tasks/plan.md** - JSON task list with your current tasks. Find ONE task where `passes: false` and work on it.
2. **@.tasks/activity.md** - Session log of previous iterations. Record what you accomplish.
3. **@.claude/CLAUDE.md** - Codebase guidelines and standards (if exists)

## Issue Context

<INSERT ISSUE BODY HERE>

## Rules for This Iteration

1. **Read .tasks/plan.md first** - Understand all tasks and their status
2. **Pick ONE task** where `passes: false` (prefer tasks with satisfied dependencies)
3. **Agent Routing (CRITICAL)** - You MUST route the work to the appropriate specialist agent(s):
   - `architect`: For architecture decisions, data flow, domain-specific logic
   - `product`: For UI components, pages, forms, accessibility
   - `systems`: For APIs, background jobs, database, external integrations
   - `qa`: For writing tests (unit, E2E, integration)
   *If the task touches 1 domain, use a single subagent. If it crosses 2+ domains, spawn an Agent Team with a Lead and `qa`.*
4. **Implement the task completely** - Don't do partial work
5. **Update .tasks/plan.md** - Set `passes: true` for the completed task
6. **Log to .tasks/activity.md** - Record what you did and any issues
7. **Run verification** - Build and tests must pass
8. **When ALL tasks pass** - Output `<promise>COMPLETE</promise>` to signal done

## Tech Stack Commands

```bash
{{BUILD_CMD}}      # Verify changes compile
{{TYPECHECK_CMD}}  # Type checking (if available)
{{TEST_CMD}}       # Run tests
{{LINT_CMD}}       # Lint code
```

## Begin

1. Read @.tasks/plan.md
2. Read @.tasks/activity.md for context
3. Find a task to work on
4. Implement it
5. Update plan.md and activity.md
6. Verify with build/tests

When all tasks in plan.md have `passes: true`, output:

```
<promise>COMPLETE</promise>
```
````

#### `.tasks/plan.md`

```markdown
# Task Plan - Issue #<NUMBER>: <TITLE>

This file tracks implementation tasks for GitHub Issue #<NUMBER>.

**Source:** https://github.com/<OWNER>/<REPO>/issues/<NUMBER>
**Generated:** <TIMESTAMP>
**Estimated Total Complexity:** <SUMMARY>

## Tasks

```json
<INSERT GENERATED TASKS JSON HERE>
```

## Agent Instructions

When working on this plan:

1. **Read this file first** to understand all tasks
2. **Pick ONE task** where `passes: false` and all `depends_on` tasks have `passes: true`
3. **Implement completely** - no partial work
4. **Update this file** - set `passes: true` when done
5. **Log to activity.md** - record what you did
6. **Verify** - build and tests must pass
7. **Signal completion** - when ALL tasks pass, output `<promise>COMPLETE</promise>`

## Notes

- Tasks should be completed respecting `depends_on` order
- Set `passes: true` only when task is fully verified
- If stuck on a task for >2 iterations, add a note to activity.md
```

#### `.tasks/activity.md`

```markdown
# Activity Log - Issue #<NUMBER>

**Session started:** <CURRENT_TIMESTAMP>
**GitHub Issue:** #<NUMBER> - <TITLE>
**Source:** https://github.com/<OWNER>/<REPO>/issues/<NUMBER>

---

## Session Log

<!-- AgentSquad will append entries here during iterations -->
```

### Step 6b: Inject Agent Quality Gates into PROMPT.md

Before finalizing PROMPT.md, scan the issue's checklist items and task file patterns to determine which agent guardrails to inject. Append a `## Quality Gates` section to the generated PROMPT.md using this mapping:

| File Pattern | Agent | Guardrails to Inject |
|-------------|-------|---------------------|
| CUSTOMIZE: frontend paths | product | CUSTOMIZE: UI component guardrails |
| CUSTOMIZE: backend paths | systems | CUSTOMIZE: API/integration guardrails |
| CUSTOMIZE: test paths | qa | No real API calls in tests, mock factories used, context protection (piped output), all three states tested |
| CUSTOMIZE: architecture paths | architect | CUSTOMIZE: Architecture guardrails |

**How to apply:**
1. Look at the task descriptions and `steps` fields in `plan.md` to identify which file patterns are touched.
2. For each matching pattern, read the corresponding agent file (e.g., `.claude/agents/product.md`) and extract the "Guardrails" checklist.
3. Append the guardrails as a `## Quality Gates` markdown checklist at the end of PROMPT.md.
4. If a task touches multiple domains, include guardrails from ALL matching agents.

### Step 7: Make Script Executable

```bash
chmod +x .tasks/loop.sh
```

### Step 8: Output Success Message

After creating all files, output an enhanced summary:

```
=================================================================
  Task files generated for Issue #<NUMBER>: <TITLE>
=================================================================

Task Summary:
  Total tasks:     <N>
  By category:     <setup: X, feature: Y, testing: Z, polish: W>
  By complexity:   <small: A, medium: B, large: C>

Validation:
  <Warnings/errors or "All checks passed">

Files created:
  .tasks/loop.sh      - Loop script (executable)
  .tasks/PROMPT.md    - Iteration instructions
  .tasks/plan.md      - Task list (<N> tasks)
  .tasks/activity.md  - Session log

To start the autonomous loop:
  .tasks/loop.sh 20

To run a single iteration manually:
  claude -p "$(cat .tasks/PROMPT.md)" --dangerously-skip-permissions

When complete, archive the session:
  /cleanup
```

## Error Handling

- If `gh` is not installed, tell the user to install GitHub CLI
- If the issue doesn't exist, report the error clearly
- If the issue has no actionable content, suggest the user add more detail
- If validation fails with errors, do not generate files

## Example

```
User: /taskify 132

Claude:
1. Fetching GitHub issue #132...
2. Found: "Add user authentication feature"
3. Loading skill from .claude/skills/plan-heuristics/SKILL.md...
4. Decomposing into tasks...

Validation Results:
  Tasks generated: 5
  By category:     setup: 1, feature: 3, polish: 1
  By complexity:   small: 2, medium: 2, large: 1

  Warnings: None
  Errors: None

5. Generating .tasks/ files...

=================================================================
  Task files generated for Issue #132
=================================================================

Task Summary:
  Total tasks:     5
  By category:     setup: 1, feature: 3, polish: 1
  By complexity:   small: 2, medium: 2, large: 1

Files created:
  .tasks/loop.sh      - Loop script (executable)
  .tasks/PROMPT.md    - Iteration instructions
  .tasks/plan.md      - Task list (5 tasks)
  .tasks/activity.md  - Session log

To start the autonomous loop:
  .tasks/loop.sh 20
```
