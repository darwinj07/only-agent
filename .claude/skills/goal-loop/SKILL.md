---
name: goal-loop
description: Force the agent to keep iterating on a task until a verification gate passes. Gates can be shell commands (tests, builds, linters), an isolated agent reviewer, or model self-verification. Use when the user says "loop until X", "don't stop until Y", "keep iterating until tests pass", "force this through with review", "research X exhaustively", "goal-loop: X with verification Y". Also handles cancellation when the user says "cancel the goal-loop" or "drop the loop".
allowed-tools: Read, Write, Edit, Bash, Agent, Glob, Grep
---

# Goal-loop

Set up a goal with a verification gate. The Stop hook reads goal-loop state files and blocks turn-end while any gate is unmet. The agent keeps working until the gate passes.

$ARGUMENTS

## When to use

Activate when the user signals "don't stop until X is true." Examples:
- "loop until `bun test` passes" - shell gate
- "don't stop until you've enumerated every possible cause" - self-verify gate
- "keep going until an isolated agent reviews and approves" - agent gate
- "research the OOM exhaustively" - self-verify gate with research-loop body
- "ship the auth refactor with tests green" - shell gate
- "fix every lint warning" - shell gate

If the user's task is one-shot ("just fix the bug") - don't activate. Goals are for "the agent should not stop until ..."

## Process

1. **Pick a slug** - kebab-case, descriptive: `auth-tests`, `oom-research`, `payment-review`. Used as the state filename.

2. **Pick a gate type** based on the user's request:

   | If verification is... | Use | How |
   |-----------------------|-----|-----|
   | A deterministic shell command (tests, build, lint, metric check) | **Shell gate** | Set `gate_command: <cmd>`. Hook runs it. exit 0 = pass. |
   | An isolated reviewer's judgment | **Agent gate** | Set `gate: not-met`. Each iteration, spawn `claude -p "<critic prompt>"` via Bash, parse output, update `gate: met` if approved or `gate_reason` with what's still wrong. |
   | The agent itself deciding (uncertainty resolved, exhaustively enumerated) | **Self-verify gate** | Set `gate: not-met`. Iterate, fill in working notes (uncertainty map, candidate space, etc.), update `gate: met` only when the criteria are honestly satisfied. |

3. **Write the state file** at `scratch/goal-loops/<slug>.md`:

   ```yaml
   ---
   task: <human-readable description>
   started: <today's date>
   # Exactly one of:
   gate_command: <shell command>     # shell gate
   # OR
   gate: not-met                     # model-verified gate (agent or self-verify)
   gate_reason: <why not yet met>
   ---

   <free-form body - working notes, uncertainty map, iteration log, review history>
   ```

   The body is yours - structure it for the gate type (see Examples below).

4. **Iterate.** Do the work. Update the body. The Stop hook gates your turn-end:
   - **Shell gate**: hook runs your command. If exit 0, you can stop. If non-zero, hook injects the failure output and you keep going.
   - **Model-verified gate**: hook reads the `gate:` field. If `met`, you can stop. If `not-met`, hook injects `gate_reason` and you keep going.

5. **Mark met** when honestly satisfied (model-verified gates only):
   ```
   gate: met
   ```
   Edit the state file. Next Stop will pass.

6. **Cancel** if the user says "cancel the goal" / "drop the loop" / "abandon this":
   ```bash
   rm scratch/goal-loops/<slug>.md
   ```

## Examples

### Shell gate: tests

User: "ship the auth refactor and don't stop until `bun test` passes"

Write `scratch/goal-loops/auth-tests.md`:
```yaml
---
task: ship auth refactor with tests green
started: 2026-05-06
gate_command: bun test
---

# Iteration log
- Initialized.
```

Then implement. The hook runs `bun test` after every turn. Exit 0 = ship allowed. Non-zero = failure output is injected, keep going.

### Agent gate: isolated reviewer

User: "keep iterating until an isolated agent reviews this diff and approves"

Write `scratch/goal-loops/diff-review.md`:
```yaml
---
task: ship diff with isolated reviewer approval
started: 2026-05-06
gate: not-met
gate_reason: no review yet
---

# Review history
```

Each iteration:
1. Make changes.
2. Run `claude -p "Review the staged diff in $(pwd). Output PASS or FAIL on the first line. If FAIL, list specific issues. Be strict."` via Bash.
3. Append the output to "Review history" in the state file.
4. If output starts with `PASS`, edit frontmatter to `gate: met`.
5. If `FAIL`, leave `gate: not-met` and update `gate_reason: <issues>`. The hook will block stop and inject the issues.

### Self-verify gate: research-loop

User: "research the OOM exhaustively before proposing a fix"

Write `scratch/goal-loops/oom-research.md`:
```yaml
---
task: diagnose OOM in data pipeline exhaustively
started: 2026-05-06
gate: not-met
gate_reason: candidate space not yet enumerated
---

# Candidate space
Enumerate every plausible source. 8+ for non-trivial. Different shapes - same-namespace siblings, different namespace, different tool family, code reasoning, historical precedent.

| # | Source | Why it might contain answer | Probe (one line) | Result |
|---|--------|------------------------------|------------------|--------|
|   |        |                              |                  | open   |

Status: `open` | `verified empty` | `partial match` | `promising` | `gold`. The answer is often a sum across `partial match` rows, not a single `gold`.

# Uncertainty map
| # | Unknown | Depends on | Status | Evidence |
|---|---------|------------|--------|----------|
|   |         |            | open   |          |

# Resolution log
- Initialized.

# Ship template (fill once gate is met)
## Result
## Confidence (per claim, with evidence row)
## Blocked on (rows that need external input)
```

Iterate. Fill rows. Probe sources. Resolve uncertainties. When every candidate is closed and every uncertainty resolved, edit `gate: met`.

## State file schema

```yaml
---
task: <required - human-readable>
started: <required - any date format>
# Exactly one of:
gate_command: <shell command>          # shell gate
# OR
gate: met | not-met                    # model-verified
gate_reason: <text>                    # only with gate field, optional
---

<free-form body>
```

Frontmatter parser is forgiving. Body is whatever the gate type calls for.

## Anti-patterns

- **Don't set `gate: met` without doing the work.** Model-verified gates trust you. Cheating defeats the point.
- **Don't pick a slow `gate_command`.** The hook runs it synchronously every Stop. For a 30-second test suite, accept the cost. For a multi-minute build, run it in the background and check a result file.
- **Don't reuse a slug.** If `scratch/goal-loops/<slug>.md` already exists, pick a different slug or cancel the old one first.
- **Don't activate for one-shot tasks.** "Fix this typo" doesn't need a goal. Goals are for tasks where premature stopping is the failure mode.

## Why this works

The Stop hook is the only mechanism that fires unconditionally at the thought-to-output boundary. Rule-in-prompt approaches fail under load - the agent doesn't notice the rule applies. State-file + Stop hook removes self-policing: even if the agent forgets, the gate enforces.

Spec: [`notes/goal-loop-primitive.md`](../../../notes/goal-loop-primitive.md). Hook: [`scripts/goal-loop-stop.sh`](../../../scripts/goal-loop-stop.sh).
