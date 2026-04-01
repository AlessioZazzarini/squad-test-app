# Task Plan Generator Skill

This skill provides the heuristics and schema for decomposing GitHub Issues (Epics) into AgentSquad-compatible task lists for autonomous development.

## Task Scoping Rules

### Context Window Sizing

Each task should be completable within a single Claude iteration (~100k tokens of context):

- **Small tasks** (~30 min work): Single file changes, simple function implementations
- **Medium tasks** (~1-2 hours work): Multi-file changes, API endpoint + component
- **Large tasks** (~half day work): Feature slice with tests, max scope for one iteration

### Atomic Outcomes

Each task must have a **verifiable atomic outcome**:

- A test passes that didn't before
- A build succeeds with new functionality
- A component renders correctly
- An API endpoint returns expected data

**Bad example**: "Work on authentication" (no clear end state)
**Good example**: "Create login API endpoint that validates credentials and returns JWT"

## Task JSON Schema

```json
{
  "id": 1,
  "category": "setup | feature | testing | polish",
  "epic": "Epic Name from Issue Title",
  "description": "Clear, actionable description of what to implement",
  "steps": ["Step 1: Create file X", "Step 2: Implement function Y", "Step 3: Export from index"],
  "acceptance_criteria": [
    "AC 1: Function returns expected output",
    "AC 2: Build compiles without errors"
  ],
  "depends_on": [],
  "passes": false,
  "github_issue": 132,
  "estimated_complexity": "small | medium | large"
}
```

### Field Definitions

| Field                  | Required | Description                                        |
| ---------------------- | -------- | -------------------------------------------------- |
| `id`                   | Yes      | Sequential task ID starting at 1                   |
| `category`             | Yes      | Task type: `setup`, `feature`, `testing`, `polish` |
| `epic`                 | Yes      | Parent epic name (from issue title)                |
| `description`          | Yes      | One sentence describing the task outcome           |
| `steps`                | Yes      | 3-7 concrete implementation steps                  |
| `acceptance_criteria`  | Yes      | Testable conditions that define "done"             |
| `depends_on`           | Yes      | Array of task IDs that must complete first         |
| `passes`               | Yes      | Boolean, starts `false`, set `true` when complete  |
| `github_issue`         | Yes      | Source GitHub issue number for traceability        |
| `estimated_complexity` | Yes      | `small`, `medium`, or `large`                      |

### Category Guidelines

- **`setup`** - Project/module initialization, infrastructure, config
- **`feature`** - Core functionality, business logic, API endpoints
- **`testing`** - Unit tests, integration tests, E2E tests
- **`polish`** - Documentation, refactoring, cleanup, optimization

## Decomposition Heuristics

### The 5-7 Rule

- **Ideal task count**: 5-7 tasks per issue
- **Maximum steps per task**: 7 (if more, split the task)
- **Maximum files per task**: 3 (prefer vertical slices)

### Vertical Slice Decomposition

Prefer thin vertical slices over horizontal layers:

```
GOOD (Vertical Slice):
Task 1: Create user registration endpoint (API + validation)
Task 2: Create registration form component (UI + state)
Task 3: Connect form to API with error handling

BAD (Horizontal Layers):
Task 1: Create all API endpoints
Task 2: Create all UI components
Task 3: Wire everything together
```

### Dependency Management

- **First task** always has `depends_on: []`
- **Prefer sequential** dependencies unless truly parallelizable
- **Maximum dependency depth**: 3 (avoid long chains)
- **No circular dependencies** (validate before generating)

### Complexity Estimation

| Complexity | Characteristics                     | Example                         |
| ---------- | ----------------------------------- | ------------------------------- |
| `small`    | 1 file, <50 LOC, no external deps   | Add utility function            |
| `medium`   | 2-3 files, API+UI, some integration | New API endpoint with component |
| `large`    | 3+ files, database changes, testing | Full feature with migrations    |

## Epic to Tasks Conversion Guidelines

### Step 1: Parse Issue Content

Look for structured content in the issue:

1. **Checkboxes** (`- [ ]` or `- [x]`) - Direct task candidates
2. **Acceptance Criteria** section - Validation requirements
3. **Sub-issues** (linked `#123` references) - May need to fetch
4. **Implementation sections** - Technical guidance

### Step 2: Identify Natural Boundaries

Split work at natural boundaries:

- **API vs UI** - Backend and frontend as separate tasks
- **Schema vs Logic** - Database changes before business logic
- **Core vs Edge** - Happy path before error handling
- **Create vs Update** - New functionality before modifications

### Step 3: Order by Dependencies

1. **Setup/infrastructure** first
2. **Core feature** implementation next
3. **Integration/wiring** after components exist
4. **Testing** after implementation
5. **Polish/docs** last

### Step 4: Validate Task Quality

Before finalizing, check each task:

- [ ] Has clear, actionable description?
- [ ] Steps are concrete (not vague)?
- [ ] Acceptance criteria are testable?
- [ ] Complexity estimate is reasonable?
- [ ] Dependencies are correct?

## plan.md Template

````markdown
# Task Plan - Issue #{{ISSUE_NUMBER}}: {{ISSUE_TITLE}}

This file tracks implementation tasks for GitHub Issue #{{ISSUE_NUMBER}}.

**Source:** https://github.com/{{OWNER}}/{{REPO}}/issues/{{ISSUE_NUMBER}}
**Generated:** {{TIMESTAMP}}
**Estimated Total Complexity:** {{TOTAL_COMPLEXITY}}

## Tasks

```json
[
  {
    "id": 1,
    "category": "setup",
    "epic": "{{ISSUE_TITLE}}",
    "description": "...",
    "steps": ["...", "...", "..."],
    "acceptance_criteria": ["...", "..."],
    "depends_on": [],
    "passes": false,
    "github_issue": {{ISSUE_NUMBER}},
    "estimated_complexity": "small"
  }
]
```
````

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

## Validation Rules

Before generating plan.md, validate:

1. **Task count**: Warn if >7 tasks (consider splitting issue)
2. **Step count**: Error if any task has >7 steps
3. **Descriptions**: Error if description is <10 characters
4. **Dependencies**: Error if circular or invalid references
5. **Completeness**: Warn if no testing tasks included

## Error Messages

| Condition | Message |
|-----------|---------|
| >7 tasks | "Warning: {{N}} tasks generated. Consider splitting into multiple issues for better iteration control." |
| >7 steps | "Error: Task #{{ID}} has {{N}} steps. Maximum is 7. Please split this task." |
| No tests | "Warning: No testing tasks generated. Consider adding test coverage tasks." |
| Vague description | "Error: Task #{{ID}} description is too vague. Be specific about the outcome." |
