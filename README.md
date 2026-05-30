# only-agent

> The only agent you need.

Most setups today fragment AI into one Claude Code project per code repo. Switch repos, switch context, lose memory. **only-agent rejects that.** A single workspace where one general-purpose agent learns your environment and routes its own context across every repo, ticket, doc, and conversation.

- **Dynamic context loading** - The agent demand-loads what it needs from a knowledge tree shaped to your work. No per-repo Claude Code projects to maintain.
- **Self-organizing memory** - Knowledge accumulates as you work. When a topic outgrows its file, the system splits it into a subtree. `/maintain` compresses, deduplicates, fixes drift. Memory grows without slowing down.
- **One agent, every context** - Switch from a Jira ticket to a code review to a release note without changing tools. The agent picks up the right context from your message.

Built on top of [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview). No vendor framework. Plain markdown, plain hooks, plain MCPs.

---

## How it works

1. SessionStart hook loads the **domain router** (~50 lines: a map of "when to enter what world").
2. Your message signals which domain - work, personal, code review, etc.
3. The agent demand-loads the relevant **leaves** from the knowledge tree.
4. As you correct it, lessons get encoded into the right file.
5. Next session starts smarter.

Four layers:

| Layer | What | Loaded |
|-------|------|--------|
| **Engine** | Operating principles, identity, preferences | Every session |
| **Router** | Domain map | Every session |
| **Knowledge** | Domain leaves, system docs | On demand |
| **Action** | MCPs, CLIs, custom tools | When invoked |

Full design: [notes/architecture.md](./notes/architecture.md).

---

## Quick start

```bash
git clone https://github.com/darwinj07/only-agent ~/only-agent
cd ~/only-agent
./bootstrap.sh
```

Bootstrap takes ~30 seconds. It scaffolds your context tree, optionally symlinks repos, and offers to launch Claude to walk you through service connections. Identity (name/email/role) gets read from `git config` or asked by the agent on first use - no questions during bootstrap.

After bootstrap:

```bash
cd ~/only-agent
claude
```

Then either:
- Connect services: `"walk me through notes/connections.md"` (Slack, Notion, Jira, Datadog, Google Workspace, etc.)
- Build your work tree: `/onboard --quick` for a 10-15 min taste (~$1-2), or `/onboard` for the full 1-3 hour sweep across every connected service.
- Or just start working - context builds as you correct it. Today, the agent does NOT auto-record lessons; say "record this" to make a note stick. See [USING.md](./USING.md) for the day-to-day workflow.

See [EXAMPLES.md](./EXAMPLES.md) for sample prompts that demonstrate dynamic context loading.

---

## Skills

Three skills, all agent-invocable from natural language:

| Skill | When |
|-------|------|
| `/onboard` | First run after bootstrap - build initial work tree from real resources |
| `/maintain` | Weekly cleanup - compress, deduplicate, fix stale references |
| `/goal-loop` | Force the agent to keep iterating until a verification gate passes |

You don't have to type the slash command - say "set up my workspace" and `/onboard` activates. Say "clean up this mess" and `/maintain` activates. Say "don't stop until tests pass" and `/goal-loop` activates with a shell gate.

---

## What makes it different

**Tree primitive.** All persistent knowledge is a tree: `topic.md` is an index, `topic/*.md` are leaves. Outgrows its size budget? The leaf splits into a subtree. The model navigates by reading indexes and demand-loading leaves. No vector store needed - the filesystem IS the index. ([details](./notes/tree-primitive.md))

**Self-maintaining.** `/maintain` walks the tree, compresses always-loaded files ruthlessly, deduplicates across files, fixes broken refs, splits oversized nodes. Knowledge stays clean across thousands of sessions.

**/onboard.** Run once after bootstrap. Spawns parallel agents across the resources you have connected (repos, tickets, docs, monitoring, data) to build a working knowledge tree in 1-3 hours. Self-assesses readiness, closes gaps, hands back a report. Adapts to whatever services you have connected. **`/onboard --quick`** runs a single Codebase agent in 10-15 min (~$1-2) for evaluators who don't want to commit the full sweep yet. ([details](./.claude/skills/onboard/SKILL.md))

**Goal-loop: verify with commands, not vibes.** Claude Code's built-in `/goal` re-reads the *transcript* and continues until the agent's words look done - great for autonomy, but it trusts what the agent *says*. `/goal-loop` enforces a Stop-hook gate the agent cannot talk its way past: it runs your actual check - `bun test`, a build, a reviewer `claude -p "review this diff"`, or a model self-check - and only a passing exit code (or an explicitly asserted gate) ends the turn. If you have ever watched an agent declare victory on code that doesn't compile, that is the gap this closes. Drive with `/goal`, gate with `/goal-loop`. ([spec](./notes/goal-loop-primitive.md))

---

## Repository layout

```
.claude/rules/self.md          # Operating principles (the engine)
.claude/rules/learnings.md     # Your preferences (builds over time)
.claude/settings.json          # Hooks: context loading, safety, goal-loop gating
.claude/skills/                # /onboard, /maintain, /goal-loop
context/index.md               # Domain router (loaded every session)
context/<domain>/              # Domain knowledge (you and the agent build this)
context/shared/                # Cross-domain identity
notes/architecture.md          # Full design
notes/connections.md           # Service connection guide
notes/tree-primitive.md        # Storage model
notes/goal-loop-primitive.md   # Gated output loops spec
projects/                      # Symlinks to your repos (created during bootstrap)
tools/                         # Custom-built tools (slack, github helpers)
scripts/                       # Hook scripts
```

---

## Philosophy

- **Orientation over information.** Auto-loaded files give a compass, not a map. Demand-load the territory.
- **Earn your tokens.** Anything auto-loaded must justify its cost every session.
- **The model is the system.** The runtime is a ceiling, not a floor. Thinnest possible infrastructure, maximum model.
- **System and instance never mix.** Replace the user and their projects: system files still work, instance files don't.

The 3 operating principles in [self.md](./.claude/rules/self.md):
1. **Depth over speed** - map before moving, demand-load, converge.
2. **Every observation becomes an action** - encode immediately, logs are queues.
3. **Seek what you're not seeing** - external perspective, patterns as signals.

---

## Privacy

- **Bootstrap is local.** No `curl`, no `wget`, no telemetry. Pure shell + python3 + git. Read [bootstrap.sh](./bootstrap.sh) before you run it.
- **Two opt-in branches send data outward**, both behind explicit `[y/N]` prompts (default no): (a) the migration step uploads existing Claude Code memory files to Anthropic via `claude -p` for re-organizing, (b) the service-connect handoff launches Claude to walk you through MCP OAuth.
- **Knowledge stays as plain markdown on your disk.** No vector store, no remote indexer, no third-party sync.
- **The system runs on top of [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)**, so once you're using the workspace, your conversations and tool calls go to Anthropic per your Claude Code settings. If your threat model excludes Anthropic, this isn't the layer to evaluate - decide on Claude Code first.
- **The default `.claude/settings.json` permits broad `Bash(*)` / `Read(*)` / `Write(*)` / `Edit(*)`.** A `PreToolUse` hook blocks force-push, push to main/master, `git reset --hard`, and raw `gh pr create`. Tighten the allow-list in `settings.json` if you want stricter defaults.

## Contributing

Issues and PRs welcome. The system is designed to be forked - if you build something interesting on top, open a PR or share what you built.

## License

MIT - see [LICENSE](./LICENSE).
