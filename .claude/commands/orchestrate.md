# /orchestrate - Orchestrate Multiple GitHub Issues Through AgentSquad Loop

Process multiple GitHub issues labeled `squad:ready` through the complete AgentSquad loop automatically, creating feature branches and PRs for each.

## Arguments

- `$ARGUMENTS` - Optional flags:
  - `--label <label>` - Label to filter issues (default: `squad:ready`)
  - `--dry-run` - Analyze and plan but don't generate execution script
  - `--max <N>` - Maximum issues to process (default: no limit)
  - `--init` - Only create labels, don't process any issues (useful for bootstrapping new repos)

## Architecture Overview

This command has been refactored to avoid **context rot** and **context overflow decay**. Instead of maintaining Claude context throughout the entire orchestration loop, the command now:

1. **Triages** (Claude) - Fetches issues, analyzes dependencies, builds execution order, generates manifest
2. **Generates Bash Script** (Claude) - Creates `squad-orchestrate.sh` that drives the outer loop
3. **Execution** (Bash + Fresh Claude Sessions) - User runs the generated script, which invokes fresh Claude sessions per issue

```
+---------------------------------------------------------+
|                    /orchestrate                          |
|                   (Claude Code Session #1)               |
+---------------------------------------------------------+
|  Phase 1: TRIAGE                                         |
|  +- Fetch open issues with target label                  |
|  +- Parse explicit dependencies (depends-on: #N)         |
|  +- Topological sort into execution order                |
|  +- Generate .tasks/orchestration-manifest.json          |
|  +- Apply 'squad:queued' labels                          |
|                                                          |
|  Phase 2: SCRIPT GENERATION                              |
|  +- Generate .tasks/squad-orchestrate.sh                 |
|  +- Output instructions for running the script           |
+---------------------------------------------------------+
                           |
+---------------------------------------------------------+
|                 squad-orchestrate.sh                     |
|                   (Pure Bash Script)                     |
+---------------------------------------------------------+
|  For each issue in priority order:                       |
|  +- Check dependencies met (read manifest)               |
|  +- Create feature branch: squad/issue-<N>               |
|  +- claude -p "/taskify <N>"  <- Fresh Claude Session    |
|  +- .tasks/loop.sh 20         <- Fresh Claude Sessions   |
|  +- Commit, push, create PR (gh CLI)                     |
|  +- claude -p "/cleanup"      <- Fresh Claude Session    |
|  +- Update labels, manifest state                        |
|                                                          |
|  On Failure:                                             |
|  +- Mark issue as squad:failed                           |
|  +- Skip dependent issues                                |
|  +- Continue with independent issues                     |
+---------------------------------------------------------+
```

### Key Benefits

| Before (Context Rot) | After (Fresh Sessions) |
|----------------------|------------------------|
| Single Claude session for all issues | Fresh Claude session per issue |
| Context degrades over time | Clean slate for each issue |
| Single point of failure stops all | Graceful continuation on failure |
| No resume capability | Auto-resume from manifest state |
| Inline execution | Bash script drives orchestration |

---

## Workflow

### Phase 1: TRIAGE

#### Step 1.1: Parse Arguments

```bash
# Defaults
LABEL="squad:ready"
DRY_RUN=false
MAX_ISSUES=""

# Parse $ARGUMENTS for flags
```

#### Step 1.2: Pre-flight Checks

Before anything else, verify the environment is ready:

```bash
# 1. Check git working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: Git working directory is not clean. Commit or stash changes first."
    exit 1
fi

# 2. Check we're on main/master
current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
    echo "WARNING: Not on main/master branch. Currently on: $current_branch"
    # Ask user to confirm or switch
fi

# 3. Check no existing task session
if [ -f ".tasks/plan.md" ]; then
    echo "ERROR: Active task session exists. Run /cleanup first."
    exit 1
fi

# 4. Check gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI (gh) not installed."
    exit 1
fi

# 5. Check required labels exist (create if missing)
```

#### Step 1.3: Ensure Required Labels Exist (CRITICAL)

**YOU MUST** create the orchestration labels if they don't exist. This is critical for scaffolding where repos start without these labels.

Run these commands to create/update labels (the `--force` flag makes this idempotent - safe to run on repos that already have the labels):

```bash
gh label create "squad:ready" --color "0E8A16" --description "Ready for AgentSquad orchestration" --force
gh label create "squad:queued" --color "FBCA04" --description "In the AgentSquad orchestration queue" --force
gh label create "squad:in-progress" --color "1D76DB" --description "Currently being processed by AgentSquad" --force
gh label create "squad:complete" --color "6F42C1" --description "Successfully processed by AgentSquad" --force
gh label create "squad:failed" --color "D93F0B" --description "AgentSquad processing failed" --force
```

Report the result:
```
Labels ensured:
  + squad:ready
  + squad:queued
  + squad:in-progress
  + squad:complete
  + squad:failed
```

If any label creation fails (e.g., no repo write access), report the error and stop.

**If `--init` flag was provided**, stop here after creating labels:

```
=================================================================
           AgentSquad Orchestration - Initialized
=================================================================

Labels created/verified:
  + squad:ready        - Add this to issues ready for processing
  + squad:queued       - Applied when issue enters the queue
  + squad:in-progress  - Applied during processing
  + squad:complete     - Applied when PR is created
  + squad:failed       - Applied if processing fails

Next steps:
  1. Add 'squad:ready' label to issues you want to process
  2. Add 'depends-on: #N' in issue bodies to declare dependencies
  3. Run '/orchestrate' to process them
```

#### Step 1.4: Fetch Issues with Target Label

```bash
gh issue list --label "$LABEL" --state open --json number,title,body,labels --limit 100
```

If no issues found, report and exit:

```
No issues found with label 'squad:ready'.

To prepare issues for orchestration:
1. Add the 'squad:ready' label to issues you want processed
2. Add 'depends-on: #N' in the issue body to declare dependencies
3. Run /orchestrate again
```

#### Step 1.5: Parse Dependencies

For each issue, extract dependencies from the body:

- Pattern: `depends-on: #N` or `blocked-by: #N` (case insensitive)
- Also check for `Depends on #N` or `Blocked by #N` in prose

```javascript
// Regex patterns to find dependencies
const patterns = [
    /depends[- ]?on:?\s*#(\d+)/gi,
    /blocked[- ]?by:?\s*#(\d+)/gi,
];
```

#### Step 1.6: Build Dependency Graph and Topological Sort

Create a directed graph where edges point from dependencies to dependents. Then topological sort to get execution order.

If circular dependencies detected, STOP and report:

```
ERROR: Circular dependency detected!

Issue #42 depends on #45
Issue #45 depends on #42

Please resolve the circular dependency before running orchestration.
```

#### Step 1.7: Generate Orchestration Manifest

Create `.tasks/orchestration-manifest.json`:

```json
{
  "created_at": "2025-01-23T10:00:00Z",
  "updated_at": "2025-01-23T10:00:00Z",
  "status": "pending",
  "source_branch": "main",
  "label_filter": "squad:ready",
  "issues": [
    {
      "number": 42,
      "title": "Issue title",
      "priority": 1,
      "dependencies": [],
      "status": "queued",
      "branch": null,
      "pr_number": null,
      "started_at": null,
      "completed_at": null,
      "error": null
    },
    {
      "number": 45,
      "title": "Another issue",
      "priority": 2,
      "dependencies": [42],
      "status": "queued",
      "branch": null,
      "pr_number": null,
      "started_at": null,
      "completed_at": null,
      "error": null
    }
  ]
}
```

#### Step 1.8: Apply Queued Labels

For each issue in the queue, update its label:

```bash
for issue in issues; do
    gh issue edit $issue --remove-label "squad:ready" --add-label "squad:queued"
done
```

#### Step 1.9: Report Triage Results

```
=================================================================
           AgentSquad Orchestration - Triage Complete
=================================================================

Issues found: 3
Execution order:
  1. #42 - Add user authentication (no dependencies)
  2. #45 - Add profile page (depends on #42)
  3. #48 - Add settings page (depends on #42)

Manifest saved to: .tasks/orchestration-manifest.json

[If --dry-run]: Dry run complete. No changes made.
[If not dry-run]: Generating execution script...
```

If `--dry-run`, stop here without generating the script.

---

### Phase 2: SCRIPT GENERATION

#### Step 2.1: Generate the Orchestration Script

Create `.tasks/squad-orchestrate.sh` with the following content. **IMPORTANT**: Generate this file exactly as specified - it contains all the logic for the outer loop.

```bash
#!/bin/bash
# squad-orchestrate.sh - Generated by /orchestrate
# Processes GitHub issues through AgentSquad loop with fresh Claude sessions
#
# Usage: ./squad-orchestrate.sh [max_iterations_per_issue]
#   max_iterations_per_issue: Number of iterations for loop.sh (default: 20)
#
# This script auto-resumes from manifest state. Safe to interrupt and restart.

set -o pipefail

MANIFEST_FILE=".tasks/orchestration-manifest.json"
LOG_FILE=".tasks/orchestration.log"
MAX_LOOP_ITERATIONS="${1:-20}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure .tasks directory exists
mkdir -p .tasks

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

log_section() {
    log ""
    log "${BLUE}================================================================${NC}"
    log "${BLUE}  $1${NC}"
    log "${BLUE}================================================================${NC}"
}

# Update a field in the manifest for a specific issue
update_manifest_issue() {
    local issue=$1
    local field=$2
    local value=$3

    local tmp_file="${MANIFEST_FILE}.tmp"
    jq --argjson num "$issue" --arg field "$field" --argjson value "$value" \
       '(.issues[] | select(.number == $num))[$field] = $value' \
       "$MANIFEST_FILE" > "$tmp_file" && mv "$tmp_file" "$MANIFEST_FILE"
}

# Update manifest status field
update_manifest_status() {
    local status=$1
    local tmp_file="${MANIFEST_FILE}.tmp"
    jq --arg status "$status" '.status = $status | .updated_at = now | todate' \
       "$MANIFEST_FILE" > "$tmp_file" && mv "$tmp_file" "$MANIFEST_FILE"
}

# Set issue status with timestamp
set_issue_status() {
    local issue=$1
    local status=$2

    update_manifest_issue "$issue" "status" "\"$status\""

    if [[ "$status" == "in_progress" ]]; then
        update_manifest_issue "$issue" "started_at" "\"$(date -Iseconds)\""
    elif [[ "$status" == "complete" || "$status" == "failed" || "$status" == "skipped" ]]; then
        update_manifest_issue "$issue" "completed_at" "\"$(date -Iseconds)\""
    fi
}

# Check if all dependencies for an issue are complete
# Returns 0 if all deps met, 1 if blocked (echoes blocking issue number)
dependencies_met() {
    local issue=$1
    local deps
    deps=$(jq -r --argjson num "$issue" \
        '(.issues[] | select(.number == $num)).dependencies // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)

    for dep in $deps; do
        [[ -z "$dep" ]] && continue
        local dep_status
        dep_status=$(jq -r --argjson num "$dep" \
            '(.issues[] | select(.number == $num)).status // "unknown"' "$MANIFEST_FILE")

        if [[ "$dep_status" != "complete" ]]; then
            echo "$dep"  # Return the blocking issue number
            return 1
        fi
    done
    return 0  # All dependencies met
}

# Process a single issue through the complete AgentSquad loop
process_issue() {
    local issue=$1
    local title=$2

    log_section "Processing Issue #$issue: $title"

    # Check dependencies
    local blocker
    if ! blocker=$(dependencies_met "$issue"); then
        log "${YELLOW}>>  Skipping #$issue - blocked by #$blocker (not complete)${NC}"
        set_issue_status "$issue" "skipped"
        update_manifest_issue "$issue" "error" "\"Blocked by #$blocker\""
        return 2  # Skipped, not failed
    fi

    set_issue_status "$issue" "in_progress"
    gh issue edit "$issue" --remove-label "squad:queued" --add-label "squad:in-progress" 2>/dev/null || true

    # Ensure we're on main and up to date
    # NOTE: Do NOT use git stash/pop here. .tasks/ is in .gitignore so the manifest
    # doesn't need stashing, and stash pop can reintroduce merge conflicts from
    # stale stash entries left by previous orchestration runs.
    log "Checking out main branch..."
    git reset --mixed HEAD 2>/dev/null || true
    git checkout main || { log "${RED}x Failed to checkout main${NC}"; return 1; }
    git reset --mixed HEAD 2>/dev/null || true
    git pull origin main || { log "${RED}x Failed to pull main${NC}"; return 1; }

    # Create feature branch
    local branch_name="squad/issue-$issue"
    log "Creating feature branch: $branch_name"
    git checkout -b "$branch_name" || {
        # Branch might already exist from a previous failed run
        log "${YELLOW}Branch exists, checking out...${NC}"
        git checkout "$branch_name" || { log "${RED}x Failed to checkout branch${NC}"; return 1; }
    }

    # Invoke fresh Claude session for taskify
    log ""
    log "${CYAN}Running /taskify $issue (fresh Claude session)...${NC}"
    if ! claude -p "/taskify $issue" --dangerously-skip-permissions; then
        log "${RED}x Taskify failed for #$issue${NC}"
        handle_failure "$issue" "Taskify failed"
        return 1
    fi

    # Run the inner AgentSquad loop
    log ""
    log "${CYAN}Running loop.sh with $MAX_LOOP_ITERATIONS iterations...${NC}"
    if [[ ! -x ".tasks/loop.sh" ]]; then
        log "${RED}x .tasks/loop.sh not found or not executable${NC}"
        handle_failure "$issue" "loop.sh not found"
        return 1
    fi

    if ! .tasks/loop.sh "$MAX_LOOP_ITERATIONS"; then
        log "${RED}x AgentSquad loop failed for #$issue${NC}"
        handle_failure "$issue" "AgentSquad loop failed after $MAX_LOOP_ITERATIONS iterations"
        return 1
    fi

    # Commit and push changes
    log ""
    log "Committing and pushing changes..."
    git add -A

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log "${YELLOW}No changes to commit${NC}"
    else
        git commit -m "feat(#$issue): $title

Implemented via AgentSquad autonomous build loop.

Co-authored-by: Claude <noreply@anthropic.com>" || {
            log "${RED}x Commit failed${NC}"
            handle_failure "$issue" "Git commit failed"
            return 1
        }
    fi

    git push -u origin "$branch_name" || {
        log "${RED}x Push failed${NC}"
        handle_failure "$issue" "Git push failed"
        return 1
    }

    # Create pull request
    log ""
    log "Creating pull request..."
    local pr_url
    pr_url=$(gh pr create \
        --title "feat(#$issue): $title" \
        --body "## Summary

Automated implementation of #$issue via AgentSquad orchestration.

## Related Issues

Closes #$issue

---
*Generated by AgentSquad Orchestrator*" 2>&1) || {
        # PR might already exist
        if echo "$pr_url" | grep -q "already exists"; then
            log "${YELLOW}PR already exists for this branch${NC}"
            pr_url=$(gh pr view "$branch_name" --json url --jq '.url' 2>/dev/null) || true
        else
            log "${RED}x PR creation failed: $pr_url${NC}"
            handle_failure "$issue" "PR creation failed"
            return 1
        fi
    }

    # Extract PR number from URL (format: .../pull/123)
    local pr_number
    pr_number=$(echo "$pr_url" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || true)

    if [[ -n "$pr_number" ]]; then
        update_manifest_issue "$issue" "pr_number" "$pr_number"
        log "${GREEN}+ Created PR #$pr_number: $pr_url${NC}"
    fi

    update_manifest_issue "$issue" "branch" "\"$branch_name\""

    # Run cleanup (archive task files) - fresh Claude session
    log ""
    log "${CYAN}Running /cleanup (fresh Claude session)...${NC}"
    claude -p "/cleanup --no-close" --dangerously-skip-permissions 2>/dev/null || {
        log "${YELLOW}Cleanup had issues, but continuing...${NC}"
    }

    # Update labels and status
    set_issue_status "$issue" "complete"
    gh issue edit "$issue" --remove-label "squad:in-progress" --add-label "squad:complete" 2>/dev/null || true

    log ""
    log "${GREEN}================================================================${NC}"
    log "${GREEN}  + Successfully completed #$issue -> PR #${pr_number:-unknown}${NC}"
    log "${GREEN}================================================================${NC}"

    # Return to main for next issue
    git reset --mixed HEAD 2>/dev/null || true
    git checkout main || true

    return 0
}

# Handle failure for an issue
handle_failure() {
    local issue=$1
    local error_msg=$2

    set_issue_status "$issue" "failed"
    update_manifest_issue "$issue" "error" "\"$error_msg\""

    gh issue edit "$issue" --remove-label "squad:in-progress" --add-label "squad:failed" 2>/dev/null || true
    gh issue comment "$issue" --body "**AgentSquad orchestration failed**

Error: $error_msg

Check the orchestration log at \`.tasks/orchestration.log\` for details.

To retry:
1. Fix any issues manually
2. Remove the \`squad:failed\` label and add \`squad:ready\`
3. Run \`/orchestrate\` again" 2>/dev/null || true

    # Return to main branch
    git reset --mixed HEAD 2>/dev/null || true
    git checkout main 2>/dev/null || true
}

# Main execution
main() {
    # Check manifest exists
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo -e "${RED}Error: $MANIFEST_FILE not found.${NC}"
        echo "Run /orchestrate first to generate the manifest and this script."
        exit 1
    fi

    log ""
    log "${BLUE}=================================================================${NC}"
    log "${BLUE}          AgentSquad Orchestration - Starting                          ${NC}"
    log "${BLUE}=================================================================${NC}"
    log ""
    log "Manifest: $MANIFEST_FILE"
    log "Max iterations per issue: $MAX_LOOP_ITERATIONS"
    log ""

    update_manifest_status "in_progress"

    # Get issues in priority order, filter to incomplete only (queued or pending)
    local issues
    issues=$(jq -r '.issues | sort_by(.priority) | .[] |
        select(.status == "queued" or .status == "pending") |
        "\(.number)|\(.title)"' "$MANIFEST_FILE")

    if [[ -z "$issues" ]]; then
        log "${GREEN}All issues already processed!${NC}"
        log ""
        log "Summary from manifest:"
        jq -r '.issues[] | "  \(if .status == "complete" then "+" elif .status == "failed" then "x" elif .status == "skipped" then ">>" else "o" end) #\(.number) - \(.title) [\(.status)]"' "$MANIFEST_FILE"
        exit 0
    fi

    local total=0
    local completed=0
    local failed=0
    local skipped=0

    # Count total issues to process
    total=$(echo "$issues" | grep -c '^' || echo 0)
    log "Issues to process: $total"
    log ""

    # Process each issue
    while IFS='|' read -r number title; do
        [[ -z "$number" ]] && continue

        process_issue "$number" "$title"
        local result=$?

        case $result in
            0) ((completed++)) ;;
            1) ((failed++)) ;;
            2) ((skipped++)) ;;
        esac

        log ""
    done <<< "$issues"

    # Final summary
    log ""
    log "${BLUE}=================================================================${NC}"
    log "${BLUE}          AgentSquad Orchestration - Complete                          ${NC}"
    log "${BLUE}=================================================================${NC}"
    log ""
    log "Results:"
    log "  ${GREEN}+ Completed: $completed${NC}"
    log "  ${RED}x Failed: $failed${NC}"
    log "  ${YELLOW}>> Skipped: $skipped${NC}"
    log ""

    # Show full summary
    log "Issue Summary:"
    jq -r '.issues | sort_by(.priority) | .[] |
        "  \(if .status == "complete" then "+" elif .status == "failed" then "x" elif .status == "skipped" then ">>" else "o" end) #\(.number) - \(.title)\(if .pr_number then " -> PR #\(.pr_number)" else "" end)\(if .error then " (\(.error))" else "" end)"' "$MANIFEST_FILE"

    if [[ $failed -gt 0 ]]; then
        update_manifest_status "failed"
        log ""
        log "${YELLOW}Some issues failed. To retry:${NC}"
        log "  1. Fix the issues manually or investigate the logs"
        log "  2. Remove 'squad:failed' label and add 'squad:ready'"
        log "  3. Run /orchestrate again"
        exit 1
    elif [[ $skipped -gt 0 && $completed -eq 0 ]]; then
        update_manifest_status "blocked"
        log ""
        log "${YELLOW}All remaining issues are blocked by failed dependencies.${NC}"
        exit 1
    else
        update_manifest_status "complete"
        log ""
        log "${GREEN}All issues processed successfully!${NC}"
        log "PRs are ready for review."
    fi
}

# Handle interrupts gracefully
trap 'echo -e "\n${YELLOW}Interrupted. Run this script again to resume.${NC}"; exit 130' INT TERM

main "$@"
```

#### Step 2.2: Make Script Executable

```bash
chmod +x .tasks/squad-orchestrate.sh
```

#### Step 2.3: Output Final Instructions

```
=================================================================
           AgentSquad Orchestration - Ready to Execute
=================================================================

Generated files:
  + .tasks/orchestration-manifest.json  (execution state)
  + .tasks/squad-orchestrate.sh         (orchestration script)

Issues queued: N
Execution order:
  1. #42 - Add user authentication (no dependencies)
  2. #45 - Add profile page (depends on #42)
  3. #48 - Add settings page (depends on #42)

To start processing:
  ./.tasks/squad-orchestrate.sh

Options:
  ./.tasks/squad-orchestrate.sh 30    # Use 30 iterations per issue (default: 20)

The script will:
  - Process each issue with fresh Claude sessions (no context rot)
  - Create feature branches and PRs automatically
  - Handle failures gracefully (skip dependents, continue independents)
  - Auto-resume from where it left off if interrupted

You can safely Ctrl+C and restart - progress is saved to the manifest.
```

---

## Issue Convention

For issues to work with AgentSquad orchestration:

1. **Label**: Must have `squad:ready` label (or custom label if `--label` specified)

2. **Dependencies**: Declare explicitly in issue body:
   ```
   depends-on: #42
   ```
   or
   ```
   Blocked by #42, #43
   ```

3. **Content**: Should have clear acceptance criteria or checklist items

---

## GitHub Labels Reference

| Label | Color | Purpose |
|-------|-------|---------|
| `squad:ready` | Green (#0E8A16) | Ready for orchestration |
| `squad:queued` | Yellow (#FBCA04) | In the orchestration queue |
| `squad:in-progress` | Blue (#1D76DB) | Currently being processed |
| `squad:complete` | Purple (#6F42C1) | Successfully processed |
| `squad:failed` | Red (#D93F0B) | Processing failed |

---

## Examples

### Basic Usage

```
User: /orchestrate

Claude:
=================================================================
           AgentSquad Orchestration - Starting
=================================================================

Pre-flight checks...
  + Git working directory clean
  + On main branch
  + No active task session
  + GitHub CLI available
  + Labels exist

Fetching issues with label 'squad:ready'...
  Found 2 issues

Analyzing dependencies...
  #42 - Add user authentication (no dependencies)
  #45 - Add profile page (depends on #42)

Execution order:
  1. #42
  2. #45

Applying labels...
  #42 -> squad:queued
  #45 -> squad:queued

Manifest created: .tasks/orchestration-manifest.json

=================================================================
           AgentSquad Orchestration - Ready to Execute
=================================================================

Generated files:
  + .tasks/orchestration-manifest.json  (execution state)
  + .tasks/squad-orchestrate.sh         (orchestration script)

To start processing:
  ./.tasks/squad-orchestrate.sh

The script will process each issue with fresh Claude sessions.
```

### Dry Run

```
User: /orchestrate --dry-run

Claude:
=================================================================
           AgentSquad Orchestration - DRY RUN
=================================================================

Pre-flight checks...
  + All checks passed

Issues that would be processed:
  1. #42 - Add user authentication (no dependencies)
  2. #45 - Add profile page (depends on #42)

Dry run complete. No changes made.
To execute for real, run: /orchestrate
```

### Custom Label

```
User: /orchestrate --label sprint:current

Claude:
Fetching issues with label 'sprint:current'...
  Found 5 issues

[... continues ...]
```

### Initialize New Repo

```
User: /orchestrate --init

Claude:
=================================================================
           AgentSquad Orchestration - Initializing
=================================================================

Creating orchestration labels...
  + squad:ready (created)
  + squad:queued (created)
  + squad:in-progress (created)
  + squad:complete (created)
  + squad:failed (created)

=================================================================
           AgentSquad Orchestration - Initialized
=================================================================

Labels created/verified:
  + squad:ready        - Add this to issues ready for processing
  + squad:queued       - Applied when issue enters the queue
  + squad:in-progress  - Applied during processing
  + squad:complete     - Applied when PR is created
  + squad:failed       - Applied if processing fails

Next steps:
  1. Add 'squad:ready' label to issues you want to process
  2. Add 'depends-on: #N' in issue bodies to declare dependencies
  3. Run '/orchestrate' to process them
```

---

## Error Handling

| Error | Action |
|-------|--------|
| Git not clean | Report dirty files, ask user to commit/stash |
| No issues found | Report and suggest how to label issues |
| Circular dependencies | Report cycle, ask user to resolve |
| gh CLI missing | Report error, link to installation |
| Taskify fails | Mark failed, continue with independent issues |
| loop.sh fails | Mark failed, continue with independent issues |
| PR creation fails | Mark failed, continue with independent issues |
| Dependency failed | Skip dependent issues, continue with others |

### Failure Recovery

The bash script is designed for graceful failure handling:

1. **Failed issues**: Marked with `squad:failed` label, error logged to manifest
2. **Dependent issues**: Automatically skipped when their dependencies fail
3. **Independent issues**: Continue processing even when others fail
4. **Resume**: Safe to Ctrl+C and restart - script reads manifest state

To retry failed issues:
1. Investigate and fix the underlying problem
2. Remove `squad:failed` label, add `squad:ready`
3. Run `/orchestrate` again (completed issues are skipped)

---

## Files Created/Modified

| File | Purpose |
|------|---------|
| `.tasks/orchestration-manifest.json` | Execution state tracking |
| `.tasks/squad-orchestrate.sh` | Generated orchestration script |
| `.tasks/orchestration.log` | Execution log (created by script) |
| `.tasks/archive/issue-N/` | Archived session files |
| `squad/issue-N` branches | Feature branches per issue |
| PRs | Pull requests per issue |
