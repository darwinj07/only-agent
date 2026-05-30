# Using only-agent

After bootstrap, six things to know. Read once. Refer back as needed.

## What "tree" means

Knowledge in only-agent is filesystem-shaped. A topic is either:
- A **leaf**: one file (e.g. `context/work/team.md`)
- A **branch**: an index file plus a sibling directory of leaves (e.g. `context/work/team.md` + `context/work/team/`)

When a leaf gets too big, it splits into a branch, and the agent files new knowledge in the right node. `/maintain` enforces this over time.

Full mental model: [notes/architecture.md](./notes/architecture.md).

---

## 1. The first prompt

Open Claude in this directory and try one of these:

```
let's get back on the X project
```

```
what was that bug we fixed last week in payment service?
```

```
draft an update to my manager about Q2 progress
```

The agent reads `context/index.md`, picks the right domain, and demand-loads the leaves it needs. You shouldn't have to explain "we work on Y" or "I'm responsible for Z" - that lives in your tree. (See [EXAMPLES.md](./EXAMPLES.md) for more.)

## 2. Run /maintain weekly

Compresses, deduplicates, fixes stale references. Catches bloat before sessions slow down. ~2 min.

## 3. It learns as you correct it

When you correct the agent or share a new fact, it encodes the lesson into the right file - a universal preference in `learnings.md`, a domain fact in that domain's leaf - so the next session starts with it. `/maintain` keeps those files clean over time.

## 4. Tell the agent to remove misleading knowledge

If you spot something wrong in rules/learnings, say **"delete this"** - not "note this as a past mistake." Past-failure entries pile up and slow every future session. Correct knowledge replaces wrong knowledge; it does not coexist with it.

## 5. Tell the agent to move misplaced knowledge

If you see a specific fact (a tool name, a path, a person) buried in a general file (`learnings.md`, `self.md`), say **"move this to the right leaf."** Universal files are for universal patterns. Specific stuff goes in scoped files where it loads only when relevant.

## 6. Trust dynamic context loading

You do not have to explain the project. The session loads relevant context based on your message. Just ask the question.

If it misses something, say **"load `<specific file>`"** once and continue. Then run `/maintain` so the index gets fixed.

---

## Skills cheat-list

All three are agent-invocable from natural language - the slash command is just the explicit way.

| Skill | Activate by saying... |
|-------|------------------------|
| `/onboard` | "set up my workspace", "scan my resources", "/onboard" |
| `/maintain` | "clean up the workspace", "compress this", "/maintain" |
| `/goal-loop` | "don't stop until tests pass", "loop until X", "research X exhaustively", "/goal-loop" |

`/goal-loop` picks a gate type from your phrasing:
- Shell verification ("until `bun test` passes") → runs the command, exit 0 = done.
- Agent verification ("until an isolated reviewer approves") → spawns `claude -p` with a critic prompt, parses output.
- Self-verification ("until you've enumerated everything") → agent maintains an uncertainty map, marks gate met when honestly satisfied.

To cancel: just say "cancel the goal-loop" or "drop the loop." It deletes the state file.

## Claude Code setup tips

These are about Claude Code itself, not only-agent. Worth doing once.

**Terminal**
- File paths in agent output are clickable. `cmd-click` (Mac) opens them. The `linkify` rule in `.claude/rules/self.md` ensures the agent renders paths in the right format.
- **Set a real editor as default for `.md` files** so clicking opens them in VS Code (or your editor of choice) instead of TextEdit/Preview. On Mac: right-click any `.md` file → Get Info → Open with → VS Code → Change All. Without this, half the agent's clickable links go to a useless preview.
- Ghostty users: enable `notify-on-command-finish` for tab notifications when long-running commands finish in unfocused tabs.

**Settings** (`~/.claude/settings.json`)
- `"autoMemoryEnabled": false` - only-agent uses its own contained knowledge tree, not the hidden `MEMORY.md`.
- `"cleanupPeriodDays": 99999` - never auto-delete transcripts. They become searchable history; prompt **"check session transcripts for X"** and the agent will grep past conversations.
- Customize `statusLine` to show context %, model, cost - make wasteful sessions visible.

**Effort & thinking depth**
- `/effort low|medium|high` per session.
- For persistent: `CLAUDE_CODE_EFFORT_LEVEL` env var or `"effortLevel"` in settings.json. `"xhigh"` is undocumented and goes beyond `/effort high`.
- `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` - your effort setting wins consistently instead of being dynamically adjusted.

**Add-ons** (one-time installs)
- [RTK](https://www.rtk-ai.app/) - `brew install rtk` + a PreToolUse hook. Rewrites common commands (`git status` -> `rtk git status`, `find` -> `rtk find`, `go test` -> `rtk go test`) to filter output before it hits context. Real-world: **95%+ token savings across 7,700+ commands**, near-100% on `go test`. Runs locally, zero API cost.
- LSP plugins via `/plugin install gopls-lsp@claude-plugins-official` (or `typescript-lsp`, `swift-lsp`). Real go-to-definition, references, diagnostics in agent context. Big uplift for code work.

**Navigation**
- **ESC twice** in chat → jump back to edit a previous message in the conversation.
- `claude --resume --fork` → start a new session forked from a past session at a chosen message. Useful for "what would have happened if I'd answered differently three turns ago."

## When you get stuck

| Symptom | Try |
|---------|-----|
| Agent loaded wrong context | "load `<specific file>`", then `/maintain` |
| Session too long | `/clear` - persistent context survives, fresh session restarts smarter |
| Rules file getting bloated | `/maintain` flags scope errors and dead anti-patterns |
| Agent stops before finishing analysis | Wrap the task: "don't stop until you've researched every angle" |

