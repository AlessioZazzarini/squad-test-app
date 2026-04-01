# AgentSquad Loop Framework — Reusable Templates for Autonomous Claude Code

## Prerequisites

Before launching ANY AgentSquad loop:

```bash
# Use the squadmode alias (sets AGENTSQUAD_LOOP_ENABLED=1 + --dangerously-skip-permissions)
squadmode
```

**Without this alias, the stop hook is inactive and AgentSquad cannot loop.**

To add the alias to your shell:
```bash
alias squadmode='cd ~/projects/YOUR_PROJECT && AGENTSQUAD_LOOP_ENABLED=1 claude --dangerously-skip-permissions'
```

To stop: `Ctrl+C Ctrl+C` kills Claude. `/loop-cancel` stops only the loop.

---

## Three Task Types

| Task | When to use | Output | Template HOW | Template WHAT |
|------|------------|--------|-------------|---------------|
| **Plan** | Design a new feature from scratch | Debate-hardened implementation plan (no code) | `loop-plan.md` | `skeleton-plan.md` |
| **Implement** | Execute an existing plan | Working code on a feature branch + merge report | `loop-implement.md` | `skeleton-implement.md` |
| **Debug** | Investigate & fix a broken feature | Root cause analysis + debate-hardened fix plan (no code) | `loop-debug.md` | `skeleton-debug.md` |

**Debate model:** Plan and Debug tasks include adversarial debate rounds. Use `/debate` for adversarial review. Choose a different model family than the one running the loop to maximize diversity of perspective.

---

## How to Use

### Step 1: Pick your task type
Decide: Am I planning, implementing, or debugging?

### Step 2: Copy templates
```bash
# Example for a debug task:
cp .claude/templates/loop-debug.md .claude/plans/loop-{{TASK_NAME}}.md
cp .claude/templates/skeleton-debug.md .claude/plans/{{TASK_NAME}}.md
```

### Step 3: Fill in variables
Open the copied HOW file and replace all `{{VARIABLES}}`:

| Variable | Description | Example |
|----------|------------|---------|
| `{{TASK_NAME}}` | Short kebab-case name | `auth-flow-fix` |
| `{{FEATURE_NAME}}` | Human-readable feature name | `Authentication Flow` |
| `{{PRODUCT_NAME}}` | Product name | `MyApp` |
| `{{PRODUCT_DESCRIPTION}}` | One-line product description | `SaaS dashboard for analytics` |
| `{{BRANCH_NAME}}` | Git branch name | `feat/auth-flow-fix` |
| `{{MAGIC_WORD}}` | Completion promise phrase | `the plan is forged` |
| `{{MAX_ITERATIONS}}` | Max AgentSquad loop iterations | `15` or `30` |
| `{{PROBLEM_DESCRIPTION}}` | What needs to be done (bullet points) | The specific problems or requirements |
| `{{PLAN_FILE_PATH}}` | Path to the existing plan (implement only) | `.claude/plans/auth-flow.md` |

### Step 4: Launch

Each template includes a ready-to-paste launch command at the bottom. Copy it, fill in the paths, and paste into Claude Code.

---

## Iteration Budget Guidelines

| Task Type | Typical Iterations | Recommended Max |
|-----------|-------------------|----------------|
| **Plan** | 8-12 | 15 |
| **Implement** | 15-25 | 30 |
| **Debug** | 8-12 | 15 |

---

## Folder Structure

```
.claude/
├── plans/                          <- Active plans and loop prompts
│   ├── loop-{{task}}.md            <- HOW file (copied from template, filled in)
│   ├── {{task}}.md                 <- WHAT file (copied from template, filled in)
│   └── execution-log-{{task}}.md   <- TRACE file (created automatically by the loop)
├── templates/                      <- Reusable templates (never edit directly)
│   ├── FRAMEWORK.md                <- This file
│   ├── loop-plan.md                <- HOW template: planning
│   ├── loop-implement.md           <- HOW template: implementation
│   ├── loop-debug.md               <- HOW template: debugging
│   ├── skeleton-plan.md            <- WHAT template: planning output
│   ├── skeleton-implement.md       <- WHAT template: implementation output
│   └── skeleton-debug.md           <- WHAT template: debug investigation output
```

---

## The Three-File System

Every AgentSquad loop uses exactly three files:

1. **The HOW file** (`loop-*.md`) — Execution instructions, phases, acceptance gates, completion promise. Tells the loop WHAT TO DO and in WHAT ORDER.

2. **The WHAT file** (`skeleton-*.md` -> copied to `plans/`) — The output document. Either a plan or a merge report. Tells the loop WHAT TO PRODUCE.

3. **The EXECUTION LOG** (`execution-log-{{task}}.md`) — A timestamped trace of every action taken during the loop. Created at loop start, appended to throughout. Tells the human WHAT HAPPENED.

The HOW always references the WHAT and the LOG. If a format reference exists (e.g., a previous plan to mirror), the HOW references that too.

### Execution Log Format

The execution log is a simple append-only markdown file. Every entry has a timestamp and a clear description of what was done. Example:

```markdown
# Execution Log — {{TASK_NAME}}

## Phase 1: Research & Architecture
- [HH:MM] Started Phase 1
- [HH:MM] Ran grep for keywords: buildPrompt, strategyContext — found 12 files
- [HH:MM] Read src/lib/services/pipeline.ts (1200 lines) — main pipeline, handles scoring + generation
- [HH:MM] Read src/lib/ai/prompts.ts (350 lines) — builds system + user prompts
- [HH:MM] Found: referenced data is fetched but never used for context enrichment
- [HH:MM] Wrote Architecture section in plan
- [HH:MM] Committed: "Phase 1: Research and architecture"
```

**Rules for the execution log:**
- Create it FIRST, before any other work
- Append to it CONTINUOUSLY — every file read, every grep, every decision, every debate invocation
- Include the ACTUAL model used for debate rounds (not just what was requested)
- Log errors and dead ends, not just successes
- Commit it alongside other work at every phase commit

---

## Launch Command Templates

### Plan a New Feature
```bash
/loop-start "You have two instruction files. Read the first one before doing anything.

1. .claude/plans/loop-{{TASK_NAME}}.md — the HOW.
2. .claude/plans/{{TASK_NAME}}.md — the WHAT. A skeleton you will populate.

Start by reading the HOW file top to bottom. Then execute each phase.

If you get stuck: re-read the HOW file.
Use /debate for all adversarial review rounds. Do not simulate or skip debates.

Begin now." --completion-promise "{{MAGIC_WORD}}" --max-iterations 15
```

### Implement an Existing Plan
```bash
/loop-start "You have two instruction files. Read BOTH before writing any code.

1. .claude/plans/loop-{{TASK_NAME}}.md — the HOW. Execution order, git workflow, tests, acceptance gates.
2. .claude/plans/{{PLAN_FILE_PATH}} — the WHAT. Every code change, line by line.

Start by reading the HOW file top to bottom. Then for each phase, read the corresponding Change sections in the plan and implement them exactly.

If you get stuck on WHICH PHASE: re-read the HOW file.
If you get stuck on WHAT CODE TO WRITE: re-read the plan.

Begin now." --completion-promise "{{MAGIC_WORD}}" --max-iterations 30
```

### Debug / Investigate a Bug
```bash
/loop-start "You have two instruction files. Read the first one before doing anything.

1. .claude/plans/loop-{{TASK_NAME}}.md — the HOW.
2. .claude/plans/{{TASK_NAME}}.md — the WHAT. A skeleton you will populate with findings and a fix plan.

Start by reading the HOW file top to bottom. Then execute each phase.

If you get stuck on WHAT TO DO NEXT: re-read the HOW file.
If you get stuck on WHAT FORMAT TO USE: check the format reference mentioned in the HOW file.
Use /debate for all adversarial review rounds. Do not simulate or skip debates.

Begin now." --completion-promise "{{MAGIC_WORD}}" --max-iterations 15
```
