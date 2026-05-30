---
name: maintain
description: Cleanup pass on the workspace - compress always-loaded files, deduplicate across files, fix stale references, split oversized leaves into subtrees, propose structural improvements. Run weekly. Use when the user says "clean up the workspace", "maintenance", "tidy up", "compress this", "fix stale stuff", "the workspace is bloated", "/maintain".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Maintain

Two jobs: keep the system clean, and make it smarter. Cleanup AND structural evolution.

$ARGUMENTS

## Scope

Everything in the persistence system. Enumerate targets from `architecture.md` Directory Contract and domain indexes - don't rely on a hardcoded list.

**What to touch:**
- All Layer 1 files (`.claude/rules/*.md`) - compress, deduplicate
- All domain indexes and their referenced leaves - sync with disk, fix staleness
- All staging files (`self-assessment.md`) - graduate or delete
- All skills (`skills/*/SKILL.md`) and scripts (`scripts/`) - verify correctness
- Settings (`settings.json`) - verify hooks match scripts on disk
- Notes (`notes/`) - check for stale dates, cross-file contradictions
- Built tools registries - sync with what's actually in `tools/`

## Process

### 1. Audit (read everything, touch nothing)

Read ALL persistence files. Build a model of:
- Duplicated across files
- Stale (old paths, completed work, outdated references)
- Verbose (could be shorter without losing meaning)
- Staging entries ready to graduate (confirmed across 2+ sessions or by user)
- Staging entries to delete (disproven or already graduated)
- Files on disk not in index, or index entries with no file
- Tools on disk not in built-tools.md
- Contradictions between files
- Misplaced entries: specific facts (tool names, file paths, people) in universal files (`learnings.md`, `self.md`) - belong in scoped leaves
- Dead anti-patterns: "don't do X" entries paired with their corrected "do Y" rule - the warning is redundant once the right rule exists

### 2. Compress

Compression policy depends on layer (see architecture.md Layers table):
- **Layer 1 (engine)**: Aggressive. Merge overlapping rules, shorten to single lines, remove examples that repeat the rule, delete one-time "don't do X" entries. Test: if removing a sentence doesn't change behavior, remove it.
- **Layer 2 (router)**: Keep to orientation. Pointers, not content.
- **Layer 3 (reference)**: Compress for clarity, not brevity. Analysis, design rationale, and depth are the value. Don't strip intellectual content just because it's long.

### 3. Deduplicate and verify consistency

Cross-file dedup:
- `learnings.md` = preferences and patterns. `self.md` = operating principles. Same info in both -> keep in the right one, delete from the other.

Scope correctness:
- Specific facts (tool names, file paths, people) in universal files (`learnings.md`, `self.md`) load every session even when irrelevant. Move them: tool-specific -> tool's own leaf, domain-specific -> `context/<domain>/rules.md`, person-specific -> identity / contact files.
- Detection: scan Layer 1 files for entries mentioning specific tool names, paths, or people. Those are scope errors waiting to be moved.

Dead anti-patterns:
- "Don't do X" entries paired with the corrected "do Y" rule are dead weight - the warning is redundant once the right rule exists. Action: delete the anti-pattern entry, keep only the live rule. Do NOT preserve "we used to do X" as a learning - that's the failure log, not knowledge.
- Exception: if a fresh user might re-derive the wrong approach, keep a one-liner ("avoid X because Y"). Litmus test: without the warning, would someone fresh re-discover the wrong approach? If no, delete.

Cross-file consistency:
- Reference docs (architecture.md, capabilities.md, notes/) intentionally duplicate some info for different readers. Verify the copies match. If they diverge, update the stale copy from the canonical source.
- Skills should NOT duplicate Layer 1 info (file paths, routing tables) - the model already has it in context when skills run.

### 4. Graduate staging entries

For entries in `context/self-assessment.md` and `context/<domain>/self-assessment.md`:
- **Confirmed** (2+ sessions or explicit user validation): Move rule to target file (self.md or learnings.md). Delete from staging.
- **Already graduated** (rule exists in target): Delete from staging.
- **Disproven** (no longer relevant): Delete from staging.
- **Uncertain**: Flag in report, don't touch.

### 5. Fix stale references

- Verify all file paths in rules actually exist. Remove dead pointers.
- Check tool routing entries match current tool availability.
- Check `built-tools.md` entries point to existing scripts. Add undocumented tools.
- Sync index with disk: add files not in index, remove entries for deleted files.
- Update staleness flags and dates.

### 6. Split oversized files (soft signal, not a hard gate)

Sizing is a signal, not a rule. A cohesive single-topic file can run long - splitting it just creates artificial navigation hops between things that belong together. Split only when a file is BOTH over budget AND covers multiple distinct `## ` sections that don't heavily cross-reference.

Budgets: knowledge leaves ~20KB soft / 30KB hard cap; indexes ~8KB soft; Layer 1 (`.claude/rules/*.md`) ~10KB.

To split: create the `name/` subtree, extract each section as a leaf, rewrite `name.md` as an index (overview + a "Leaves" table with "read when..." guidance), and point the parent index at it. Report what you split, not what you considered.

### 7. Structural review

The full system is now in context. Use that to think about whether the structure itself is right.

- Do any files always get loaded together? Should they merge?
- Are there files that never get loaded? Dead weight?
- Do recent session trees (`scratch/sessions/`) reveal recurring patterns that need new structure (new context files, new tools, new skills)?
- Do Layer 1 files still earn their always-loaded token cost? Is anything there that should be on-demand instead?
- Has any domain, tool, or workflow outgrown its current home?
- Are the skills and hooks still the right set? Should any be added, removed, or combined?
- Are there manual multi-step patterns that should be scripts or skills?

Act on clear improvements. Propose and ask for input on larger structural changes.

### 8. Report

Print summary:
- Entries graduated (from staging -> which file)
- Entries deleted (stale/duplicate/disproven)
- Lines saved (before vs after, per file)
- Stale references fixed
- Index corrections
- Structural proposals (with rationale)
- Anything needing user input

### 9. Reset the maintenance tracker

Last action of every run. Reset the counter the SessionStart hook (`scripts/session-audit.sh`) reads - without this, "N sessions since last /maintain" counts forever and the warning means nothing:

```
echo 0 > "$CLAUDE_PROJECT_DIR/context/.session-count"
date +%Y-%m-%d > "$CLAUDE_PROJECT_DIR/context/.last-maintain"
```

## Anti-patterns

- Don't rewrite working rules to "improve" phrasing.
- Don't delete entries you're unsure about - flag them.
- Don't count lines obsessively. Goal is clarity, not minimalism.
