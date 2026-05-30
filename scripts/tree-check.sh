#!/bin/bash
# tree-check.sh - PostToolUse hook for Read, Write, and Edit
# Tree-aware perception (reads) + safety net (writes).
# Exit 0 always (advisory). Outputs JSON with additionalContext for model injection.
#
# PostToolUse receives input via stdin JSON (not env vars).
# Fields: tool_name, tool_input.file_path, tool_response

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# Read stdin JSON (PostToolUse passes tool_name and tool_input via stdin)
STDIN=$(cat)

# Parse tool name and file path from stdin JSON
TOOL_NAME=$(echo "$STDIN" | grep -oE '"tool_name" *: *"[^"]+"' | head -1 | sed 's/.*"tool_name" *: *"//;s/"$//')
FILE_PATH=$(echo "$STDIN" | grep -oE '"file_path" *: *"[^"]+"' | head -1 | sed 's/.*"file_path" *: *"//;s/"$//')

# Fallback: try env vars (for manual testing / PreToolUse compat)
[ -z "$TOOL_NAME" ] && TOOL_NAME="${CLAUDE_TOOL_USE_NAME:-}"
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$CLAUDE_TOOL_INPUT" | grep -oE '"file_path" *: *"[^"]+"' | head -1 | sed 's/.*"file_path" *: *"//;s/"$//')

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

# Only check .md files
case "$FILE_PATH" in *.md) ;; *) exit 0 ;; esac

# Only check managed paths
RELPATH="${FILE_PATH#$PROJECT_DIR/}"
case "$RELPATH" in
    context/*|.claude/rules/*|notes/*) ;;
    *) exit 0 ;;
esac

# Detect tool type
case "$TOOL_NAME" in
    Read) MODE="read" ;;
    Write|Edit) MODE="write" ;;
    *) MODE="read" ;;  # Default to read for perception (matcher handles filtering)
esac

BASENAME=$(basename "$FILE_PATH")
NAME="${BASENAME%.md}"
PARENT_DIR=$(dirname "$FILE_PATH")
SIBLING_DIR="${PARENT_DIR}/.${NAME}"

MSGS=""
msg() { MSGS="${MSGS}$1\n"; }

# --- Tree governance detection ---
# A file is tree-governed if it has a hidden sibling dir (.name/ next to name.md).
# No sibling dir = just a file (not tree-governed, no size warnings).
# Skip index.md - it's inside its branch dir, not a sibling pattern.
HAS_SIBLING=false
HAS_BRANCH=false
LEAF_COUNT=0
LEAF_NAMES=""
if [ "$BASENAME" != "index.md" ] && [ -d "$SIBLING_DIR" ]; then
    HAS_SIBLING=true
    LEAVES=$(find "$SIBLING_DIR" -maxdepth 1 -name "*.md" -not -name "index.md" 2>/dev/null | sort)
    if [ -n "$LEAVES" ]; then
        LEAF_COUNT=$(echo "$LEAVES" | wc -l | tr -d ' ')
    fi
    if [ "$LEAF_COUNT" -gt 0 ]; then
        HAS_BRANCH=true
        LEAF_NAMES=$(echo "$LEAVES" | xargs -I{} basename {} .md | tr '\n' ', ' | sed 's/,$//')
    fi
fi

# --- Cross-reference detection ---
RELATED_PATHS=""
RELATED_LINE=$(grep -n '^<!-- related:' "$FILE_PATH" 2>/dev/null | tail -1)
if [ -n "$RELATED_LINE" ]; then
    # Extract paths from <!-- related: path1, path2, ... -->
    RELATED_PATHS=$(echo "$RELATED_LINE" | sed 's/.*<!-- related: *//;s/ *-->.*//' | tr ',' '\n' | sed 's/^ *//;s/ *$//')
fi

# === C: READ-TIME PERCEPTION ===
if [ "$MODE" = "read" ]; then
    if [ "$HAS_BRANCH" = true ]; then
        msg "TREE: branch index for ${SIBLING_DIR#$PROJECT_DIR/}/ ($LEAF_COUNT leaves: $LEAF_NAMES)"
    elif [ "$HAS_SIBLING" = true ]; then
        msg "TREE: governed node (.${NAME}/ exists, ready for split)"
    fi

    # Surface cross-references
    if [ -n "$RELATED_PATHS" ]; then
        RELATED_LIST=$(echo "$RELATED_PATHS" | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
        msg "RELATED: $RELATED_LIST"
    fi
fi

# === A: WRITE-TIME SAFETY NET ===
if [ "$MODE" = "write" ]; then
    BYTES=$(wc -c < "$FILE_PATH" | tr -d ' ')

    if [ "$HAS_BRANCH" = true ]; then
        # Branch index: strict 5KB limit
        if [ "$BYTES" -gt 5120 ]; then
            msg "TREE: $RELPATH is $(( (BYTES+512)/1024 ))KB (index limit 5KB). Branch has $LEAF_COUNT leaves: $LEAF_NAMES. Move depth content to a leaf in ${SIBLING_DIR#$PROJECT_DIR/}/."
        fi

        # Check for unreferenced leaves
        UNREFERENCED=""
        if [ -n "$LEAVES" ]; then
            while IFS= read -r LEAF; do
                LEAF_BASE=$(basename "$LEAF")
                if ! grep -q "$LEAF_BASE" "$FILE_PATH" 2>/dev/null; then
                    UNREFERENCED="${UNREFERENCED} ${LEAF_BASE}"
                fi
            done <<< "$LEAVES"
        fi
        if [ -n "$UNREFERENCED" ]; then
            msg "TREE: $RELPATH doesn't reference:$UNREFERENCED"
        fi

    elif [ "$HAS_SIBLING" = true ]; then
        # Tree-governed leaf (empty sibling dir, pre-staged for split): 10KB limit
        if [ "$BYTES" -gt 10240 ]; then
            msg "TREE: $RELPATH is $(( (BYTES+512)/1024 ))KB (limit 10KB). .${NAME}/ exists - split into leaves."
        fi

    elif [ "$BASENAME" = "index.md" ]; then
        # Legacy index.md pattern
        if [ "$BYTES" -gt 5120 ]; then
            msg "TREE: $RELPATH is $(( (BYTES+512)/1024 ))KB (index limit 5KB). Consider decomposing."
        fi

    fi
    # No sibling dir and not index.md = just a file. No size governance.

    # Validate cross-references (all file types)
    if [ -n "$RELATED_PATHS" ]; then
        while IFS= read -r REF_PATH; do
            [ -z "$REF_PATH" ] && continue
            if [ ! -f "$PROJECT_DIR/$REF_PATH" ]; then
                msg "CROSS-REF: references '$REF_PATH' but file not found"
            fi
        done <<< "$RELATED_PATHS"
    fi
fi

# Output - structured JSON for PostToolUse hook
if [ -n "$MSGS" ]; then
    # Escape for JSON string: backslashes, quotes, newlines
    CONTEXT=$(printf "$MSGS" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g; s/ $//')
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "$CONTEXT"
  }
}
EOF
fi

exit 0
