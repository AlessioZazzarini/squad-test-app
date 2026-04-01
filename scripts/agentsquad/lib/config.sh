#!/bin/bash
# config.sh — Shared configuration reader for AgentSquad scripts
#
# Reads .claude/agentsquad.json and exports standardized env vars.
# Falls back to sensible defaults if config doesn't exist.
#
# Usage: source "$(dirname "$0")/lib/config.sh"

_AGENTSQUAD_CONFIG_DIR="${AGENTSQUAD_CONFIG_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_AGENTSQUAD_CONFIG_FILE="${_AGENTSQUAD_CONFIG_DIR}/.claude/agentsquad.json"

_config_read() {
  local key="$1" default="$2"
  if [[ -f "$_AGENTSQUAD_CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    local val
    val=$(jq -r "$key // empty" "$_AGENTSQUAD_CONFIG_FILE" 2>/dev/null)
    if [[ -n "$val" ]]; then
      echo "$val"
      return
    fi
  fi
  echo "$default"
}

export AGENTSQUAD_PROJECT_NAME="${AGENTSQUAD_PROJECT_NAME:-$(_config_read '.project' "$(basename "$_AGENTSQUAD_CONFIG_DIR")")}"
export AGENTSQUAD_BUILD_CMD="${AGENTSQUAD_BUILD_CMD:-$(_config_read '.commands.build' 'npm run build')}"
export AGENTSQUAD_TEST_CMD="${AGENTSQUAD_TEST_CMD:-$(_config_read '.commands.test' 'npm test')}"
export AGENTSQUAD_E2E_CMD="${AGENTSQUAD_E2E_CMD:-$(_config_read '.commands.e2e' 'npx playwright test')}"
export AGENTSQUAD_LINT_CMD="${AGENTSQUAD_LINT_CMD:-$(_config_read '.commands.lint' 'npm run lint')}"
export AGENTSQUAD_MAIN_BRANCH="${AGENTSQUAD_MAIN_BRANCH:-$(_config_read '.mainBranch' 'main')}"
export AGENTSQUAD_TASKS_DIR="${AGENTSQUAD_TASKS_DIR:-$(_config_read '.tasksDir' '.tasks')}"
export AGENTSQUAD_MAX_WORKERS="${AGENTSQUAD_MAX_WORKERS:-$(_config_read '.maxWorkers' '3')}"
