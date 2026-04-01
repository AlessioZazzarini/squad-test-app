# /cleanup - Archive Task Session and Close GitHub Issue

Archive completed task session files and close the associated GitHub issue.

## Arguments

- `$ARGUMENTS` - Optional flags:
  - `--force` - Skip task completion check and cleanup anyway
  - `--no-close` - Archive files but don't close the GitHub issue
  - `--no-comment` - Don't post completion comment to GitHub

## Workflow

### Step 1: Check for Active Task Session

Verify `.tasks/plan.md` exists:

```bash
if [ ! -f ".tasks/plan.md" ]; then
    echo "No active task session found. Nothing to clean up."
    exit 0
fi
```

### Step 2: Extract Issue Information

Parse the issue number from `.tasks/plan.md` or `.tasks/activity.md`:

Look for patterns like:

- `Issue #123`
- `GitHub Issue: #123`
- In the activity log header

Store the issue number for later GitHub operations.

### Step 3: Verify Task Completion

Read `.tasks/plan.md` and check if all tasks have `passes: true`.

```bash
# Count tasks with passes: false
incomplete=$(grep -c '"passes": false' .tasks/plan.md || echo "0")
```

If any tasks are incomplete and `--force` is not provided, STOP and report:

```
Cannot cleanup: <N> tasks still incomplete in .tasks/plan.md

Incomplete tasks:
- Task #2: Implement user authentication (passes: false)
- Task #5: Write integration tests (passes: false)

Options:
1. Complete the remaining tasks first
2. Run `/cleanup --force` to archive anyway
```

### Step 4: Generate Session Summary

Create a summary of what was accomplished:

```markdown
## Task Session Summary

**Issue:** #<NUMBER> - <TITLE>
**Date:** <CURRENT_DATE>
**Tasks Completed:** <COMPLETED>/<TOTAL>

### Completed Tasks

- [x] Task 1: <description>
- [x] Task 2: <description>
      ...

### Session Duration

Started: <start_time from activity.md>
Completed: <current_time>
Iterations: <count from activity.md>
```

### Step 5: Archive Session Files

Create archive copies in a folder per issue:

```bash
# Create timestamp
timestamp=$(date "+%Y-%m-%d")
issue_num="<EXTRACTED_ISSUE_NUMBER>"

# Create folder per issue
mkdir -p ".tasks/archive/issue-${issue_num}"

# Archive all files to issue folder
cp .tasks/plan.md ".tasks/archive/issue-${issue_num}/plan.md"
cp .tasks/activity.md ".tasks/archive/issue-${issue_num}/activity.md"
cp .tasks/PROMPT.md ".tasks/archive/issue-${issue_num}/PROMPT.md"
cp .tasks/loop.sh ".tasks/archive/issue-${issue_num}/loop.sh"
```

### Step 6: Post GitHub Comment (unless --no-comment)

Post a completion comment to the GitHub issue:

```bash
gh issue comment <issue_number> --body "$(cat <<'EOF'
## Task Session Complete

This issue was implemented using the AgentSquad autonomous build loop.

### Summary
- **Tasks Completed:** <COMPLETED>/<TOTAL>
- **Iterations:** <COUNT>
- **Date:** <DATE>
- **Archived to:** `.tasks/archive/issue-<NUMBER>/`

### Completed Tasks
<LIST_OF_COMPLETED_TASKS>

### Files Changed
<GIT_DIFF_STAT_OR_FILE_LIST>

---
*Automated comment from AgentSquad build loop*
EOF
)"
```

### Step 7: Close GitHub Issue (unless --no-close)

Close the issue if all tasks passed:

```bash
gh issue close <issue_number> --comment "Completed via AgentSquad autonomous build loop"
```

If `--force` was used with incomplete tasks, add a note:

```bash
gh issue close <issue_number> --comment "Partially completed via AgentSquad (some tasks incomplete). See issue for details."
```

### Step 8: Remove Working Files

Clean up the active session files:

```bash
rm -f .tasks/loop.sh
rm -f .tasks/PROMPT.md
rm -f .tasks/plan.md
rm -f .tasks/activity.md
```

### Step 9: Output Success Message

```
Task session archived successfully!

Session Summary:
  Issue: #<NUMBER> - <TITLE>
  Tasks: <COMPLETED>/<TOTAL> completed

Archived to:
  .tasks/archive/issue-<NUMBER>/
    +-- plan.md
    +-- activity.md
    +-- PROMPT.md
    +-- loop.sh

GitHub:
  Comment posted: Yes
  Issue closed: Yes (#<NUMBER>)

Working files removed. Ready for next session.
```

## Error Handling

- If GitHub operations fail, continue with local cleanup and report the error
- If archive directory doesn't exist, create it
- If issue number cannot be determined, skip GitHub operations and warn user

## Examples

### Normal Cleanup (all tasks complete)

```
User: /cleanup

Claude:
Checking task session status...
  Issue: #124 - Build guided program
  Tasks: 12/12 complete

Archiving session files...
  Created: .tasks/archive/issue-124/
  Archived: plan.md, activity.md, PROMPT.md, loop.sh

Posting completion comment to GitHub issue #124...
  Comment posted successfully

Closing GitHub issue #124...
  Issue closed

Removing working files...
  Removed: .tasks/loop.sh
  Removed: .tasks/PROMPT.md
  Removed: .tasks/plan.md
  Removed: .tasks/activity.md

Task session archived successfully!
```

### Incomplete Tasks

```
User: /cleanup

Claude:
Checking task session status...
  Issue: #124 - Build guided program
  Tasks: 10/12 complete

Cannot cleanup: 2 tasks still incomplete

Incomplete tasks:
- Task #11: Write E2E tests (passes: false)
- Task #12: Update documentation (passes: false)

Options:
1. Complete the remaining tasks: .tasks/loop.sh 10
2. Force cleanup anyway: /cleanup --force
```

### Force Cleanup

```
User: /cleanup --force

Claude:
Checking task session status...
  Issue: #124 - Build guided program
  Tasks: 10/12 complete (--force flag used)

Archiving session files...
  Created: .tasks/archive/issue-124/
  Archived: plan.md, activity.md, PROMPT.md, loop.sh

Posting completion comment to GitHub issue #124...
  Comment posted (noted: 2 tasks incomplete)

Closing GitHub issue #124...
  Issue closed with partial completion note

Removing working files...
  Done

Task session archived (with incomplete tasks).
```

### Archive Only (no GitHub changes)

```
User: /cleanup --no-close --no-comment

Claude:
Checking task session status...
  Issue: #124 - Build guided program
  Tasks: 12/12 complete

Archiving session files...
  Created: .tasks/archive/issue-124/
  Archived: plan.md, activity.md, PROMPT.md, loop.sh

Skipping GitHub operations (--no-close --no-comment)

Removing working files...
  Done

Task session archived successfully!
```
