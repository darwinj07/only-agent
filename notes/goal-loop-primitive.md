# Goal-loop Primitive

Infrastructure for structured, gated work. State-file-driven. Stop hook enforces the gate so self-policing is not required.

## Problem

Abstract principles ("don't ship claims built on uncertainty", "don't stop before tests pass") fail to fire under load. The agent can know the rule and still violate it.

The fix is structural: the harness blocks `Stop` until a machine-checkable or model-asserted condition is met.

## Shape

A goal-loop is defined by two parts:

| Part | What |
|------|------|
| **State** | A markdown file at `scratch/goal-loops/<slug>.md`. Frontmatter declares the gate; body is free-form working memory. |
| **Gate** | A condition the Stop hook evaluates every time the agent tries to end its turn. Blocks stop when not met. |

There is **one primitive** (state file + Stop hook) and **two gate mechanisms** that cover everything:

| Mechanism | Frontmatter key | Hook behavior | Use when |
|-----------|-----------------|---------------|----------|
| **Auto-verified** | `gate_command: <shell cmd>` | Hook runs the command each Stop. exit 0 = met. Non-zero exit + stdout/stderr = block reason. | Anything testable by a command: tests, builds, linters, metric thresholds, file-existence checks, HTTP probes, custom scripts. |
| **Model-verified** | `gate: met \| not-met` + optional `gate_reason: <text>` | Hook reads the field. `met` passes. Anything else blocks with `gate_reason`. | Judgment calls: uncertainty resolution, isolated agent review, human approval, anything where a shell command can't compute the answer. |

Any gate type maps to one of these two mechanisms.

## State file schema

```yaml
---
task: <required - human-readable description>
started: <required - any date format>
# Exactly one of:
gate_command: <shell command>          # auto-verified
# OR
gate: met | not-met                    # model-verified
gate_reason: <text>                    # only with gate field, optional
---

<free-form body>
```

## Gate type examples

| Gate type | Mechanism | Example frontmatter | Body |
|-----------|-----------|---------------------|------|
| Tests pass | auto-verified | `gate_command: bun test` | Iteration log |
| Build pass | auto-verified | `gate_command: cargo build --release` | Iteration log |
| Lint clean | auto-verified | `gate_command: bun lint` | Iteration log |
| Metric threshold | auto-verified | `gate_command: ./scripts/check-metric.sh error_rate '<' 0.01` | Metric history |
| File pattern present | auto-verified | `gate_command: grep -q 'SHIP OK' path/to/output.md` | Work log |
| Isolated agent review | model-verified | `gate: not-met`, `gate_reason: reviewer flagged X` | Review history; agent spawns `claude -p`, parses, updates |
| Research / uncertainty resolution | model-verified | `gate: not-met`, `gate_reason: row 2 open` | Candidate space + uncertainty map + resolution log |
| Human approval | model-verified | `gate: not-met`, `gate_reason: awaiting user ack` | Context; agent updates when user says approved |

The auto-verified column is robust. The model-verified column is flexible. Use auto-verified when possible.

> **Note**: `gate_command` is executed via `bash -c` by the Stop hook (`scripts/goal-loop-stop.sh`). It is the user's (or agent's) own shell command - same trust level as anything else the agent runs. If your threat model worries about agent-authored shell commands, set narrower `Bash(...)` allow patterns in `.claude/settings.json` and the `PreToolUse` guard will still see them.

## Why Stop hook, not prompt-level rule

| Approach | Fails when |
|----------|-----------|
| Rule in prompt ("don't ship with uncertainties") | Agent doesn't notice the situation matches the rule |
| UserPromptSubmit hook injection | Fires once at turn start, doesn't gate output |
| Subagent for verification | Subagent doesn't see main-context artifacts by default |
| **Stop hook reading state file** | Works. Auto-verified gates are bulletproof. Model-verified gates can be gamed, but the state file (with named gate_reason) raises the bar. |

Stop hook is the only mechanism that acts at the thought-to-output boundary unconditionally, without requiring the agent to self-activate it.

## Files

| Path | Purpose |
|------|---------|
| `.claude/skills/goal-loop/SKILL.md` | The skill the agent invokes from natural language. Writes the state file. |
| `scripts/goal-loop-stop.sh` | Stop hook. Parses `scratch/goal-loops/*.md`, dispatches on gate_command vs gate field. |
| `.claude/settings.json` `hooks.Stop[0]` | Where the Stop hook is wired. |

## Adding gate types

**Auto-verified** (hook runs your command): write a shell command or script that returns exit 0 when "done". Set as `gate_command` in the state file. No new code required.

**Model-verified** (agent updates state): set `gate: not-met`. The skill body explains how the agent decides "met" and updates the field. No hook change required.

The hook itself only changes if a new dispatch mechanism is needed beyond shell-run and field-read.

## Known gaps

- **Slow shell commands**: hook runs the command synchronously. A 30-second test suite stalls Stop by 30 seconds. Acceptable for most. For long-running checks, run in the background and have a quick `gate_command` check the result file.
- **Output truncation**: hook shows last 20 lines of failing command output. For longer output, run the command directly.
- **Model-verified gate cheating**: agent can flip `gate: met` without doing the work. Mitigation is naming the gate reason explicitly so the cheat shows up in the state file. If cheating becomes a pattern, add a verification step.

<!-- related: .claude/rules/self.md, scripts/goal-loop-stop.sh, .claude/skills/goal-loop/SKILL.md, notes/architecture.md -->
