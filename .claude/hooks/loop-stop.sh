#!/bin/bash

# AgentSquad Loop Stop Hook (v2 — Taskmaster Compliance)
# Prevents session exit when a AgentSquad loop is active
# Feeds Claude's output back as input to continue the loop
# Injects Taskmaster 7-point compliance checklist every iteration

set -euo pipefail

# Only active in squadmode sessions (env var set by alias)
[[ "${AGENTSQUAD_LOOP_ENABLED:-}" != "1" ]] && exit 0

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)

# Check if loop is active
SQUAD_STATE_FILE=".claude/loop.local.md"

if [[ ! -f "$SQUAD_STATE_FILE" ]]; then
  # No active loop - allow exit
  exit 0
fi

# Parse markdown frontmatter (YAML between ---) and extract values
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$SQUAD_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
# Extract completion_promise and strip surrounding quotes if present
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

# Session isolation: the state file is project-scoped, but the Stop hook
# fires in every Claude Code session in that project. If another session
# started the loop, this session must not block (or touch the state file).
# Legacy state files without session_id fall through (preserves old behavior).
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# Validate numeric fields before arithmetic operations
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "⚠️  AgentSquad loop: State file corrupted" >&2
  echo "   File: $SQUAD_STATE_FILE" >&2
  echo "   Problem: 'iteration' field is not a valid number (got: '$ITERATION')" >&2
  echo "" >&2
  echo "   This usually means the state file was manually edited or corrupted." >&2
  echo "   AgentSquad loop is stopping. Run /loop-start again to start fresh." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  AgentSquad loop: State file corrupted" >&2
  echo "   File: $SQUAD_STATE_FILE" >&2
  echo "   Problem: 'max_iterations' field is not a valid number (got: '$MAX_ITERATIONS')" >&2
  echo "" >&2
  echo "   This usually means the state file was manually edited or corrupted." >&2
  echo "   AgentSquad loop is stopping. Run /loop-start again to start fresh." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 AgentSquad loop: Max iterations ($MAX_ITERATIONS) reached."
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  AgentSquad loop: Transcript file not found" >&2
  echo "   Expected: $TRANSCRIPT_PATH" >&2
  echo "   This is unusual and may indicate a Claude Code internal issue." >&2
  echo "   AgentSquad loop is stopping." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Read last assistant message from transcript (JSONL format - one JSON per line)
# First check if there are any assistant messages
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  AgentSquad loop: No assistant messages found in transcript" >&2
  echo "   Transcript: $TRANSCRIPT_PATH" >&2
  echo "   This is unusual and may indicate a transcript format issue" >&2
  echo "   AgentSquad loop is stopping." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Extract the most recent assistant text block.
#
# Claude Code writes each content block (text/tool_use/thinking) as its own
# JSONL line, all with role=assistant. So slurp the last N assistant lines,
# flatten to text blocks only, and take the last one.
#
# Capped at the last 100 assistant lines to keep jq's slurp input bounded
# for long-running sessions.
LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)
if [[ -z "$LAST_LINES" ]]; then
  echo "⚠️  AgentSquad loop: Failed to extract assistant messages" >&2
  echo "   AgentSquad loop is stopping." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Parse the recent lines and pull out the final text block.
# `last // ""` yields empty string when no text blocks exist (e.g. a turn
# that is all tool calls). That's fine: empty text means no <promise> tag,
# so the loop simply continues.
# (Briefly disable errexit so a jq failure can be caught by the $? check.)
set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | last // ""
' 2>&1)
JQ_EXIT=$?
set -e

# Check if jq succeeded
if [[ $JQ_EXIT -ne 0 ]]; then
  echo "⚠️  AgentSquad loop: Failed to parse assistant message JSON" >&2
  echo "   Error: $LAST_OUTPUT" >&2
  echo "   This may indicate a transcript format issue." >&2
  echo "   AgentSquad loop is stopping." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Check for completion promise (only if set)
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # Extract text from <promise> tags using Perl for multiline support
  # -0777 slurps entire input, s flag makes . match newlines
  # .*? is non-greedy (takes FIRST tag), whitespace normalized
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  # Use = for literal string comparison (not pattern matching)
  # == in [[ ]] does glob pattern matching which breaks with *, ?, [ characters
  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "✅ AgentSquad loop: Detected <promise>$COMPLETION_PROMISE</promise>"
    rm "$SQUAD_STATE_FILE"
    exit 0
  fi
fi

# Not complete - continue loop with SAME PROMPT
NEXT_ITERATION=$((ITERATION + 1))

# Extract prompt (everything after the closing ---)
# Skip first --- line, skip until second --- line, then print everything after
# Use i>=2 instead of i==2 to handle --- in prompt content
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$SQUAD_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  AgentSquad loop: State file corrupted or incomplete" >&2
  echo "   File: $SQUAD_STATE_FILE" >&2
  echo "   Problem: No prompt text found" >&2
  echo "" >&2
  echo "   This usually means:" >&2
  echo "     • State file was manually edited" >&2
  echo "     • File was corrupted during writing" >&2
  echo "" >&2
  echo "   AgentSquad loop is stopping. Run /loop-start again to start fresh." >&2
  rm "$SQUAD_STATE_FILE"
  exit 0
fi

# Update iteration in frontmatter (portable across macOS and Linux)
# Create temp file, then atomically replace
TEMP_FILE="${SQUAD_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$SQUAD_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SQUAD_STATE_FILE"

# Build Taskmaster compliance system message
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_INSTRUCTION="TO COMPLETE: Output <promise>$COMPLETION_PROMISE</promise> ONLY when ALL checks pass."
else
  PROMISE_INSTRUCTION="No completion promise set — loop runs until --max-iterations."
fi

SYSTEM_MSG="AgentSquad ITERATION $NEXT_ITERATION$(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "/$MAX_ITERATIONS"; fi) — COMPLIANCE CHECK

BEFORE STOPPING, PASS ALL 7 CHECKS:
1. GOAL: What is the goal? Is it achieved RIGHT NOW? YES or NO only.
2. ORIGINAL REQUEST: Re-read every criterion. Each one FULLY done?
3. TASK LIST: Any incomplete items? Do them now.
4. PLAN: All steps EXECUTED (not planned)? Verification steps actually run and passing?
5. ERRORS: Any broken code, failed tests, incomplete work? Fix now.
6. LOOSE ENDS: TODOs, placeholders, untested changes? Do them now.
7. BLOCKERS: Did you actually TRY before claiming impossible?

BANNED PHRASES (if you think these, you are rationalizing):
- \"diminishing returns\" / \"good progress\" / \"core functionality works\"
- \"would require broader changes\" / \"good stopping point\"
- \"further improvements in a follow-up\"

DO NOT NARRATE — EXECUTE. Describing remaining work instead of doing it is failure.
PROGRESS IS NOT COMPLETION. Partial work toward a goal is not the goal.

$PROMISE_INSTRUCTION"

# Output JSON to block the stop and feed prompt back
# The "reason" field contains the prompt that will be sent back to Claude
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

# Exit 0 for successful hook execution
exit 0
