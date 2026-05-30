# only-agent

> The only agent you will ever need. One workspace and one agent for all your repos, tickets, and docs - no more switching between Claude Code projects.

Most people run a separate Claude Code project per repo. You switch repos, switch context, and re-explain your stack. **only-agent rejects that.** A single workspace where one general-purpose agent learns your environment and routes its own context across every repo, ticket, doc, and conversation - ever-growing along with you.

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
- Or just start working - context builds as you correct it. See [USING.md](./USING.md) for the day-to-day workflow.

See [EXAMPLES.md](./EXAMPLES.md) for sample prompts that demonstrate dynamic context loading.

---

## The filesystem is the index

No vector database, no embeddings, no retrieval service. Knowledge is plain markdown in a tree: `topic.md` is an index, `topic/*.md` are the leaves. When a leaf gets too big it splits, and its path stays the same so nothing that points at it breaks:

```text
codebase.md  (32KB, bloated)   ->   codebase.md   (index, ~20 lines)
                                     codebase/checkout-svc.md
                                     codebase/mobile-api.md
                                     codebase/deploy.md
```

The agent navigates it with the same `Read`, `Glob`, and `Grep` it uses on your code. You can read your agent's entire memory in an editor, grep it in a shell, and diff it in git. That is the whole storage engine. ([how and why](./notes/tree-primitive.md))

## Skills

Three, all invocable from plain English - the slash command is just the explicit form.

| Skill | Say something like | What it does |
|-------|--------------------|--------------|
| `/onboard` | "set up my workspace" | Spawns parallel agents across your connected resources to build your initial tree. |
| `/maintain` | "clean up the workspace" | Weekly pass: compress, deduplicate, fix stale references, split oversized files. |
| `/goal-loop` | "don't stop until tests pass" | Will not let the agent end its turn until a real check passes. |

`/goal-loop` is worth one extra note. Claude Code's built-in `/goal` re-reads the transcript and stops when the agent's words look done - it trusts what the agent says. `/goal-loop` runs your actual command (`go test ./...`, a build, a linter, a `claude -p` reviewer) and only a passing exit code ends the turn. If you've ever watched an agent declare victory on code that doesn't compile, that's the gap it closes. Drive with `/goal`, gate with `/goal-loop`. ([spec](./notes/goal-loop-primitive.md))


---

## Isn't this just a big CLAUDE.md?

Close to the opposite. A `CLAUDE.md` loads in full every session and only grows. only-agent keeps the always-loaded part tiny (the router) and demand-loads the rest, so it stays fast as the knowledge grows. `/maintain` keeps the loaded files compressed and free of drift.

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
tools/                         # Custom-built tools (github helpers)
scripts/                       # Hook scripts
```

---

## Philosophy

- **Orientation over information.** Auto-loaded files give a compass, not a map. Demand-load the territory.
- **Earn your tokens.** Anything auto-loaded must justify its cost every session.
- **The model is the system.** The runtime is a ceiling, not a floor. Thinnest possible infrastructure, maximum model.
- **System and instance never mix.** Replace the user and their projects: system files still work, instance files don't.

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
