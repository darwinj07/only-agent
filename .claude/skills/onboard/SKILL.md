---
name: onboard
description: Build the initial work tree by scanning real resources (repos, tickets, docs, monitoring, data) in parallel. Full mode spawns 5+ agents and runs 1-3 hours autonomously; `--quick` mode runs one Codebase agent in 10-15 min (~$1-2) for evaluators. Use after bootstrap when the user says "onboard me", "set up my workspace", "scan my resources", "build my context", "/onboard", "/onboard --quick", "give me a quick taste".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, WebFetch
---

# Onboard

Bootstraps the user's primary domain tree from real resources (code, tickets, docs, monitoring, data) using parallel agents and self-assessment loops. Runs autonomously for 1-3 hours.

Output: a working knowledge tree in `context/<DOMAIN>/`, ready to support real tasks.

`<DOMAIN>` is resolved in Phase 0 from `context/index.md`. Default convention: `work`. If the user picked custom domains during bootstrap, the skill targets the first non-`personal` domain (or asks if ambiguous).

$ARGUMENTS

## When to run

After `bootstrap.sh` completes. The user has identity files and connected services but no domain knowledge yet. This skill builds the initial knowledge tree for the primary domain.

If `context/<DOMAIN>/` already contains substantive files, ask the user before continuing. Do not silently overwrite.

## Inputs (mostly auto-detected)

The skill reads what bootstrap already captured. It asks once for anything missing, then runs uninterrupted.

| Seed | Where it comes from |
|------|---------------------|
| Name, manager (if any), team/role | `context/shared/identity.md` (set by bootstrap) |
| Main repo(s) | `projects/` symlinks (set by bootstrap, or by Pre-flight) |
| Onboarding doc / overview | `$ARGUMENTS` if provided. Otherwise asked once in Phase 0; user can skip - the breadth phase discovers docs from connected sources. |

`$ARGUMENTS` is optional. Examples:
- `/onboard` - full run, reads everything from local state, asks for doc if missing
- `/onboard --quick` - quick mode (see below): one breadth agent on the Codebase category, ~10-15 min wall time
- `/onboard doc=<url>` - skips the doc question
- `/onboard manager="Jane Doe" repo=/abs/path doc=<url>` - full override (rare)

After Phase 0, no more questions until the run completes.

## Quick mode (`--quick`)

Activate when the user says "quick", "fast", "demo", "minimal", "give me a taste", or passes `--quick` in `$ARGUMENTS`. Use case: redditor evaluating only-agent in 15 minutes; first-time user who wants to see what /onboard produces before committing 1-3 hours.

Quick mode collapses the full pipeline to a single breadth agent on one category:

1. **Phase 0 abbreviated**: resolve `<DOMAIN>` (same rule), pick the primary repo from `projects/` (first symlink, or ask if multiple). Skip Phase 1b/2/3 planning.
2. **One Agent**: spawn a single breadth agent for the **Codebase** category only. Writes to `context/<DOMAIN>/codebase.md`.
3. **Hand back**: print path to the file, line count, suggested next steps ("ask me about X to verify; run `/onboard` (no --quick) for the full sweep").

Target: 10-15 min wall time, ~50-100K tokens. Roughly $1-2 of API usage.

What quick mode does NOT do: depth sweep, self-assessment, gap-closing loops, multiple categories, ticket/doc/Slack scans. Those are full-`/onboard` only.

## Capability detection

Before starting, **detect which services are connected** and adapt. This skill is service-agnostic - missing tools degrade coverage but do not block the run.

Read `~/.claude/settings.json` and `~/.claude.json` for `mcpServers` entries. Match each entry to a category:

| Connected service | Enables category |
|-------------------|------------------|
| GitHub (`gh` CLI available) | Codebase, code conventions |
| Atlassian MCP | Tickets / project mgmt |
| Notion MCP | Documentation |
| Slack MCP | Team channels, recent incidents |
| Google Workspace MCP | Shared docs, runbooks |
| Datadog MCP | Alerts, monitors, recent incidents |
| BigQuery / Snowflake / DB CLI | Data category |
| Linear / Trello / other PM MCPs | Tickets / project mgmt |
| Glean / enterprise search MCP | Cross-system documentation |

Skip categories for services that aren't connected. The final report flags which categories were skipped.

If the user has only `gh` connected and nothing else, this run is a code-focused onboard. That's fine - it's still useful.

## Process

### Pre-flight: Repo discovery (if `projects/` is empty)

Run `ls projects/`. If empty (no symlinks), repos were not collected during bootstrap. Discover and link before continuing:

1. Probe filesystem: `find $HOME -maxdepth 3 -name .git -type d 2>/dev/null` to find git roots. Skip `.git` inside `node_modules`, `vendor`, `.cache`.
2. Group candidates by parent directory. Show the user a numbered list with last-modified dates.
3. User picks which to symlink (numbers, "all", or paths).
4. For each chosen repo: `ln -s "$ABS_PATH" "projects/$(basename $ABS_PATH)"`.
5. Confirm with `ls -la projects/`.

If `projects/` already has symlinks, skip this step.

### Phase 0: Confirm and proceed

1. **Resolve `<DOMAIN>`.** Read `context/index.md`. Pick the target domain in this order:
   - If a domain named `work` exists, use `work`.
   - Otherwise, use the first non-`personal` domain in the table.
   - If only `personal` exists or it is ambiguous, ask the user once: "Which domain should I populate?"
   Treat the resolved name as `<DOMAIN>` for the entire run. Every reference to `context/<DOMAIN>/...` below applies to that resolved path.

2. **Auto-detect seeds.**
   - Read `context/shared/identity.md` for name, team, manager
   - Read `projects/` for main repo(s)
   - Detect connected services (capability map above)
   - Apply `$ARGUMENTS` overrides on top

3. **Ask only what is missing.** Single round of questions, then no more until done.
   - Identity gaps (rare - bootstrap usually fills these)
   - No repo and Pre-flight added none -> ask
   - No doc -> ask, but accept "skip" - breadth phase will discover

4. **Confirm to the user.**
   - Target domain (`<DOMAIN>`) and seeds locked (auto-detected + answered)
   - Plan: Phase 1 -> Phase 1b -> Phase 2 -> Phase 3, looping until gaps are small
   - Estimate: 1-3 hours, mostly autonomous
   - Output: filled `context/<DOMAIN>/` tree, gap report, list of unresolved items
   - Capability map (which categories are full vs degraded vs skipped)

5. **User approves with a single message.** Then run.

### Phase 1: Acquire (parallel breadth scan)

Spawn agents in parallel via the `Agent` tool, **one per available category**. Each writes to its own file under `context/<DOMAIN>/`.

Standard categories (skip those with no source connected):

| Axis | Agent task | Writes to | Needs |
|------|-----------|-----------|-------|
| Team | Manager, peers, reports, charter, recent goals/OKRs. | `context/<DOMAIN>/team.md` | Slack and/or PM tool and/or doc tool |
| Codebase | Main repos, structure, build, deploy, recent activity. | `context/<DOMAIN>/codebase.md` | GitHub / `gh` |
| Tickets | Active tickets, recent epics, sprint cadence. | `context/<DOMAIN>/tickets.md` | Jira / Linear / etc. |
| Documentation | Internal docs, architecture diagrams, runbooks. | `context/<DOMAIN>/docs.md` | Notion / Confluence / Drive / Glean |
| Communication | Team channels, oncall, alerts. | `context/<DOMAIN>/slack.md` (or rename to your tool) | Slack or equivalent |
| Conventions | PR style, commit format, code review norms. | `context/<DOMAIN>/conventions.md` | GitHub (recent PRs, CONTRIBUTING.md) |
| Stack | Languages, frameworks, infra. | `context/<DOMAIN>/stack.md` | Local repo analysis (no MCP needed) |
| Data | Datasets/tables the team owns. | `context/<DOMAIN>/data.md` | BigQuery / Snowflake / data catalog MCP |

After all return, write `context/<DOMAIN>/index.md` summarizing the topology and pointing to each leaf.

### Phase 1b: Depth sweep (operational reality)

Phase 1 maps what the system *is*. Phase 1b maps what it *does wrong* and who cares. Senior engineers carry this knowledge; docs do not capture it.

Spawn additional parallel agents on whatever sources are available:

| Axis | Agent task | Appends to | Needs |
|------|-----------|------------|-------|
| Alerts & Monitors | Monitor configs, severity, who pages. | `context/<DOMAIN>/oncall.md` (new) | Datadog / equivalent |
| Data Consumers | Who queries the team's tables, downstream pipelines, data contracts. | `context/<DOMAIN>/data.md` | Data + Slack/docs to find consumers |
| Recent Incidents | Threads in oncall channels, postmortems, failure patterns. | `context/<DOMAIN>/oncall.md` | Slack + PM/doc tool for postmortems |
| Cross-team Interfaces | Which teams escalate to/from this team, why, key contacts. | `context/<DOMAIN>/team.md` | Slack and/or PM tool |
| Feature Flags / Runtime Config | Flag systems, ramp states, recent flag-driven changes. | `context/<DOMAIN>/runtime-config.md` (new) | Repo analysis or feature flag MCP if connected |

### Phase 2: Challenge (self-assess)

After Phase 1 and 1b complete, run a meta prompt. The model evaluates its own readiness:

> Are you truly ready to show senior-level performance week one? Be honest. Show me what you have vs what you are missing. Produce a have / have-not table.

Save the resulting gap table to `scratch/onboard-gaps-<ISO_TIMESTAMP>.md`. Do not skip this step - self-assessment generates better targeting than a human prompt could.

### Phase 3: Close gaps

For each gap in the table:
- Spawn an `Agent` targeted at that specific gap
- The agent updates the relevant existing file (do not create one-off scratch files)
- Mark the gap as closed in the gap-table file when its source file is updated

Run agents in parallel where they touch different files. Serial when the same file is target.

### Loop: Phase 2 -> Phase 3 until done

After each Phase 3 round, re-run Phase 2. Repeat until the gap table is acceptably small:
- Rule of thumb: < 3 critical gaps, < 10 minor gaps
- Hard cap: 5 loops. After 5, hand back what is unresolved.

### Final: Hand back

Report to the user:
- Files created in `context/<DOMAIN>/` (count, names, line totals)
- Gaps closed vs remaining (with the latest gap table linked)
- Axes skipped due to missing tools (from capability detection)
- Unresolved items needing user input (credentials, access, ambiguous decisions)
- Suggested first task: pick one item the user can verify, e.g. "ask me a question about [X]; I should know."

Do not exit until the user confirms the report is complete.

## Anti-patterns

- **Do not ask the user mid-run.** Confirm and lock inputs in Phase 0, then go.
- **Do not spawn serial agents when parallel works.** Phase 1 = up to 8 parallel, Phase 1b = up to 5 parallel.
- **Do not assume a specific stack.** This skill works for an indie dev with just GitHub *and* an enterprise engineer with the full set. Detect, don't assume.
- **Do not stop at breadth.** Phase 1b is non-optional when sources allow it.
- **Do not skip Phase 2.** Self-assessment closes the loop.
- **Do not mark gaps closed without writing to a file.** Closure means persistent.
- **Do not write to `scratch/` for permanent knowledge.** Only the gap-table goes there.
- **Do not loop forever.** Hard cap at 5 Phase 2/3 rounds.

## See also

- `notes/connections.md` - for the user, if a prereq is missing
- `USING.md` - what the user reads after this skill completes
