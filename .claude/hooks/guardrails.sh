#!/usr/bin/env bash
#
# AgentSquad Guardrails - PreToolUse Hook
# Prevents destructive operations during autonomous loops
#
# This hook runs BEFORE every Bash tool call, even when
# --dangerously-skip-permissions is used.
#
# Exit 0 = allow command
# Exit 2 = block command (error shown to Claude)

set -e

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool_name and command using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only check Bash tool calls
if [[ "$TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

# Normalize command for pattern matching (lowercase)
CMD_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

log_blocked() {
    local reason="$1"
    echo "BLOCKED: $reason" >&2
    echo "Command was: $COMMAND" >&2
    exit 2
}

# ============================================================
# DATABASE DESTRUCTION PATTERNS
# ============================================================

# DROP TABLE/DATABASE/SCHEMA
if echo "$CMD_LOWER" | grep -qE '(drop\s+(table|database|schema)|\btruncate\s+table)'; then
    log_blocked "Database destruction (DROP/TRUNCATE) is not allowed in autonomous mode"
fi

# DELETE without WHERE clause (dangerous mass deletion)
if echo "$CMD_LOWER" | grep -qE 'delete\s+from\s+[a-z_]+\s*(;|$)'; then
    log_blocked "DELETE without WHERE clause is not allowed - use DELETE FROM table WHERE condition"
fi

# ============================================================
# GIT DESTRUCTION PATTERNS
# ============================================================

# Force push to main/master
if echo "$CMD_LOWER" | grep -qE 'git\s+push\s+.*(-f|--force).*\s+(origin\s+)?(main|master)'; then
    log_blocked "Force push to main/master is not allowed"
fi
if echo "$CMD_LOWER" | grep -qE 'git\s+push\s+.*\s+(origin\s+)?(main|master).*(-f|--force)'; then
    log_blocked "Force push to main/master is not allowed"
fi

# Delete main/master branch
if echo "$CMD_LOWER" | grep -qE 'git\s+branch\s+(-d|-D|--delete).*\s+(main|master)'; then
    log_blocked "Deleting main/master branch is not allowed"
fi

# Hard reset without specific target (dangerous when it loses commits)
if echo "$CMD_LOWER" | grep -qE 'git\s+reset\s+--hard\s*$'; then
    log_blocked "git reset --hard without a specific target is dangerous - specify a commit or branch"
fi

# git clean with force and directories (removes untracked files and dirs)
if echo "$CMD_LOWER" | grep -qE 'git\s+clean\s+.*-fd'; then
    log_blocked "git clean -fd removes untracked files/directories irreversibly"
fi

# ============================================================
# FILE SYSTEM DESTRUCTION PATTERNS
# ============================================================

# rm -rf on source directories
if echo "$CMD_LOWER" | grep -qE 'rm\s+(-rf|-fr|--recursive\s+--force)\s+(\.?/?)?(src|lib|app|components|pages|api|utils|hooks|services|models|controllers|routes|middleware|config|public|assets|styles)(/|\s|$)'; then
    log_blocked "Deleting source directories (src, lib, app, components, etc.) is not allowed"
fi

# rm -rf on .git directory
if echo "$CMD_LOWER" | grep -qE 'rm\s+(-rf|-fr)\s+.*\.git(/|\s|$)'; then
    log_blocked "Deleting .git directory would destroy all git history"
fi

# rm -rf on root or parent directories
if echo "$CMD_LOWER" | grep -qE 'rm\s+(-rf|-fr)\s+(/|\.\./)'; then
    log_blocked "Deleting root or parent directories is not allowed"
fi

# Deleting environment files
if echo "$CMD_LOWER" | grep -qE 'rm\s+.*\.env'; then
    log_blocked "Deleting .env files is not allowed - these contain critical configuration"
fi

# Deleting config files
if echo "$CMD_LOWER" | grep -qE 'rm\s+.*(package\.json|tsconfig\.json|next\.config|tailwind\.config|vite\.config|webpack\.config)'; then
    log_blocked "Deleting core config files is not allowed"
fi

# ============================================================
# SECRET LEAK PATTERNS
# ============================================================

# export $(grep ...) — if grep fails, export dumps ALL env vars
if echo "$CMD_LOWER" | grep -qE 'export\s+\$\('; then
    log_blocked "export \$(command) is unsafe — if the inner command fails, all env vars are leaked. Use dotenv or source with a file-existence check instead"
fi

# Bare 'export' with no arguments dumps all env vars
if echo "$CMD_LOWER" | grep -qE '^\s*export\s*$'; then
    log_blocked "Bare 'export' dumps all environment variables including secrets"
fi

# source/dot-sourcing .env files then piping to psql or other commands
# (Allow source .env for loading, but block if .env.local doesn't exist check is missing)

# Direct env var expansion in psql connection strings (risk of logging)
if echo "$CMD_LOWER" | grep -qE 'psql.*\$[A-Z_]' && echo "$CMD_LOWER" | grep -qE 'xargs'; then
    log_blocked "Combining xargs with psql env vars is unsafe — use dotenv.config() in a script instead"
fi

# Piping env/printenv/set into files or commands
if echo "$CMD_LOWER" | grep -qE '(^|\|)\s*(env|printenv|set)\s*(\||>)'; then
    log_blocked "Piping environment variables to files or commands risks leaking secrets"
fi

# ============================================================
# CLOUD/CI DESTRUCTION PATTERNS
# ============================================================

# Vercel project deletion
if echo "$CMD_LOWER" | grep -qE 'vercel\s+(rm|remove|delete)'; then
    log_blocked "Vercel project deletion is not allowed in autonomous mode"
fi

# Deleting GitHub workflows
if echo "$CMD_LOWER" | grep -qE 'rm\s+.*\.github/workflows'; then
    log_blocked "Deleting GitHub workflow files is not allowed"
fi

# ============================================================
# SAFE PATTERNS - These are explicitly allowed even though
# they match rm -rf patterns
# ============================================================

# These are safe to delete (build artifacts, dependencies, caches)
# node_modules, .next, dist, build, coverage, .turbo, .cache
# The checks above use specific source directory names, so these
# don't need explicit allowlisting - they just won't match

# ============================================================
# If we get here, the command is allowed
# ============================================================

exit 0
