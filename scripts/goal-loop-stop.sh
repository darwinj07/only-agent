#!/bin/bash
# Goal-gate Stop hook.
# Reads state files at $CLAUDE_PROJECT_DIR/scratch/goal-loops/*.md and blocks
# turn-end while any gate is unmet.
#
# State file format:
#   ---
#   task: <human-readable>
#   started: <date>
#   # Exactly one of:
#   gate_command: <shell cmd>     # auto-verified (hook runs it, exit 0 = met)
#   gate: met|not-met             # model-verified (model updates the field)
#   gate_reason: <why not-met>    # optional, shown back to model when blocking
#   ---
#   <free-form body>

set -uo pipefail

cat > /dev/null  # consume hook stdin (not used)

GOALS_DIR="$CLAUDE_PROJECT_DIR/scratch/goal-loops"
[ -d "$GOALS_DIR" ] || exit 0

# Extract a single frontmatter key from a state file.
fm_get() {
  local file="$1" key="$2"
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$file" | head -40 \
    | grep "^${key}:" | head -1 | sed "s/^${key}: *//" | sed 's/^"\(.*\)"$/\1/' || true
}

BLOCKING_MSG=""

for state in "$GOALS_DIR"/*.md; do
  [ -f "$state" ] || continue

  TASK=$(fm_get "$state" task)
  GATE_COMMAND=$(fm_get "$state" gate_command)
  GATE_FIELD=$(fm_get "$state" gate)
  GATE_REASON=$(fm_get "$state" gate_reason)

  STATE_REL="${state#$CLAUDE_PROJECT_DIR/}"

  if [ -n "$GATE_COMMAND" ]; then
    # Shell gate: run the command
    CMD_OUTPUT=$(bash -c "$GATE_COMMAND" 2>&1)
    CMD_EXIT=$?
    if [ "$CMD_EXIT" -ne 0 ]; then
      CMD_TAIL=$(echo "$CMD_OUTPUT" | tail -20)
      BLOCKING_MSG+="
[$TASK]
State: $STATE_REL
Gate: command exited $CMD_EXIT
Command: $GATE_COMMAND
Output (last 20 lines):
$CMD_TAIL
"
    fi
  elif [ -n "$GATE_FIELD" ]; then
    # Model-verified gate: read the field
    if [ "$GATE_FIELD" != "met" ]; then
      REASON="${GATE_REASON:-(no reason set)}"
      BLOCKING_MSG+="
[$TASK]
State: $STATE_REL
Gate: not met
Reason: $REASON
"
    fi
  else
    BLOCKING_MSG+="
[$TASK]
State: $STATE_REL
ERROR: state file missing both 'gate_command' and 'gate'. Fix the file or delete it.
"
  fi
done

if [ -n "$BLOCKING_MSG" ]; then
  REASON="Active goal(s) with open gates. Continue iterating, or delete the state file to abandon.
$BLOCKING_MSG"
  jq -n --arg m "$REASON" '{decision: "block", reason: $m}'
fi

exit 0
