#!/bin/bash
# session-audit.sh - SessionStart hook
# Checks context health and injects warnings into session context.
# Output goes to stdout (injected into model's context by the hook).
# BETA: Testing automated self-maintenance (2026-02-13)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CONTEXT_DIR="$PROJECT_DIR/context"
MAINTAIN_TRACKER="$CONTEXT_DIR/.last-maintain"
SESSION_COUNTER="$CONTEXT_DIR/.session-count"

WARNINGS=""
warn() { WARNINGS="${WARNINGS}⚠ $1\n"; }

# --- Count sessions since last maintain ---
COUNT=0
if [ -f "$SESSION_COUNTER" ]; then
    COUNT=$(cat "$SESSION_COUNTER" 2>/dev/null || echo 0)
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$SESSION_COUNTER"

PRUNE_INTERVAL=10
if [ "$COUNT" -ge "$PRUNE_INTERVAL" ]; then
    warn "It's been $COUNT sessions since last /maintain. Context files may have stale or bloated content. Run /maintain early this session."
fi

# --- Check for oversized context files ---
# Limits in bytes. ~10KB general, ~5KB indexes, ~7KB MEMORY.md
SIZE_LIMIT=10240
INDEX_LIMIT=5120
MEMORY_LIMIT=7168

human_size() { echo "$(( ($1 + 512) / 1024 ))KB"; }

while IFS= read -r -d '' FILE; do
    BYTES=$(wc -c < "$FILE" | tr -d ' ')
    BASENAME=$(basename "$FILE")
    RELPATH="${FILE#$PROJECT_DIR/}"

    if [ "$BASENAME" = "index.md" ]; then
        if [ "$BYTES" -gt "$INDEX_LIMIT" ]; then
            warn "$RELPATH is $(human_size $BYTES) (index limit: $(human_size $INDEX_LIMIT)). Consider splitting into subtree."
        fi
    else
        if [ "$BYTES" -gt "$SIZE_LIMIT" ]; then
            warn "$RELPATH is $(human_size $BYTES) (limit: $(human_size $SIZE_LIMIT)). Consider splitting into subtree."
        fi
    fi
done < <(find "$CONTEXT_DIR" -name "*.md" -not -path "*/\.*" -print0 2>/dev/null)

# Also check rules files
while IFS= read -r -d '' FILE; do
    BYTES=$(wc -c < "$FILE" | tr -d ' ')
    RELPATH="${FILE#$PROJECT_DIR/}"
    if [ "$BYTES" -gt "$SIZE_LIMIT" ]; then
        warn "$RELPATH is $(human_size $BYTES) (limit: $(human_size $SIZE_LIMIT)). Consider splitting."
    fi
done < <(find "$PROJECT_DIR/.claude/rules" -name "*.md" -print0 2>/dev/null)

# Also check MEMORY.md
# Claude Code stores memory at ~/.claude/projects/<mangled-path>/memory/MEMORY.md
# where <mangled-path> is the absolute project path with / replaced by -
MANGLED=$(echo "$PROJECT_DIR" | sed 's|[/.]|-|g')
MEMORY_FILE="$HOME/.claude/projects/$MANGLED/memory/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
    BYTES=$(wc -c < "$MEMORY_FILE" | tr -d ' ')
    if [ "$BYTES" -gt "$MEMORY_LIMIT" ]; then
        warn "MEMORY.md is $(human_size $BYTES) (limit: $(human_size $MEMORY_LIMIT)). Run /maintain."
    fi
fi

# --- Check for stale indexes (reference files that don't exist) ---
for INDEX_FILE in "$CONTEXT_DIR"/*/index.md; do
    [ -f "$INDEX_FILE" ] || continue
    DIR=$(dirname "$INDEX_FILE")
    RELDIR="${DIR#$PROJECT_DIR/}"
    # Extract file references from markdown tables/links
    while IFS= read -r REF; do
        REF_CLEANED=$(echo "$REF" | sed 's/`//g' | tr -d ' ')
        [ -z "$REF_CLEANED" ] && continue
        # Check relative to the index's directory
        if [ ! -f "$DIR/$REF_CLEANED" ] && [ ! -d "$DIR/$REF_CLEANED" ]; then
            # Also check relative to project root
            if [ ! -f "$PROJECT_DIR/$REF_CLEANED" ] && [ ! -d "$PROJECT_DIR/$REF_CLEANED" ]; then
                warn "$RELDIR/index.md references '$REF_CLEANED' but it doesn't exist. Index may be stale."
            fi
        fi
    done < <(grep -oE '`[a-zA-Z0-9_/-]+\.md`' "$INDEX_FILE" 2>/dev/null | sed 's/`//g' | grep -v 'index\.md' | grep -v 'learnings\.md' | sort -u)
done

# --- Output ---
if [ -n "$WARNINGS" ]; then
    # stdout -> injected into model context
    echo ""
    echo "--- Context Health ---"
    printf "$WARNINGS"
    echo "---"
    echo ""
fi
