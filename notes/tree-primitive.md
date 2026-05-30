# The Tree Primitive - Design Notes

A general-purpose scaling architecture for persistent LLM workspaces. (BETA)

## The Problem: Unbounded Growth

Persistent LLM workspaces hit the same wall: files grow without bound. MEMORY.md accumulates traps. Context files bloat with every project. Session state piles up. The model loads more tokens each session, context quality degrades, and eventually someone manually trims or starts over. This is the universal pain point of Claude Code (and any persistent agent workspace).

There's no built-in scaling mechanism. The filesystem stores files. The model reads them. Nothing manages the growth.

The tree primitive is that mechanism. It applies to any structured content that grows: knowledge, session state, project context, configuration. One pattern, universally applicable.

## Why Filesystem

An LLM agent needs persistent, navigable structured content. The options:

| Medium | LLM affinity | Structure | Shared? |
|--------|-------------|-----------|---------|
| Vector DB | Low (opaque retrieval) | Flat | No |
| Graph DB | Medium (needs query tool) | Rich | No |
| Custom format | Medium (needs parser) | Flexible | No |
| **Filesystem** | **Native** (Read, Glob, Grep) | **Hierarchical** | **Yes - that's the problem** |

The filesystem wins because the LLM already knows how to navigate it. No custom tools, no query languages, no embedding pipelines. `ls` a directory, read a file, grep for a term. The model's training data is saturated with filesystem navigation.

But the filesystem is shared territory. Repositories have their own conventions (README.md, go.mod, package.json). Claude Code expects specific paths (.claude/rules/, MEMORY.md). The knowledge tree must coexist with all of them without breaking anything.

## The Node Model

**Every filesystem path is a tree node.** Not just .md files - every file, every directory. The tree primitive is a perception of the filesystem, not a parallel system built on top of it.

A node is either:
- **Leaf**: a single file (any format)
- **Branch**: a file + sibling directory of the same name

### The Sibling Pattern

When a leaf outgrows its budget, it splits into a branch:

```
Before (leaf):
  api-traps.md              ← single file, 15KB, too big

After (branch):
  api-traps.md              ← index (orientation, pointers, ~20 lines)
  .api-traps/               ← hidden leaves dir (depth)
    google-docs.md
    slack.md
    linkedin.md
```

The file stays. A sibling directory appears. The address (`api-traps.md`) never changes for callers. External systems that depend on the file still work.

**Why not `name/index.md`?**

The alternative (replacing `foo.md` with `foo/index.md`) breaks external dependencies. MEMORY.md can't become `memory/index.md` because Claude Code auto-loads `MEMORY.md` specifically. README.md can't move because GitHub renders it. CLAUDE.md can't move because Claude Code expects it at the project root.

The sibling pattern (`name.md` + `.name/`) preserves the file AND adds structure. It's additive, not destructive. The dot prefix prevents conflicts with non-tree directories (a `work/` source dir won't be mistaken for a tree branch).

**Navigation advantage**: When an LLM lists a directory, it sees both index files and subdirectories at the same level. Each `.md` file orients; each sibling directory offers depth. With `index.md` inside directories, the LLM must enter each directory to find its identity - an extra navigation step at every level.

### Resolution

When reading a node at path `foo`:
1. Check `foo` (exact path - could be a file)
2. Check `foo.md` (leaf form)
3. Check `foo/index.md` (legacy form, for existing trees)

First match wins. Writing new nodes: always use the sibling pattern.

### Operations

| Operation | Description |
|-----------|-------------|
| **Read** | Read `name.md`. If it contains pointers, follow them into `name/`. |
| **Split** | File exceeds budget. Create `.name/`, extract subtopics as leaves, rewrite `name.md` as index. |
| **Collapse** | Directory has only trivial leaves. Merge content back into `name.md`, remove directory. |
| **Grow** | Add a new leaf to `.name/`. Update `name.md` index if needed. |

## Why This Works for LLMs

### Single file = whole context load

When an agent reads a file, it loads the ENTIRE thing. There's no way to read "just the section about Slack traps" from a 100-line MEMORY.md. The file is the atom of retrieval.

This means file boundaries ARE the chunking strategy. Smaller, focused files = better retrieval precision. The tree structure provides the navigation layer that connects them.

### Filesystem is the native interface

The LLM's tool palette for navigation:
- `Glob("context/**/*.md")` - find all knowledge files
- `Read("context/work.md")` - read an index
- `Grep("MPID", "context/.work/")` - search within a subtree

No custom tools needed. No query language. The agent uses the same tools for knowledge navigation and code exploration. This is the filesystem's killer advantage: zero impedance mismatch.

### But it's shared territory

The filesystem serves multiple masters:
- **Repositories**: README.md, go.mod, Makefile - conventions set by language/framework ecosystems
- **Claude Code**: .claude/rules/*.md, MEMORY.md, settings.json - paths dictated by the runtime
- **OS/tools**: .git/, node_modules/, .venv/ - tool-specific directories
- **The knowledge tree**: context/, notes/, memory/ - our structure

The tree primitive must layer on top without conflicting. The sibling pattern achieves this: it only ADDS files and directories, never moves or renames what's already there.

## Constraints and Tradeoffs

### What the filesystem can't do
- **Cross-cutting queries**: "find everything about iOS across all subtrees" requires reading every index or falling back to Grep. Trees are great for drill-down, bad for lateral search.
- **Semantic linking**: a note in `context/.work/` can't natively "link" to one in `context/.personal/`. Pointers are manual (write the path).
- **Atomic updates**: moving a node means updating both the file AND all pointers to it. No referential integrity.

### What it does well
- **Incremental growth**: add a leaf = create a file. O(1).
- **Bounded reads**: agent reads only what it navigates to. No index scan.
- **Universal tooling**: works with any editor, version control, shell.
- **Transparent**: `ls` shows you the full structure. No hidden state.

## Generality

The tree primitive is not a knowledge management system. It's a scaling layer for any structured content that grows in an LLM workspace:

- **Knowledge** (MEMORY.md, context files) - the obvious case. API traps accumulate, domain context expands.
- **Session state** (scratch/session/) - checkpoint trees grow as work progresses. Already using the pattern.
- **Project context** - project hubs, architecture docs, design specs. Any file that deepens over time.
- **Configuration** - CLAUDE.md, rules files. As the system evolves, these grow too.

The pattern is always the same: file exceeds budget -> split into branch (keep index, create `.name/` with leaves) -> address stays stable -> recursive if needed. One operation handles all growth.

**Why this matters**: Every persistent LLM workspace will hit the growth wall. The tree primitive is the first systematic answer that's filesystem-native (no infrastructure), self-maintaining (hooks detect when splits are needed), compatible (doesn't break anything), and recursive (handles arbitrary depth). It's not a convention for this workspace - it's a general architecture.

## Instances

Current applications:

| Instance | Index file | Sibling dir | Leaves | Split trigger |
|----------|-----------|-------------|--------|---------------|
| MEMORY.md | `MEMORY.md` | `memory/` | Topic-specific trap files | Node > ~50 lines |
| Domain knowledge | `context/work.md` | `context/.work/` | Domain context files | New subtopic |
| System docs | `notes/architecture.md` | `notes/architecture/` (if needed) | Deep-dive sections | Node > ~10KB |
| Session state | `scratch/session/index.md` | (within dir) | `completed/`, `research/` | Session outgrows one file |
| Code repos | `README.md` | (the repo itself) | Source files, packages | N/A (external convention) |

### Layer 1 as tree roots

Claude Code auto-loads certain files: CLAUDE.md, .claude/rules/*.md, MEMORY.md. These can't be moved. Under the tree primitive, they serve as **root nodes that happen to auto-load**:

- `MEMORY.md` → index for `memory/` subtree (technical traps)
- `self.md` → index for behavioral principles (leaves in `notes/` for specs)
- `learnings.md` → index for preferences (leaves in `context/shared/` for details)
- `CLAUDE.md` → root of roots (points to everything)

Their content should be **orientation, not depth**. Inline what changes behavior every session; point to leaves for everything else.

## Cross-References

The tree primitive handles vertical navigation (drill-down via indexes). Cross-references add lateral discovery - "what else relates to this?" - using filesystem-native HTML comments.

### Convention

```markdown
<!-- related: context/.work/built-tools.md, notes/architecture.md -->
```

- **Format**: `<!-- related: path1, path2, ... -->` - comma-separated, paths relative to workspace root
- **Placement**: Last line of file (metadata, not content)
- **Bidirectional**: If A references B, B should reference A. `/maintain` enforces this.
- **Optional**: Not every file needs one. Only add when a meaningful lateral connection exists that isn't already expressed by the tree structure (parent/child pointers).

### When to add

Add cross-references when:
- Two files discuss the same concept from different angles (e.g., design notes + implementation docs)
- A rule file references a detail file outside its subtree
- Knowledge in one domain connects to knowledge in another

Don't add when:
- The connection is already expressed by index pointers (that's the tree doing its job)
- The connection is trivial or obvious from the directory structure

### Validation

- **Read-time** (`tree-check.sh`): When reading any file with `<!-- related: -->`, the hook injects `RELATED: path1, path2` into model context - same pattern as TREE perception for branches.
- **Write-time** (`tree-check.sh`): After writing, validates each referenced path exists on disk. Warns on broken references.
- **Full audit** (`/maintain` step 5): Walks all managed `.md` files, collects cross-reference map, reports dead links, missing backlinks (A->B without B->A), and stale references.

---
*Captured from design discussion, 2026-03-03*
<!-- related: notes/architecture.md, .claude/rules/self.md -->
