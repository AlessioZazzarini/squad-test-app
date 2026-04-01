#!/usr/bin/env bash
# collab-bridge.sh — Claude Code → secondary model CLI bridge
#
# Usage:
#   collab-bridge.sh think "Your prompt here"
#   collab-bridge.sh build "Your prompt here"
#   collab-bridge.sh build "Implement this spec" .collab/specs/task.md
#
# Modes:
#   think — Read-only. Secondary model reads files but changes nothing.
#           For debate, review, architecture, debugging hypotheses.
#   build — Workspace-write + full-auto. Secondary model creates/modifies files.
#           For implementation tasks delegated by Claude.
#
# Configuration:
#   AGENTSQUAD_SECONDARY_MODEL — model to use (default: gpt-5.4)
#   AGENTSQUAD_SECONDARY_CLI   — CLI command (default: codex)
#
# Security:
#   Unsets OPENAI_API_KEY to force subscription auth.
#   Your project's API keys are NOT used by the secondary model.

set -euo pipefail

MODE="${1:?Usage: collab-bridge.sh <think|build> \"prompt\" [spec-file]}"
PROMPT="${2:?Usage: collab-bridge.sh <think|build> \"prompt\" [spec-file]}"
SPEC_FILE="${3:-}"

MODEL="${AGENTSQUAD_SECONDARY_MODEL:-gpt-5.4}"
CLI="${AGENTSQUAD_SECONDARY_CLI:-codex}"

# If a spec file is provided, prepend its contents to the prompt
if [[ -n "$SPEC_FILE" && -f "$SPEC_FILE" ]]; then
  PROMPT="## Build Spec
$(cat "$SPEC_FILE")

## Instructions
${PROMPT}"
fi

# ── Security ──────────────────────────────────────────────
# CRITICAL: Unset OPENAI_API_KEY so the secondary CLI falls
# back to its own auth (subscription). This prevents
# accidental API billing against your project's key.
unset OPENAI_API_KEY

# Suppress OpenTelemetry crash (known Codex CLI bug)
export OTEL_SDK_DISABLED=true

# ── Execute ───────────────────────────────────────────────
case "$MODE" in
  think)
    exec "$CLI" exec -m "$MODEL" -s read-only "$PROMPT"
    ;;
  build)
    exec "$CLI" exec -m "$MODEL" --full-auto "$PROMPT"
    ;;
  *)
    echo "Error: Mode must be 'think' or 'build'. Got: $MODE" >&2
    exit 1
    ;;
esac
