# Context Router

The domain map. Loaded every session. Tells me what worlds exist and when to enter each one.

## Domains

*Not yet configured. Bootstrap will populate this.*

| Domain | Path | Activate when... |
|--------|------|-------------------|

## Activation Protocol
1. Session starts, this file loads (root of the domain routing tree)
2. User's message signals domain - pick it (or ask if ambiguous)
3. Load that domain's `index.md` + `learnings.md` (subtree root)
4. Within domain, load leaf files on demand per the domain index
5. Cross-domain requests load both domain indexes

## Shared Resources
Cross-domain files that any domain can reference:
- `context/shared/identity.md` - core identity (used everywhere)
