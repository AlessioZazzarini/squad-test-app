# /finish - Wrap Up Session: Commit, Push, Issues, Docs

Complete the current work session by handling all git operations, GitHub issue management, and documentation updates.

## Arguments

- `$ARGUMENTS` - Optional flags:
  - `--dry-run` - Preview what would happen without making changes
  - `--no-push` - Commit but don't push to remote
  - `--no-issues` - Skip GitHub issue management
  - `--no-docs` - Skip documentation review/updates

## Workflow

### Phase 1: Assess Current State

#### Step 1.1: Git Status & Diff

Gather the full picture of what changed in this session:

```bash
git status
git diff --stat
git diff --staged --stat
git log --oneline -5
```

Identify:
- All modified, added, and deleted files
- Whether we're on `main` or a feature branch
- Whether there are uncommitted changes

#### Step 1.2: Identify Related GitHub Issues

Scan the work done to find related issues:

1. Check the git log for issue references (`#123`, `fixes #123`, `closes #123`)
2. Check if there's an active task session (`.tasks/plan.md`) with a linked issue
3. Look at the files changed and cross-reference with open issues:
   ```bash
   gh issue list --state open --limit 50 --json number,title,labels,body
   ```
4. Ask the user to confirm which issues are related if unclear

#### Step 1.3: Determine Branch Strategy

- **If on `main`**: Create a feature branch from the changes before committing
  - Branch name: `feat/<short-description>` or `fix/<short-description>` based on the nature of changes
- **If on a feature branch**: Continue on the current branch
- **If changes span multiple unrelated issues**: Flag this to the user and suggest splitting

### Phase 2: Commit & Push

#### Step 2.1: Stage Changes

Review all changes and stage them intelligently:

1. **Never stage**: `.env`, `.env.local`, credentials, secrets, large binaries
2. **Group related changes**: If changes touch multiple features, consider separate commits
3. Stage files:
   ```bash
   git add <specific-files>
   ```

#### Step 2.2: Craft Commit Message

Write a clear commit message following the repo's conventions (check recent `git log` for style):

- Summary line: imperative mood, under 72 chars
- Body: explain the "why", reference issue numbers
- Include `Co-Authored-By: Claude <noreply@anthropic.com>`

Format:
```
<type>: <summary> (#<issue>)

<body explaining what changed and why>

Co-Authored-By: Claude <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

#### Step 2.3: Commit

```bash
git commit -m "<message>"
```

If pre-commit hooks fail, fix the issues and create a NEW commit (never amend).

#### Step 2.4: Push

Unless `--no-push` is set:

```bash
git push -u origin <branch-name>
```

If on a new branch, set upstream tracking.

### Phase 3: GitHub Issue Management

Skip if `--no-issues` is set.

#### Step 3.1: Update Related Issues

For each issue related to this work:

1. **Post a progress comment** summarizing what was done:
   ```bash
   gh issue comment <number> --body "$(cat <<'EOF'
   ## Progress Update

   ### Changes Made
   - <bullet list of changes>

   ### Files Modified
   <git diff --stat output>

   ### Status
   <COMPLETED | IN PROGRESS | PARTIALLY DONE>

   ### Next Steps
   - <any remaining work>

   ---
   *Updated by Claude Code session*
   EOF
   )"
   ```

2. **Update labels** if applicable (e.g., add `in-progress`, remove `squad:ready`)

#### Step 3.2: Close Completed Issues

If an issue's acceptance criteria are fully met:

```bash
gh issue close <number> --comment "Completed. All acceptance criteria met. See commit <sha> / PR #<number>."
```

Before closing, verify:
- All checklist items in the issue body are done
- Tests pass for the related functionality
- The feature works as specified

#### Step 3.3: Create New Issues for Discovered Work

If during the session we identified new work, bugs, or TODOs:

```bash
gh issue create --title "<title>" --body "$(cat <<'EOF'
## Context
Discovered during work on #<parent-issue>.

## Description
<what needs to be done>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>

---
*Created by Claude Code session*
EOF
)" --label "<appropriate-labels>"
```

Common scenarios for new issues:
- Technical debt discovered during implementation
- Edge cases that need handling
- Follow-up features identified
- Test gaps found
- Performance improvements needed

#### Step 3.4: Create PR if on Feature Branch

If we're on a feature branch and changes are pushed:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points>

## Related Issues
- Closes #<number>
- Related to #<number>

## Changes
<bullet list of what changed>

## Test Plan
- [ ] <test steps>

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Phase 4: Documentation Review & Updates

Skip if `--no-docs` is set.

#### Step 4.1: Review Project Documentation

Scan for project documentation files and check:

1. **Task completion status**: Mark completed tasks/epics as done
2. **Dependency updates**: If new dependencies were added, document them
3. **Architecture changes**: If the approach diverged from the plan, update it
4. **New tasks discovered**: Add them to the appropriate section

#### Step 4.2: Review README and Guides

Check if any docs need updates based on changes made:
- README.md - if setup instructions, commands, or project structure changed
- Any architecture docs - if system design changed
- Configuration docs - if env vars or config files changed

#### Step 4.3: Commit Documentation Changes

If any docs were updated, create a separate commit:

```bash
git add <doc-files>
git commit -m "$(cat <<'EOF'
docs: update documentation to reflect latest changes

- <list of doc changes>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

### Phase 5: Final Summary

Output a clear summary of everything that was done:

```
========================================
  Session Wrap-Up Complete
========================================

Git:
  Branch:  <branch-name>
  Commits: <N> new commits
  Pushed:  Yes/No
  PR:      <PR-URL or N/A>

GitHub Issues:
  Updated:  #<list>
  Closed:   #<list>
  Created:  #<list of new issues>

Documentation:
  Updated:  <list of files>
  Changes:  <summary of doc updates>

All clean. Ready for next session.
========================================
```

## Error Handling

- If `gh` CLI is not authenticated, warn and skip GitHub operations
- If push fails (e.g., conflicts), report the error and suggest resolution
- If pre-commit hooks fail, fix issues and retry (never use `--no-verify`)
- If documentation files don't exist, skip those checks
- Always complete as many phases as possible even if one fails

## Decision Guidelines

### When to Create a Branch vs Stay on Main
- **Create branch**: If changes are substantial (3+ files, new feature, breaking change)
- **Stay on main**: If changes are minor (typo fix, small config update, single-file fix)
- **Always ask**: If uncertain, ask the user

### When to Close vs Comment on Issues
- **Close**: All acceptance criteria met, tests pass, feature works
- **Comment only**: Partial progress, some criteria unmet, blocked on something

### When to Create New Issues
- Any TODO comments added during the session
- Any known limitations or edge cases punted
- Any follow-up work explicitly discussed with the user
- Any bugs discovered but not fixed

## Example

```
User: /finish

Claude:
Assessing current state...

Git Status:
  Branch: main
  Modified: 8 files
  Untracked: 2 files

Related Issues:
  #45 - Add widget component (matches changed files)
  #47 - Update prompts for v2 (matches changed files)

Creating feature branch: feat/widget-and-prompt-updates

Committing changes...
  Commit 1: feat: add widget component (#45)
  Commit 2: feat: update prompts for v2 (#47)
  Pushed to origin/feat/widget-and-prompt-updates

GitHub Issues:
  #45 - Commented with progress, closed (all criteria met)
  #47 - Commented with progress, closed (all criteria met)
  #52 - Created: "Add widget error boundary" (discovered during #45)

Documentation:
  Updated: README.md (added new commands)
  Committed: docs: update README with new commands

PR: https://github.com/owner/repo/pull/83

========================================
  Session Wrap-Up Complete
========================================

Git:
  Branch:  feat/widget-and-prompt-updates
  Commits: 3 new commits
  Pushed:  Yes
  PR:      https://github.com/owner/repo/pull/83

GitHub Issues:
  Updated:  #45, #47
  Closed:   #45, #47
  Created:  #52

Documentation:
  Updated:  README.md

All clean. Ready for next session.
========================================
```
