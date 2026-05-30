# Preferences (Universal)

Domain-specific preferences in `context/<domain>/learnings.md`.

## Identity
*Filled during bootstrap.*

## How [user] works
*Discovered through sessions. Add preferences as they emerge.*

## Style
*Discovered through sessions. Add preferences as they emerge.*

## Tool routing
*Discovered through sessions. Route each tool to one canonical method.*

## Context system
Knowledge is organized as trees (see tree primitive in `notes/architecture.md`). Domain routing is one instance:
- `context/index.md` - root, auto-loaded every session
- `context/<domain>/index.md` + `learnings.md` - loaded on domain activate
- Domain leaf files - on demand, per domain index
