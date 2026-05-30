#!/bin/bash
# Regression test runner.
# Runs every executable .sh in scenarios/, in lexical order, and aggregates results.
#
# Usage:
#   bash tests/run.sh                  # run all scenarios
#   bash tests/run.sh 01               # run scenarios matching '01' prefix
#   bash tests/run.sh goal-loop        # run scenarios containing 'goal-loop'
#
# Each scenario script is responsible for its own setup/cleanup. Scenarios
# return exit 0 on pass, non-zero on fail. Logs go to stdout.

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIOS_DIR="$TESTS_DIR/scenarios"

FILTER="${1:-}"

PASS=0
FAIL=0
FAILED_NAMES=()

shopt -s nullglob
for scenario in "$SCENARIOS_DIR"/*.sh; do
  name=$(basename "$scenario" .sh)

  if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
    continue
  fi

  echo "=========================================="
  echo "  $name"
  echo "=========================================="
  if bash "$scenario"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name")
  fi
  echo ""
done

echo "=========================================="
echo "  Summary: $PASS passed, $FAIL failed"
echo "=========================================="
if [[ $FAIL -gt 0 ]]; then
  for n in "${FAILED_NAMES[@]}"; do
    echo "  - $n"
  done
  exit 1
fi
exit 0
