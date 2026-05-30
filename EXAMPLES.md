# Example Prompts

Sample prompts that show off what only-agent does differently. Try these (or close variants) once you've connected a few services and run `/onboard`.

> **Note**: These work because the agent navigates a knowledge tree. The first time you use the workspace, the tree is sparse - prompts feel generic. After `/onboard` and 2-3 weeks of real work, prompts feel telepathic.

---

## 1. Pick up where you left off (no context dump)

```
let's get back on the X project
```

**What happens**: Agent reads `context/index.md` -> sees `work` domain -> reads `context/work/index.md` -> finds the project leaf -> loads what it needs. You don't have to re-explain what the project is.

If `X` is ambiguous, it asks. Once. Then never again.

---

## 2. "What was that bug?" (cross-session memory)

```
what was the bug we fixed last week in the payment service?
```

**What happens**: Agent reads `context/work/codebase.md` -> finds the payment service -> surfaces what it knows. No vector store. The filesystem IS the index.

If it's in your tree, the bug + fix lives in `context/work/payment-service/issues.md`. It loads only when relevant.

---

## 3. Switch domains mid-session

```
forget that. draft an email to my partner about dinner plans
```

**What happens**: Agent recognizes a personal-domain signal -> stops loading work context -> reads `context/personal/index.md` -> drafts an email in your voice (which it learned from `context/personal/learnings.md` over time). One agent. No tab switching.

---

## 4. Onboard a new project (use /onboard)

```
/onboard
```

**What happens**: Spawns parallel agents across each connected resource (repos, tickets, docs, monitoring, channels). 1-3 hours later: a populated `context/work/` tree. Self-assesses gaps. Loops to close them.

You don't sit there. Walk away. Come back to a workspace that knows your stack.

---

## 5. Self-cleanup

```
/maintain
```

**What happens**: Agent walks every persistence file. Compresses always-loaded files ruthlessly. Deduplicates across files. Splits oversized leaves into subtrees. Deletes dead anti-patterns.

Run weekly. The system stays fast across thousands of sessions.

---

## 6. Teaching it something mid-session

```
the staging deploy needs --no-cache when the protobuf changes,
otherwise it picks up cached generated code
```

**What happens**: The agent files the fact in the right leaf (`context/work/codebase.md`, or `context/work/deploy.md` if it exists) under the right section. Next session, you ask "how do I deploy staging?" and that note loads automatically.

---

## 7. Don't let the agent stop until the build passes

```
implement the new endpoint with error handling. don't stop until bun test passes.
```

**What happens**: Agent picks up the "don't stop until" phrase, activates `/goal-loop`, writes a state file with `gate_command: bun test`. The Stop hook runs `bun test` after every turn. If it fails, the failure output is injected and the agent keeps going. Can't ship until tests pass.

Same primitive works for anything: "until lint is clean", "until the build succeeds", "until an isolated reviewer approves" (agent gate, spawns `claude -p "review this"`).

---

## 8. Don't let the agent ship a half-baked answer

```
research the OOM in the data pipeline exhaustively before proposing a fix
```

**What happens**: Agent activates `/goal-loop` with a self-verify gate. Builds an uncertainty map, enumerates candidate sources (memory leak in worker? GC tuning? upstream burst? bad query plan?), probes each, resolves uncertainties. Can't stop until every row is closed and the gate field flips to `met`. No shipping a guess.

---

## 9. Drift correction

```
that's wrong. delete that learning - it was a one-off, not a pattern
```

**What happens**: Agent finds the entry in `learnings.md` or wherever it lives, removes it. Says "deleted." No "noted as a past mistake" entries that pile up forever.

This is the underrated workflow: **correct knowledge replaces wrong knowledge; it does not coexist with it.**

---

## What none of these need

- "First, let me explain my project: [50 lines of context]"
- "I'm a software engineer working on [team] at [company]..."
- "We use [stack]. The relevant files are [list]..."
- "Last week I asked you about [topic], you said [paraphrase]..."

The tree carries this. You skip the preamble and get to the question.

That's the value: **dynamic context loading + self-organizing memory** = one agent that picks up the right context from your message, every time.

---

*If you build a workflow on top of this that works well, share it - PRs welcome.*
