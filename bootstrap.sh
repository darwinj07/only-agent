#!/usr/bin/env bash
set -euo pipefail

# only-agent bootstrap - one-off interactive setup for new instances.
# Handles the deterministic parts (file generation, symlinks, commits),
# hands off to Claude for the parts that need judgment (OAuth, diagnosis).

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${CYAN}%s${NC}\n" "$*"; }
ok()    { printf "${GREEN}%s${NC}\n" "$*"; }
warn()  { printf "${YELLOW}%s${NC}\n" "$*"; }
err()   { printf "${RED}%s${NC}\n" "$*" >&2; }

# --- Guard: don't re-run on a bootstrapped instance ---
if grep -q "^- \*\*Name\*\*:" context/shared/identity.md 2>/dev/null; then
    err "This instance is already bootstrapped."
    read -rp "Start fresh? Re-runs identity/learnings/CLAUDE.md generation. Existing context/<custom-domain>/ dirs and projects/* symlinks are NOT cleared - delete by hand if unwanted. [y/N]: " REDO
    case "$REDO" in
        [Yy]|[Yy][Ee][Ss])
            info "Resetting identity..."
            rm -f context/shared/identity.md
            ;;
        *)
            info "Aborted."
            exit 0
            ;;
    esac
fi

# ============================================================
# Hard dependencies (minimal - only what the bootstrap script itself needs)
# ============================================================
MISSING=()
for TOOL in git python3; do
    command -v "$TOOL" &>/dev/null || MISSING+=("$TOOL")
done
if (( ${#MISSING[@]} > 0 )); then
    err "Missing required tools: ${MISSING[*]}"
    err "  git     - version control"
    err "  python3 - bootstrap helpers (used to read existing Claude Code config)"
    exit 1
fi

# Soft check: claude CLI is needed for the optional service-connect handoff,
# but bootstrap can complete without it.
if ! command -v claude &>/dev/null; then
    warn "claude CLI not found in PATH. Bootstrap will complete, but the optional"
    warn "service-connect step at the end requires it. Install: https://docs.anthropic.com/en/docs/claude-code"
fi

# ============================================================
# Phase 1: Collect info
# ============================================================
printf "\n${BOLD}=== only-agent bootstrap ===${NC}\n\n"
info "Scaffolding your workspace. ~30 seconds."
info "Identity (name/email/role) gets read from git config or asked by the agent on first use."
printf "\n"

# Defaults. Identity (Name/Email/GitHub/Role/Manager) gets read from git config or asked
# by the agent in session 1. Domains start at work/personal; /onboard adds more if your
# resources warrant it.
DOMAINS=(work personal)

# --- Repos ---
info "Which repos do you actively work on? These get symlinked into projects/."
info "Enter absolute paths, one per line. Empty line when done."
info "Example: ~/myrepo"
info "Or press Enter - the /onboard skill will discover repos after bootstrap."
printf "\n"

REPO_PATHS=()
REPO_NAMES=()
REPO_SKIPPED=()
while true; do
    read -rp "Repo path (empty to finish): " REPO_PATH
    [[ -z "$REPO_PATH" ]] && break

    # Expand ~ if used
    REPO_PATH="${REPO_PATH/#\~/$HOME}"

    if [[ ! -d "$REPO_PATH" ]]; then
        warn "  Directory not found: $REPO_PATH (skipping)"
        REPO_SKIPPED+=("$REPO_PATH (not found)")
        continue
    fi
    if [[ ! -d "$REPO_PATH/.git" ]]; then
        warn "  Not a git repo: $REPO_PATH (skipping)"
        REPO_SKIPPED+=("$REPO_PATH (not a git repo)")
        continue
    fi

    REPO_NAME="$(basename "$REPO_PATH")"
    REPO_PATHS+=("$REPO_PATH")
    REPO_NAMES+=("$REPO_NAME")
    ok "  Added: $REPO_NAME -> $REPO_PATH"
done

# --- Confirm ---
printf "\n${BOLD}--- Summary ---${NC}\n"
printf "Domains: %s\n" "${DOMAINS[*]}"
if [[ ${#REPO_NAMES[@]} -gt 0 ]]; then
    printf "Repos:   %s\n" "${REPO_NAMES[*]}"
else
    printf "Repos:   (none - you can add later with ln -s)\n"
fi
# Skipped list always shown when non-empty - including the case where every entered
# path was rejected and REPO_NAMES is empty (e.g. researcher pointing only at
# notebook folders that aren't git repos).
if [[ ${#REPO_SKIPPED[@]} -gt 0 ]]; then
    printf "Skipped: %s\n" "${REPO_SKIPPED[0]}"
    for ((i=1; i<${#REPO_SKIPPED[@]}; i++)); do
        printf "         %s\n" "${REPO_SKIPPED[$i]}"
    done
fi
printf "\n"
read -rp "Proceed? [Y/n]: " CONFIRM
case "$CONFIRM" in
    [Nn]|[Nn][Oo]) info "Aborted."; exit 0 ;;
esac

# ============================================================
# Phase 2: Generate files
# ============================================================
printf "\n${BOLD}=== Generating files ===${NC}\n\n"

# --- context/shared/identity.md ---
# Stub. The agent fills this in on first use - reads `git config --get user.{name,email}`,
# asks for anything else (GitHub handle, role, manager) if and when it's relevant.
mkdir -p context/shared
cat > context/shared/identity.md << 'EOF'
# Identity

*Empty stub. The agent populates this on first use from `git config` and conversation.*
EOF
ok "Created context/shared/identity.md"

# --- .claude/rules/learnings.md ---
cat > .claude/rules/learnings.md << 'EOF'
# Preferences (Universal)

Domain-specific preferences in `context/<domain>/learnings.md`.

## Identity
- See `context/shared/identity.md`. The agent populates from `git config` on first use.

## How you work
*Discovered through sessions. Add preferences as they emerge.*

## Style
*Discovered through sessions. Add preferences as they emerge.*

## Tool routing
*Discovered through sessions. Route each tool to one canonical method.*

## Context system
- **Router**: `context/index.md` (loaded every session)
- **Domain**: `context/<domain>/index.md` + `learnings.md` (loaded when domain activates)
- **Leaf**: domain files (loaded on demand, per the domain index)
EOF
ok "Created .claude/rules/learnings.md"

# --- context/index.md ---
DOMAIN_TABLE=""
for DOMAIN in "${DOMAINS[@]}"; do
    case "$DOMAIN" in
        work)
            DOMAIN_TABLE+="| work | \`context/work/\` | Work-related: code, projects, team, tickets, monitoring |"$'\n'
            ;;
        personal)
            DOMAIN_TABLE+="| personal | \`context/personal/\` | Personal life, side projects, social, non-work |"$'\n'
            ;;
    esac
done

cat > context/index.md << EOF
# Context Router

The domain map. Loaded every session. Tells the agent what worlds exist and when to enter each one.

## Domains

| Domain | Path | Activate when... |
|--------|------|-------------------|
${DOMAIN_TABLE}
## Activation Protocol
1. Session starts, this file loads (the router)
2. User's message signals domain - pick it (or ask if ambiguous)
3. Load that domain's \`index.md\` + \`learnings.md\`
4. Within domain, load files on demand per the index
5. Cross-domain requests load both indexes

## Shared Resources
Cross-domain files that any domain can reference:
- \`context/shared/identity.md\` - core identity (used everywhere)
EOF
ok "Created context/index.md"

# --- Domain scaffolds ---
domain_label() {
    case "$1" in
        work)     echo "Work" ;;
        personal) echo "Personal" ;;
        *)
            # Capitalize first letter, lowercase the rest
            local first="${1:0:1}"
            local rest="${1:1}"
            echo "$(echo "$first" | tr '[:lower:]' '[:upper:]')${rest}"
            ;;
    esac
}

for DOMAIN in "${DOMAINS[@]}"; do
    LABEL="$(domain_label "$DOMAIN")"
    mkdir -p "context/$DOMAIN"

    cat > "context/$DOMAIN/index.md" << EOF
# $LABEL Domain

## Files
*No files yet. Created as context accumulates from real work.*

| File | What it tracks |
|------|----------------|
| \`learnings.md\` | $LABEL preferences and patterns |
EOF

    cat > "context/$DOMAIN/learnings.md" << EOF
# Preferences ($DOMAIN)

Preferences specific to the $DOMAIN domain. Universal prefs in \`.claude/rules/learnings.md\`.

*Discovered through sessions. Add preferences as they emerge.*
EOF
    ok "Created context/$DOMAIN/ scaffold"
done

# --- CLAUDE.md Instance section ---
DOMAIN_LIST=""
for D in "${DOMAINS[@]}"; do
    DOMAIN_LIST+="- **$(domain_label "$D")** (\`context/$D/\`)"$'\n'
done

PROJECTS_BLOCK=""
if [[ ${#REPO_NAMES[@]} -gt 0 ]]; then
    REPOS_LINE="Active repos: **$(printf '%s\n' "${REPO_NAMES[@]}" | paste -sd',' - | sed 's/,/**, **/g')**."
    PROJECTS_BLOCK="

### Projects
All symlinked in \`projects/\`. When working on one:
1. \`git -C projects/<name> status\`
2. Check for project CLAUDE.md
3. Read its README

$REPOS_LINE"
fi

INSTANCE_BLOCK="## Instance

*Identity (name, email, role) lives in \`context/shared/identity.md\` - the agent populates it from \`git config\` on first use.*

### Domains
${DOMAIN_LIST}
### Workspace layout
- \`projects/\` - Symlinks to repos. \`ls\` to see what's linked.
- \`context/\` - Domain-scoped knowledge. Follow the index.
- \`notes/\` - System docs (architecture, connections, primitives).
- \`tools/\` - Built tools.
- \`scratch/\` - Temp files.${PROJECTS_BLOCK}"

{
    sed '/^## Instance/,$d' CLAUDE.md
    echo "$INSTANCE_BLOCK"
} > CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md
ok "Updated CLAUDE.md Instance section"

# ============================================================
# Symlink repos
# ============================================================
mkdir -p projects  # always create, so docs that reference projects/ aren't dead
if [[ ${#REPO_PATHS[@]} -gt 0 ]]; then
    printf "\n${BOLD}=== Symlinking repos ===${NC}\n\n"
    for i in "${!REPO_PATHS[@]}"; do
        RPATH="${REPO_PATHS[$i]}"
        RNAME="${REPO_NAMES[$i]}"
        if [[ -e "projects/$RNAME" ]]; then
            warn "projects/$RNAME already exists, skipping"
        else
            ln -s "$RPATH" "projects/$RNAME"
            ok "Linked projects/$RNAME -> $RPATH"
        fi
    done
fi

# ============================================================
# Context migration (scan existing Claude Code artifacts)
# ============================================================
printf "\n${BOLD}=== Existing Claude Code context ===${NC}\n\n"
info "Bootstrap can scan ~/.claude/ for existing memory/rules/skills to offer migration."
info "Read-only scan - nothing leaves your machine unless you opt into migration."
read -rp "Scan now? [y/N]: " WANT_SCAN
DO_SCAN=false
case "$WANT_SCAN" in
    [Yy]|[Yy][Ee][Ss]) DO_SCAN=true ;;
esac

MIGRATE=false

if $DO_SCAN; then

MANIFEST="$ROOT_DIR/scratch/migration-manifest.md"
mkdir -p scratch
HAS_CONTEXT=false

# --- MCP servers (configured in ~/.claude.json) ---
MCP_NAMES=()
for SETTINGS_FILE in "$HOME/.claude.json" "$HOME/.claude/settings.json"; do
    [[ -f "$SETTINGS_FILE" ]] || continue
    if command -v python3 &>/dev/null; then
        NAMES="$(python3 -c "
import json, sys
try:
    data = json.load(open('$SETTINGS_FILE'))
    for name in sorted(data.get('mcpServers', {}).keys()):
        print(name)
except: pass
" 2>/dev/null)" || true
        while IFS= read -r NAME; do
            [[ -n "$NAME" ]] && MCP_NAMES+=("$NAME")
        done <<< "$NAMES"
    fi
done
MCP_COUNT="${#MCP_NAMES[@]}"

# --- User-level CLAUDE.md ---
USER_CLAUDE_MD=""
USER_CLAUDE_LINES=0
if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
    USER_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
    USER_CLAUDE_LINES="$(wc -l < "$USER_CLAUDE_MD" | tr -d ' ')"
fi

# --- Memory files ---
MEMORY_FILES=()
MEMORY_TOTAL_LINES=0
while IFS= read -r -d '' MEMFILE; do
    LINES="$(wc -l < "$MEMFILE" | tr -d ' ')"
    if [[ "$LINES" -gt 0 ]]; then
        MEMORY_FILES+=("$MEMFILE")
        MEMORY_TOTAL_LINES=$((MEMORY_TOTAL_LINES + LINES))
    fi
done < <(find "$HOME/.claude/projects" -path "*/memory/*.md" -print0 2>/dev/null || true)

# --- Project .claude/ directories (rules, skills, CLAUDE.md) ---
SCAN_DIRS=()
if (( ${#REPO_PATHS[@]} > 0 )); then
    SCAN_DIRS+=("${REPO_PATHS[@]}")
fi
for CANDIDATE in "$HOME"/*/; do
    [[ -d "${CANDIDATE}.claude" ]] || continue
    CANDIDATE="${CANDIDATE%/}"
    ALREADY=false
    if (( ${#REPO_PATHS[@]} > 0 )); then
        for R in "${REPO_PATHS[@]}"; do
            [[ "$CANDIDATE" == "$R" ]] && ALREADY=true
        done
    fi
    [[ "$CANDIDATE" == "$ROOT_DIR" ]] && ALREADY=true
    $ALREADY || SCAN_DIRS+=("$CANDIDATE")
done

RULES_FILES=()
SKILLS_DIRS=()
PROJECT_CLAUDE_MDS=()
if (( ${#SCAN_DIRS[@]} > 0 )); then
for SCANDIR in "${SCAN_DIRS[@]}"; do
    if [[ -d "$SCANDIR/.claude/rules" ]]; then
        while IFS= read -r -d '' RF; do
            LINES="$(wc -l < "$RF" | tr -d ' ')"
            [[ "$LINES" -gt 0 ]] && RULES_FILES+=("$RF")
        done < <(find "$SCANDIR/.claude/rules" -name "*.md" -print0 2>/dev/null || true)
    fi
    if [[ -d "$SCANDIR/.claude/skills" ]]; then
        while IFS= read -r -d '' SKILL; do
            SKILLS_DIRS+=("$SKILL")
        done < <(find "$SCANDIR/.claude/skills" -name "SKILL.md" -print0 2>/dev/null || true)
    fi
    if [[ -f "$SCANDIR/CLAUDE.md" ]]; then
        LINES="$(wc -l < "$SCANDIR/CLAUDE.md" | tr -d ' ')"
        [[ "$LINES" -gt 0 ]] && PROJECT_CLAUDE_MDS+=("$SCANDIR/CLAUDE.md")
    fi
done
fi

# --- Display summary ---
FOUND_ITEMS=0
if [[ "$MCP_COUNT" -gt 0 ]]; then
    printf "  MCP servers:     %d configured" "$MCP_COUNT"
    [[ ${#MCP_NAMES[@]} -gt 0 ]] && printf " (%s)" "${MCP_NAMES[*]}"
    printf "\n"
    FOUND_ITEMS=$((FOUND_ITEMS + 1))
fi
if [[ -n "$USER_CLAUDE_MD" ]]; then
    printf "  User CLAUDE.md:  %s (%d lines)\n" "$USER_CLAUDE_MD" "$USER_CLAUDE_LINES"
    FOUND_ITEMS=$((FOUND_ITEMS + 1))
fi
if [[ ${#MEMORY_FILES[@]} -gt 0 ]]; then
    printf "  Memory files:    %d files, %d lines total\n" "${#MEMORY_FILES[@]}" "$MEMORY_TOTAL_LINES"
    FOUND_ITEMS=$((FOUND_ITEMS + 1))
fi
if [[ ${#RULES_FILES[@]} -gt 0 ]]; then
    printf "  Rules files:     %d across projects\n" "${#RULES_FILES[@]}"
    FOUND_ITEMS=$((FOUND_ITEMS + 1))
fi
if [[ ${#SKILLS_DIRS[@]} -gt 0 ]]; then
    printf "  Skills:          %d custom skills\n" "${#SKILLS_DIRS[@]}"
    FOUND_ITEMS=$((FOUND_ITEMS + 1))
fi
if [[ ${#PROJECT_CLAUDE_MDS[@]} -gt 0 ]]; then
    printf "  Project configs: %d CLAUDE.md files\n" "${#PROJECT_CLAUDE_MDS[@]}"
    FOUND_ITEMS=$((FOUND_ITEMS + 1))
fi

if [[ "$FOUND_ITEMS" -gt 0 ]]; then
    HAS_CONTEXT=true
    printf "\n"
    read -rp "Migrate this context into your only-agent workspace? Claude will read, categorize, and organize it. [y/N]: " DO_MIGRATE
    case "$DO_MIGRATE" in
        [Yy]|[Yy][Ee][Ss]) MIGRATE=true ;;
    esac
else
    info "No existing Claude Code context found. Skipping migration."
fi

fi  # end of if $DO_SCAN

if $MIGRATE && command -v claude &>/dev/null; then
    info "Building migration manifest..."

    cat > "$MANIFEST" << 'MANIFEST_HEADER'
# Migration Manifest

Inline contents of files discovered from previous Claude Code usage.
Extract useful content and write it into the only-agent workspace.

## Target structure
- Universal preferences (style, workflow, tool routes) -> `.claude/rules/learnings.md` (append to existing sections)
- Work domain knowledge (team context, project patterns, service gotchas) -> `context/work/learnings.md`
- Personal domain knowledge -> `context/personal/learnings.md` (if domain exists)
- Project-specific knowledge -> `context/work/learnings.md` under a project map section (what each project contains, key skills, patterns - so the workspace knows what's available via symlinks)
- MCP server names -> note in `context/work/learnings.md` under a "Connected services" section

## Rules
- DO NOT import content that duplicates what only-agent already provides (self.md principles, context system docs)
- DO NOT import stale/broken content (expired tokens, old paths)
- DO import: preferences, style rules, tool routing decisions, API gotchas, workflow patterns, team knowledge
- DO import project-specific knowledge as a map/index (what each project contains, its key skills, patterns, gotchas). The actual project CLAUDE.md stays in the repo - but the workspace should know what's there.
- Preserve the user's voice - these are their hard-won learnings
- For skills: do not copy project-specific skills - only general-purpose ones. Index project-specific skills in the work context so the workspace knows they exist.

## Source files (contents inline below)
MANIFEST_HEADER

    append_source() {
        local LABEL="$1" SOURCE="$2"
        printf "\n### %s\nSource: %s\n\`\`\`\n" "$LABEL" "$SOURCE" >> "$MANIFEST"
        cat "$SOURCE" >> "$MANIFEST"
        printf "\n\`\`\`\n" >> "$MANIFEST"
    }

    if [[ "$MCP_COUNT" -gt 0 ]]; then
        printf "\n### MCP Servers\nNames: %s\n" "${MCP_NAMES[*]}" >> "$MANIFEST"
    fi
    if [[ -n "$USER_CLAUDE_MD" ]]; then
        append_source "User-level CLAUDE.md" "$USER_CLAUDE_MD"
    fi
    if (( ${#MEMORY_FILES[@]} > 0 )); then
        for MF in "${MEMORY_FILES[@]}"; do
            append_source "Memory file" "$MF"
        done
    fi
    if (( ${#RULES_FILES[@]} > 0 )); then
        for RF in "${RULES_FILES[@]}"; do
            append_source "Rules file" "$RF"
        done
    fi
    if (( ${#SKILLS_DIRS[@]} > 0 )); then
        for SD in "${SKILLS_DIRS[@]}"; do
            append_source "Skill" "$SD"
        done
    fi
    if (( ${#PROJECT_CLAUDE_MDS[@]} > 0 )); then
        for PC in "${PROJECT_CLAUDE_MDS[@]}"; do
            append_source "Project CLAUDE.md" "$PC"
        done
    fi

    ok "Manifest written to scratch/migration-manifest.md"
    printf "\n"
    info "Running Claude to migrate context (headless)..."
    info "This reads your existing files and organizes them into only-agent."
    printf "\n"

    CLAUDECODE= claude -p \
        --allowedTools "Read,Write,Edit" \
        --system-prompt "You are a migration tool. Read the manifest, extract content, write it into target files. No conversation, no questions - just read, extract, write. Ignore any context/index.md or hook output." \
        "TASK: Migrate existing Claude Code context into this only-agent workspace.

STEP 1: Read the manifest at $MANIFEST - it contains the INLINE contents of all source files.

STEP 2: From the inline contents, extract and categorize:
- Preferences, style rules, workflow patterns -> .claude/rules/learnings.md
- Work knowledge (API gotchas, team patterns, service traps) -> context/work/learnings.md
- Personal knowledge -> context/personal/learnings.md (if dir exists)
- MCP server names -> context/work/learnings.md under '## Connected services'
- Project map (what each project contains - skills, patterns, key files) -> context/work/learnings.md under '## Project map'

STEP 3: Read each TARGET file first (they already have scaffold content), then APPEND the extracted content under the appropriate sections.

Target files to update:
- .claude/rules/learnings.md (sections: How you work, Style, Tool routing)
- context/work/learnings.md
- context/personal/learnings.md (if exists)

RULES:
- APPEND to existing content, never overwrite
- Skip system-internal content (self.md principles, context tier system, activation protocol)
- Skip stale content (expired tokens, old paths)
- Keep the user's voice - these are their battle-tested learnings
- For project CLAUDE.md files: don't duplicate their content, but index what each project offers (skills, tools, patterns) so the workspace knows what's available via projects/ symlinks
- For skills: copy general-purpose skills to .claude/skills/ preserving directory structure (skip project-specific ones)

Print a summary of what you wrote and where when done." 2>&1 || true

    printf "\n"
    rm -f "$MANIFEST"
    ok "Migration complete."
elif $MIGRATE; then
    warn "Skipping migration - claude CLI not in PATH. Re-run later with claude installed if you want to migrate."
fi

# ============================================================
# Git commit
# ============================================================
printf "\n${BOLD}=== Committing ===${NC}\n\n"
if git rev-parse --git-dir >/dev/null 2>&1; then
    git add -A
    git commit -m "bootstrap" --quiet 2>/dev/null || warn "Nothing to commit (already committed?)"
    ok "Committed bootstrap state"
else
    info "Not a git repo - skipping commit (your workspace files are still saved)"
fi

# ============================================================
# Phase 3: Service connections (optional Claude handoff)
# ============================================================
printf "\n${BOLD}=== Done! ===${NC}\n\n"
ok "Bootstrap complete. Your workspace is ready."
printf "\n"

if ! command -v claude &>/dev/null; then
    info "Install the Claude Code CLI to start using your workspace:"
    info "  https://docs.anthropic.com/en/docs/claude-code"
    printf "\n"
    info "Once installed:"
    printf "  cd %s && claude\n" "$ROOT_DIR"
    exit 0
fi

info "Next step: connect services (Slack, Jira, Notion, Datadog, Google Workspace, etc.)"
info "This is optional. Skip what you don't use. Best done with Claude's help."
printf "\n"
read -rp "Connect services now? [y/N]: " CONNECT_SERVICES
case "$CONNECT_SERVICES" in
    [Yy]|[Yy][Ee][Ss])
        info "Launching Claude to walk you through service connections..."
        printf "\n"
        exec claude --initial-prompt "Bootstrap complete. First, ask the user which services they want to connect (out of: Slack, Atlassian/Jira, Notion, Datadog, Google Workspace, Gmail, Google Calendar, GitHub CLI). They'll list theirs. Then walk through ONLY those, in the order they list. For each: open notes/connections.md to the relevant section, follow the recipe, run a smoke test, fix failures before moving on. Once done, recommend running /onboard to build their work tree. Also: read context/shared/identity.md - if it's the empty stub, populate it from \`git config --get user.name\` and \`git config --get user.email\`, and ask if they want to add a GitHub handle, role, or team."
        ;;
    *)
        printf "\n"
        info "Next steps when ready:"
        printf "  cd %s\n" "$ROOT_DIR"
        printf "  claude\n"
        printf "\n"
        info "Then, in order:"
        info "  1. Connect services:  \"Walk me through notes/connections.md - I use [list your tools]\""
        info "  2. Build work tree:    /onboard"
        info "  3. Read the basics:   USING.md"
        printf "\n"
        ;;
esac
