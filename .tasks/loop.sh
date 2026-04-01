#!/bin/bash

# loop.sh - AgentSquad Autonomous Build Loop
# =======================================
#
# Usage:
#   .tasks/loop.sh [max_iterations]

set -e

# Navigate to repo root (parent of .tasks)
cd "$(dirname "$0")/.."

# Configuration - files are in .tasks/
MAX_ITERATIONS=${1:-10}
PROMPT_FILE=".tasks/PROMPT.md"
PLAN_FILE=".tasks/plan.md"
ACTIVITY_FILE=".tasks/activity.md"
COMPLETION_SIGNAL="<promise>COMPLETE</promise>"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_dependencies() {
    if ! command -v claude &> /dev/null; then
        echo -e "${RED}Error: Claude Code CLI not found.${NC}"
        exit 1
    fi

    if [ ! -f "$PROMPT_FILE" ]; then
        echo -e "${RED}Error: $PROMPT_FILE not found.${NC}"
        exit 1
    fi

    if [ ! -f "$PLAN_FILE" ]; then
        echo -e "${RED}Error: $PLAN_FILE not found.${NC}"
        exit 1
    fi
}

log_activity() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" >> "$ACTIVITY_FILE"
}

run_loop() {
    local iteration=1

    echo -e "${BLUE}=======================================================${NC}"
    echo -e "${BLUE}           AgentSquad Autonomous Build Loop                  ${NC}"
    echo -e "${BLUE}=======================================================${NC}"
    echo -e "${BLUE}  Max iterations: ${GREEN}$MAX_ITERATIONS${NC}"
    echo -e "${BLUE}  Prompt file:    ${GREEN}$PROMPT_FILE${NC}"
    echo -e "${BLUE}  Plan file:      ${GREEN}$PLAN_FILE${NC}"
    echo -e "${BLUE}=======================================================${NC}"
    echo ""

    log_activity "=== AgentSquad Loop Started (max $MAX_ITERATIONS iterations) ==="

    while [ $iteration -le $MAX_ITERATIONS ]; do
        echo -e "${YELLOW}--- Iteration $iteration of $MAX_ITERATIONS ---${NC}"

        log_activity "--- Iteration $iteration started ---"

        local prompt_content=$(cat "$PROMPT_FILE")
        local output_file="/tmp/squad_output_$$_$iteration.txt"

        claude -p "$prompt_content" --dangerously-skip-permissions 2>&1 | tee "$output_file" || {
            echo -e "${RED}Claude exited with error${NC}"
            log_activity "ERROR: Claude exited with error"
        }

        local output=$(cat "$output_file" 2>/dev/null || echo "")
        rm -f "$output_file"

        local summary=$(echo "$output" | tail -20)
        log_activity "Output summary: $summary"

        if echo "$output" | grep -q "$COMPLETION_SIGNAL"; then
            echo ""
            echo -e "${GREEN}=======================================================${NC}"
            echo -e "${GREEN}                    BUILD COMPLETE!                      ${NC}"
            echo -e "${GREEN}=======================================================${NC}"
            log_activity "=== BUILD COMPLETE - All tasks finished ==="
            exit 0
        fi

        iteration=$((iteration + 1))

        if [ $iteration -le $MAX_ITERATIONS ]; then
            echo -e "${BLUE}Waiting 2 seconds before next iteration...${NC}"
            sleep 2
        fi
    done

    echo ""
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "${YELLOW}   Maximum iterations reached ($MAX_ITERATIONS)         ${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    log_activity "=== Loop ended - Max iterations reached ==="
}

main() {
    check_dependencies
    run_loop
}

trap 'echo -e "\n${YELLOW}Interrupted by user${NC}"; log_activity "=== Interrupted by user ==="; exit 130' INT

main
