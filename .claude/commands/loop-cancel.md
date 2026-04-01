---
description: "Cancel active AgentSquad Loop"
allowed-tools: ["Bash(test -f .claude/loop.local.md:*)", "Bash(rm .claude/loop.local.md)", "Read(.claude/loop.local.md)"]
---

# Cancel AgentSquad Loop

To cancel the AgentSquad loop:

1. Check if `.claude/loop.local.md` exists using Bash: `test -f .claude/loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active AgentSquad loop found."

3. **If EXISTS**:
   - Read `.claude/loop.local.md` to get the current iteration number from the `iteration:` field
   - Remove the file using Bash: `rm .claude/loop.local.md`
   - Report: "Cancelled AgentSquad loop (was at iteration N)" where N is the iteration value
