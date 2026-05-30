# AI Workspace

Home of the only-agent system. Not a code project - a persistent AI workspace where context and memory accumulate across sessions.

## System
- Principles: `.claude/rules/self.md`
- Preferences: `.claude/rules/learnings.md`
- Domain router: `context/index.md` (loaded every session by hook)
- Architecture: `notes/architecture.md`
- Setup guide: `notes/connections.md`

Nothing here is sacred. Rules serve goals. Change what isn't working.

## Bootstrap

Run `./bootstrap.sh` for first-time setup. It scaffolds the context tree, optionally symlinks your repos, and offers to launch Claude for service connections. Identity (name, email, role) gets read from `git config` or asked by the agent on first use - no questions during bootstrap.

After bootstrap:
1. Connect services (`notes/connections.md`) - Slack, Notion, Jira, Datadog, Google Workspace, etc.
2. Build your work tree: run `/onboard` to scan your resources in parallel.
3. Read `USING.md` - the day-to-day cheatsheet.

## Skills

All agent-invocable from natural language. No need to type the slash command.

| Skill | When |
|-------|------|
| `/onboard` | After bootstrap - build initial work tree from real resources |
| `/maintain` | Weekly cleanup - compress, deduplicate, fix stale references |
| `/goal-loop` | Force the agent to keep iterating until a verification gate passes (shell command, isolated agent reviewer, or model self-check) |

Spec for `/goal-loop`: `notes/goal-loop-primitive.md`. Hook: `scripts/goal-loop-stop.sh`.

## Instance

*Not yet configured. Run `./bootstrap.sh` to set up.*
