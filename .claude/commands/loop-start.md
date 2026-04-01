---
description: "Start AgentSquad Loop with Taskmaster compliance"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
allowed-tools: ["Bash(.claude/hooks/loop-setup.sh:*)"]
---

Execute: `.claude/hooks/loop-setup.sh $ARGUMENTS`

Then work on the task. Taskmaster compliance fires every iteration — a 7-point checklist that blocks premature stopping rationalizations.

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop, even if you think you're stuck or should exit for other reasons. The loop is designed to continue until genuine completion.
