#!/usr/bin/env bash
#
# Create a GitHub PR with enforced conventions.
#
# Discovers repo conventions at runtime (no hard-coded config):
# - Default branch from gh repo view
# - PR template from .github/
# - Recent PR titles for convention reference
#
# Usage:
#   create-pr.sh --check                        # prep: branch status, template, recent titles
#   create-pr.sh --create --title "..." --body "..."  # create draft PR
#   create-pr.sh --create --title "..." --body-file /path/to/body.md
#
# Always creates draft PRs. No override.

set -euo pipefail

# --- helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "--- $* ---"; }

get_default_branch() {
    gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null \
        || git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' \
        || echo "main"
}

get_current_branch() {
    git branch --show-current 2>/dev/null || die "Not on a branch (detached HEAD?)"
}

check_branch_freshness() {
    local default_branch="$1"
    git fetch origin "$default_branch" --quiet 2>/dev/null

    local merge_base origin_sha
    merge_base=$(git merge-base "origin/$default_branch" HEAD 2>/dev/null) || die "Cannot compute merge-base. Is origin/$default_branch fetched?"
    origin_sha=$(git rev-parse "origin/$default_branch")

    if [ "$merge_base" = "$origin_sha" ]; then
        echo "FRESH (branch includes latest origin/$default_branch)"
        return 0
    else
        local behind
        behind=$(git rev-list --count "$merge_base".."origin/$default_branch")
        echo "STALE (behind origin/$default_branch by $behind commits)"
        return 1
    fi
}

find_pr_template() {
    # Check standard locations
    local candidates=(
        ".github/pull_request_template.md"
        ".github/PULL_REQUEST_TEMPLATE.md"
        ".github/PULL_REQUEST_TEMPLATE/pull_request_template.md"
        "docs/pull_request_template.md"
    )
    for f in "${candidates[@]}"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    # Glob fallback
    find .github -iname "*pull_request_template*" -type f 2>/dev/null | head -1
}

show_recent_titles() {
    local count="${1:-10}"
    gh pr list --state merged --limit "$count" --json title,number \
        --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || echo "(could not fetch recent PRs)"
}

# --- commands ---

cmd_check() {
    local default_branch current_branch
    default_branch=$(get_default_branch)
    current_branch=$(get_current_branch)

    info "Repository"
    gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "(unknown)"
    echo "Default branch: $default_branch"
    echo "Current branch: $current_branch"
    echo ""

    info "Branch Freshness"
    local freshness_status=0
    check_branch_freshness "$default_branch" || freshness_status=$?
    echo ""

    info "PR Template"
    local template
    template=$(find_pr_template)
    if [ -n "$template" ]; then
        echo "Found: $template"
        echo ""
        cat "$template"
    else
        echo "(no PR template found)"
    fi
    echo ""

    info "Recent Merged PR Titles (convention reference)"
    show_recent_titles 10
    echo ""

    if [ "$freshness_status" -ne 0 ]; then
        echo "WARNING: Branch is stale. Rebase onto origin/$default_branch before creating PR."
    fi
}

cmd_create() {
    local title="" body="" body_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title) title="$2"; shift 2 ;;
            --body) body="$2"; shift 2 ;;
            --body-file) body_file="$2"; shift 2 ;;
            *) die "Unknown argument to --create: $1" ;;
        esac
    done

    [ -z "$title" ] && die "Missing --title"
    [ -z "$body" ] && [ -z "$body_file" ] && die "Missing --body or --body-file"

    if [ -n "$body_file" ]; then
        [ -f "$body_file" ] || die "Body file not found: $body_file"
        body=$(cat "$body_file")
    fi

    local default_branch current_branch
    default_branch=$(get_default_branch)
    current_branch=$(get_current_branch)

    # Guard: not on default branch
    [ "$current_branch" = "$default_branch" ] && die "Cannot create PR from $default_branch. Create a feature branch first."

    # Guard: branch freshness
    local freshness
    freshness=$(check_branch_freshness "$default_branch") || die "Branch is stale: $freshness. Rebase onto origin/$default_branch first."

    # Guard: branch pushed to remote
    if ! git rev-parse "origin/$current_branch" >/dev/null 2>&1; then
        echo "Pushing branch to origin..."
        git push -u origin "$current_branch"
    fi

    # Create draft PR
    gh pr create --draft --title "$title" --body "$body"
}

# --- main ---

case "${1:-}" in
    --check)
        cmd_check
        ;;
    --create)
        shift
        cmd_create "$@"
        ;;
    -h|--help|"")
        echo "Usage:"
        echo "  create-pr.sh --check                                # prep: branch status, template, titles"
        echo "  create-pr.sh --create --title \"...\" --body \"...\"    # create draft PR"
        echo "  create-pr.sh --create --title \"...\" --body-file path # create draft PR from file"
        ;;
    *)
        die "Unknown command: $1. Use --check or --create."
        ;;
esac
