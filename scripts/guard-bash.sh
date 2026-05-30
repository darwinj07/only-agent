#!/usr/bin/env bash
#
# PreToolUse hook for Bash - enforces safety rules on commands before execution.
#
# Reads tool input JSON from stdin. Exits 2 to block, 0 to allow.
# Blocked commands get a message explaining what to do instead.
#
# Rules:
# - Block force push (--force, -f)
# - Block push to main/master
# - Block git reset --hard
# - Block raw `gh pr create` (must use tools/github/create-pr.sh)

set -euo pipefail

# Read the full stdin (tool input JSON)
INPUT=$(cat)

# Extract the command from tool input JSON
# Format: {"tool_input": {"command": "..."}}
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null)

# If we couldn't parse the command, allow (don't block on hook errors)
[ -z "$COMMAND" ] && exit 0

# Extract the first line of the command (actual command, not heredoc/message content)
FIRST_LINE=$(echo "$COMMAND" | head -1)

# --- Rule: Block force push ---
if echo "$FIRST_LINE" | grep -qE '(push.*--force|push.*-f|--force.*push)'; then
    MSG="BLOCKED: force push. Use regular push or ask the user first."
    echo "$MSG"
    echo "$MSG" >&2
    exit 2
fi

# --- Rule: Block push to main/master ---
if echo "$FIRST_LINE" | grep -qE 'push.*(origin|upstream)\s+(main|master)\b'; then
    MSG="BLOCKED: pushing directly to main/master. Create a branch and PR instead."
    echo "$MSG"
    echo "$MSG" >&2
    exit 2
fi

# --- Rule: Block reset --hard ---
if echo "$FIRST_LINE" | grep -qE 'git\s+reset\s+--hard'; then
    MSG="BLOCKED: git reset --hard can destroy work. Ask the user first."
    echo "$MSG"
    echo "$MSG" >&2
    exit 2
fi

# --- Rule: Block raw gh pr create ---
# The PR creation tool (tools/github/create-pr.sh) calls gh pr create internally
# as a subprocess, which does NOT trigger this hook. Only direct Claude tool calls
# are intercepted, so there's no conflict.
if echo "$FIRST_LINE" | grep -qE 'gh\s+pr\s+create'; then
    MSG="BLOCKED: Use tools/github/create-pr.sh instead of raw gh pr create. Run --check first, then --create."
    echo "$MSG"      # stdout -> model context
    echo "$MSG" >&2  # stderr -> user-visible
    exit 2
fi

exit 0
