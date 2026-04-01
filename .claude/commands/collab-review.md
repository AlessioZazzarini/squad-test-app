# /collab-review — Quick Second Opinion

Get a fast review from the secondary model on current changes without full collaboration.

## Workflow

1. **Identify what to review.** Run `git diff` for uncommitted changes, or use what the user describes.
2. **Summarize the changes.** Write a 2-3 sentence summary of what changed and why.
3. **Call secondary model (synchronous — reviews are fast):**
   ```bash
   packs/collab/bin/collab-bridge.sh think "Review these recent changes. Focus on: bugs, edge cases, type safety, missing error handling. Be concise — bullet points, critical issues first, skip praise.

   Files changed: [list paths]
   Summary: [your 2-3 sentence summary]
   [User's specific concerns if any]"
   ```
4. **Synthesize.** Present to user:
   - Critical issues found (if any)
   - Suggestions worth considering
   - Things flagged that you disagree with (and why)
   - Your own observations not covered by the secondary model

## Rules

- Keep the prompt under 300 words. The secondary model can read the files itself.
- Synthesize — don't relay raw output.
- If nothing significant is found, say so. Don't invent issues.
- If no changes exist to review, tell the user and ask what they'd like reviewed.

$ARGUMENTS
