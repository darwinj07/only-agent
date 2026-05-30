# Regression tests

Agentic regression tests for only-agent. Each scenario spawns a real Claude session via tmux, exercises a feature, and asserts on the agent's behavior plus side effects.

This is "agent-level" testing - the unit under test is "the agent using a skill correctly," not just a function. Slower and more variable than pure code tests, but catches behaviors that pure code can't.

## Run

```bash
bash tests/run.sh                  # all scenarios
bash tests/run.sh 01               # scenarios with '01' in the name
bash tests/run.sh goal-loop        # scenarios about goal-loop
```

Exit 0 if all pass, exit 1 if any fail. Failed scenario names listed at the bottom.

## Add a scenario

1. Create `scenarios/NN-short-name.sh` (NN is a 2-digit prefix for ordering).
2. Source `lib/spawn.sh` and `lib/assert.sh`.
3. Set `FAIL_COUNT=0`. Use the `assert_*` helpers - they increment FAIL_COUNT on failure.
4. Use `spawn_agent <project_dir> <prompt>` to launch a Claude session.
5. Use `wait_for_outbox <id> [num] [timeout]` to wait for the agent's report.
6. `read_outbox <id>` to get the report content.
7. Assert against the report and any side effects (state files, etc.).
8. Set up a `trap cleanup EXIT` that calls `kill_agent` and removes test artifacts.
9. Exit 0 on pass, non-zero on fail.

See `scenarios/01-goal-loop-self-verify.sh` for a complete example.

## Why agentic tests

The goal-loop test (`01-goal-loop-self-verify.sh`) exists because a path-mismatch bug in the Stop hook silently let `gate: not-met` pass without iterating. Pure code tests on the hook script would have caught the path mismatch eventually, but they wouldn't catch a future regression where:
- The hook reads the right path but the SKILL.md instructs the agent to write somewhere else.
- The hook fires correctly but the injection text confuses the agent.
- The agent reads the SKILL.md but skips a step under load.

These regressions only show up when a real agent runs the workflow end to end.

## Cost

Each scenario spawns a full Claude session. Expect ~2-3 min per scenario. Cost: a few cents in API credits per run. Not free, but low enough for occasional regression sweeps.
