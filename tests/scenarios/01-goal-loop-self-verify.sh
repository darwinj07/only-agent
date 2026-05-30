#!/bin/bash
# Scenario: goal-loop self-verify gate, end-to-end via real Claude spawn.
# Verifies:
#   - Stop hook fires when state file has gate: not-met
#   - Hook injects gate_reason back to the agent
#   - Agent receives injection, iterates, flips gate: met
#   - Hook passes cleanly when gate: met
# Expected runtime: ~2-3 min (real Claude session)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/lib/spawn.sh"
source "$TESTS_DIR/lib/assert.sh"

FAIL_COUNT=0
SLUG="regression-fruit-test"
STATE_FILE="$PROJECT_DIR/scratch/goal-loops/$SLUG.md"
SPAWN_ID=""

cleanup() {
  [[ -n "$SPAWN_ID" ]] && kill_agent "$SPAWN_ID"
  rm -f "$STATE_FILE"
}
trap cleanup EXIT

# Pre-cleanup in case of stale state
rm -f "$STATE_FILE"

PROMPT='Goal-loop regression test. Steps:

1. Read .claude/skills/goal-loop/SKILL.md if you havent already.

2. Use the goal-loop skill to set up a self-verify goal at scratch/goal-loops/'"$SLUG"'.md with:
   task: enumerate 3 fruits
   gate: not-met
   gate_reason: no fruits enumerated yet
   started: any date
   Empty body section called Fruits.

3. End your turn here without enumerating fruits. The Stop hook should block your turn-end with a gate-not-met injection.

4. After being unblocked by the injection, enumerate exactly 3 fruits (apple, banana, cherry) in the body and update the frontmatter to gate: met.

5. Stop again. The hook should pass cleanly this time.

6. Write your full report to the outbox path specified in your task message. The report MUST include these phrases verbatim:
   - "STATE_PATH: scratch/goal-loops/'"$SLUG"'.md"
   - "BLOCK_OBSERVED: yes"  (if the first stop was blocked) or "BLOCK_OBSERVED: no"
   - "PASS_OBSERVED: yes"   (if the second stop passed) or "PASS_OBSERVED: no"
   - The exact text the Stop hook injected when it blocked the first attempt.

Report only facts. If something unexpected happened, say so.'

echo "  spawning agent..."
SPAWN_ID=$(spawn_agent "$PROJECT_DIR" "$PROMPT")
[[ -n "$SPAWN_ID" ]] || { echo "  FAIL: spawn returned empty id"; exit 1; }
echo "  spawn id: $SPAWN_ID"

echo "  waiting for outbox (up to 360s)..."
if ! wait_for_outbox "$SPAWN_ID" 001 360; then
  echo "  FAIL: outbox not written within timeout"
  echo "  --- last pane content ---"
  capture_pane "$SPAWN_ID"
  exit 1
fi

REPORT=$(read_outbox "$SPAWN_ID")

echo ""
echo "  === assertions ==="
assert_contains "$REPORT" "STATE_PATH: scratch/goal-loops/$SLUG.md" "report cites correct state path"
assert_contains "$REPORT" "BLOCK_OBSERVED: yes" "first stop was blocked"
assert_contains "$REPORT" "PASS_OBSERVED: yes" "second stop passed"
assert_contains "$REPORT" "Active goal" "report includes hook block message"
assert_contains "$REPORT" "not met" "report includes 'not met' from hook"
assert_file_exists "$STATE_FILE" "state file exists at correct path"

# Verify the file was NOT created at the legacy wrong path (catches path-mismatch regressions)
assert_dir_not_exists "$PROJECT_DIR/scratch/goals" "no state files at legacy wrong path"

# Verify final state file has gate: met
if [[ -f "$STATE_FILE" ]]; then
  FINAL_STATE=$(cat "$STATE_FILE")
  assert_contains "$FINAL_STATE" "gate: met" "final state file shows gate: met"
fi

echo ""
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "  PASS: all assertions ok"
  exit 0
else
  echo "  FAIL: $FAIL_COUNT assertion(s) failed"
  echo "  --- outbox report ---"
  echo "$REPORT" | head -50
  exit 1
fi
