#!/usr/bin/env bash

# bump.sh — Refresh every power from upstream and commit the result.
#
# This is a thin orchestrator. Each power owns a sync script (e.g.
# pstack/sync-pstack.sh) that mirrors its upstream content AND derives and writes
# its version, using the shared helpers in .github/scripts/lib/version.sh. So
# this script does not know how any power is versioned; it just runs each sync
# against the default upstream ref, then commits per-power what changed.
#
# Seeding a new power at a specific tag is a separate, manual operation:
# run that power's sync with --ref <tag> once and commit. This script always
# uses each sync's default ref (main).
#
# Usage:
#   bump.sh [--dry-run]

set -euo pipefail

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN]${RESET}"
else
    echo -e "Configuring git user"
    git config set color.ui always
    git config set user.name "github-actions[bot]"
    git config set user.email "github-actions[bot]@users.noreply.github.com"
fi

# --- Run each power's sync ---
# A power is any top-level directory with a plugin.json and a sync-*.sh. Each
# sync mirrors its upstream content and writes its own version.
for plugin in */plugin.json; do
    dir="${plugin%/plugin.json}"
    sync_script=$(find "$dir" -maxdepth 1 -name 'sync-*.sh' | head -1)
    if [ -z "$sync_script" ]; then
        echo -e "${YELLOW}${dir}: no sync-*.sh, skipping${RESET}"
        continue
    fi
    echo -e "${CYAN}Running ${dir} sync...${RESET}"
    # A sync exits 3 on a version regression (upstream moved backwards, e.g. a
    # force-push). Revert that power's changes and flag it rather than committing
    # content with a stale version. Any other non-zero exit is a real failure.
    rc=0
    "$sync_script" || rc=$?
    if [ "$rc" -eq 3 ]; then
        echo "::warning::Version regression in ${dir}. Upstream may have force-pushed. Reverting and skipping; investigate manually."
        git checkout -- "$dir" 2>/dev/null || true
        git clean -fd -- "$dir/skills" >/dev/null 2>&1 || true
    elif [ "$rc" -ne 0 ]; then
        echo "Error: ${dir} sync failed (exit $rc)" >&2
        exit "$rc"
    fi
done

echo -e "${BLUE}Diffing changes...${RESET}"
git --no-pager diff --color=always

if git diff --quiet; then
    echo -e "${YELLOW}Nothing changed${RESET}"
    exit 0
fi

# --- Commit each power that changed ---
if [ "$DRY_RUN" = false ]; then
    for plugin in */plugin.json; do
        dir="${plugin%/plugin.json}"
        if git diff --quiet -- "$dir"; then
            continue
        fi
        version=$(jq -r '.version // "0.0.0"' "$plugin")
        echo -e "  ${CYAN}${dir}:${RESET} committing ${GREEN}${version}${RESET}"
        git add -A -- "$dir"
        git commit -m "Bump ${dir} to ${version}"
    done
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run complete. No changes committed.${RESET}"
    git checkout -- .
    git clean -fd -- */skills/ >/dev/null 2>&1 || true
    exit 0
fi

echo -e "${BLUE}Pushing changes to origin/${GITHUB_REF_NAME}...${RESET}"
git push origin "${GITHUB_REF_NAME}"
