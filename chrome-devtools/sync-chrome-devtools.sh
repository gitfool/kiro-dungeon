#!/usr/bin/env bash
set -euo pipefail

# sync-chrome-devtools.sh — Mirrors the ChromeDevTools/chrome-devtools-mcp plugin
# skills from GitHub into this power's skills/ directory.
#
# Downloads the chrome-devtools-mcp repo and mirrors its skills/ tree into
# ./skills/, so this directory can be installed as a Kiro power.
#
# This upstream ships no agents, so — unlike the dotnet powers — there is no agent
# conversion step. It is a straight skills mirror plus a hand-written mcp.json for
# the chrome-devtools MCP server.
#
# The manifests (plugin.json, mcp.json), POWER.md, README, and this script are
# maintained by hand and are NOT touched by the sync (except the version field in
# plugin.json/POWER.md, which write_power_version stamps) — it only writes under
# skills/. Upstream's plugin.json is already Agent Plugins 1.0.0 compliant (it has
# $schema and is identity-only), so it is not the #1087 case the dotnet mirrors hit;
# it is simply not mirrored because this power carries its own identity manifest.
#
# Support directories (references, scripts) under a skill are mirrored as-is. Only
# immediate subdirectories of skills/ are treated as skills by Kiro, so nested
# markdown is never loaded and needs no special handling.
#
# This is a maintainer tool, not an installer. Run it to refresh skills/ when
# upstream changes, then commit the result.
#
# Usage:
#   sync-chrome-devtools.sh [--dry-run] [--ref <branch|tag|sha>]

DRY_RUN=false
REF=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --ref)
            shift
            if [ $# -eq 0 ]; then
                echo "--ref requires a value" >&2
                exit 1
            fi
            REF="$1"
            ;;
        --ref=*) REF="${1#--ref=}" ;;
        -h|--help)
            sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# --- Upstream source ---
REPOSITORY="ChromeDevTools/chrome-devtools-mcp"
BASE_PATH="skills"
# Path within the upstream repo whose commit date drives this power's version.
# The skills/ tree, not the repo root, so unrelated commits (server code, docs,
# tests) don't bump the power — only a change to the mirrored skills does.
UPSTREAM_PATH="skills"
# Default ref when --ref is not given (the bump workflow's path).
REF="${REF:-main}"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_ROOT="$SCRIPT_DIR/skills"
PLUGIN_JSON="$SCRIPT_DIR/plugin.json"
POWER_MD="$SCRIPT_DIR/POWER.md"

# Shared version-derivation helpers (derive_version, latest_commit_for_path,
# is_version_regression, write_power_version).
source "$SCRIPT_DIR/../.github/scripts/lib/version.sh"

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${GREEN}sync-chrome-devtools: $REPOSITORY@$REF ($BASE_PATH)${RESET}"
if [ "$DRY_RUN" = true ]; then echo -e "  ${YELLOW}[DRY RUN]${RESET}"; fi

# --- Download and extract archive ---
# Uses the tarball rather than the zip, since tar is always present while unzip
# is not installed on a minimal Linux.
TEMP_DIR=$(mktemp -d)
TARBALL_PATH="$TEMP_DIR/archive.tar.gz"

echo -e "${BLUE}  Downloading archive ($REF)...${RESET}"
# GitHub's codeload accepts a branch, tag, or SHA after refs/heads is dropped;
# the generic archive endpoint resolves any of them.
ARCHIVE_URL="https://github.com/$REPOSITORY/archive/$REF.tar.gz"
GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"
CURL_OPTS=(-fsSL)
if [ -n "$GH_TOKEN" ]; then
    CURL_OPTS+=(-H "Authorization: token $GH_TOKEN")
fi
if ! curl "${CURL_OPTS[@]}" "$ARCHIVE_URL" -o "$TARBALL_PATH"; then
    echo "Error: Failed to download archive" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${BLUE}  Extracting...${RESET}"
tar -xzf "$TARBALL_PATH" -C "$TEMP_DIR"
rm "$TARBALL_PATH"

# Find extracted root (GitHub archives have a top-level folder like repo-main/)
EXTRACTED_ROOT=$(find "$TEMP_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)
SOURCE_ROOT="$EXTRACTED_ROOT/$BASE_PATH"

if [ ! -d "$SOURCE_ROOT" ]; then
    echo "Error: Skills path not found in archive: $BASE_PATH" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Stats ---
STAT_CREATED=0
STAT_UPDATED=0
STAT_UNCHANGED=0

# --- File output ---
# Compares with CR removed. Comparing this way avoids reporting every file as
# changed on a Windows working tree, where text=auto yields CRLF while upstream
# archives are always LF.
copy_output_file() {
    local source_path="$1"
    local dest_path="$2"
    local relative_path="./${dest_path#"$SCRIPT_DIR"/}"

    if [ -f "$dest_path" ]; then
        if diff -q <(tr -d '\r' < "$source_path") <(tr -d '\r' < "$dest_path") >/dev/null 2>&1; then
            echo "    [unchanged] $relative_path"
            STAT_UNCHANGED=$((STAT_UNCHANGED + 1))
            return 0
        fi
        echo "    [updated] $relative_path"
        STAT_UPDATED=$((STAT_UPDATED + 1))
    else
        echo "    [created] $relative_path"
        STAT_CREATED=$((STAT_CREATED + 1))
    fi

    if [ "$DRY_RUN" = true ]; then return 0; fi

    mkdir -p "$(dirname "$dest_path")"
    cp "$source_path" "$dest_path"
}

# --- Mirror a directory tree verbatim ---
sync_support_dir() {
    local source_dir="$1"
    local dest_dir="$2"

    for item in "$source_dir"/*; do
        if [ ! -e "$item" ]; then continue; fi
        if [ -d "$item" ]; then
            sync_support_dir "$item" "$dest_dir/$(basename "$item")"
        else
            copy_output_file "$item" "$dest_dir/$(basename "$item")"
        fi
    done
}

# --- Mirror one skill folder ---
# Skill names already match their directory names upstream, so no name
# normalization is needed; SKILL.md is copied verbatim.
sync_skill_folder() {
    local source_dir="$1"
    local skill_name="$2"
    local local_base="$SKILLS_ROOT/$skill_name"

    for item in "$source_dir"/*; do
        if [ ! -e "$item" ]; then continue; fi
        local name
        name=$(basename "$item")

        if [ -d "$item" ]; then
            sync_support_dir "$item" "$local_base/$name"
        else
            copy_output_file "$item" "$local_base/$name"
        fi
    done
}

# --- Main sync ---
SKILLS=()

for dir in "$SOURCE_ROOT"/*/; do
    if [ ! -d "$dir" ]; then continue; fi
    name=$(basename "$dir")
    SKILLS+=("$name")
done

echo "  Found ${#SKILLS[@]} skills"

echo -e "${BLUE}  Syncing skills...${RESET}"
for s in "${SKILLS[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$s" "$s"
done

# --- Orphan detection ---
# A local skill is an orphan if it no longer exists upstream in skills/.
ORPHANS=()
if [ -d "$SKILLS_ROOT" ]; then
    for dir in "$SKILLS_ROOT"/*/; do
        if [ ! -d "$dir" ]; then continue; fi
        name=$(basename "$dir")
        if [ -d "$SOURCE_ROOT/$name" ]; then continue; fi
        ORPHANS+=("$name")
    done
fi

# --- Cleanup temp ---
rm -rf "$TEMP_DIR"

# --- Versioning ---
# Derive the version from the commit date of UPSTREAM_PATH at REF, and write it
# to plugin.json and POWER.md. This is the same derivation whether REF is a seed
# tag or the default branch (the bump workflow's path), so there is one source of
# truth. The regression guard refuses a version that would move backwards, which
# usually means an upstream force-push worth investigating.
echo -e "${BLUE}  Versioning...${RESET}"
VERSION_STATUS="unchanged"
if commit_info=$(latest_commit_for_path "$REPOSITORY" "$UPSTREAM_PATH" "$REF"); then
    commit_date=$(echo "$commit_info" | sed -n 1p)
    commit_sha=$(echo "$commit_info" | sed -n 2p)
    next_version=$(derive_version "$commit_date")
    current_version=$(jq -r '.version // "0.0.0"' "$PLUGIN_JSON")
    short_sha="${commit_sha:0:7}"

    if [ "$current_version" = "$next_version" ]; then
        echo "    $current_version (unchanged, $short_sha)"
    elif is_version_regression "$current_version" "$next_version"; then
        echo -e "    ${YELLOW}regression: $current_version -> $next_version ($short_sha)${RESET}" >&2
        VERSION_STATUS="regression"
    else
        echo "    $current_version -> $next_version ($short_sha)"
        VERSION_STATUS="bumped"
        if [ "$DRY_RUN" = false ]; then
            write_power_version "$next_version" "$PLUGIN_JSON" "$POWER_MD"
        fi
    fi
else
    echo -e "    ${YELLOW}could not query upstream commit; version left unchanged${RESET}" >&2
fi

# --- Summary ---
echo ""
echo -e "${GREEN}  Done.${RESET}"
echo "    Created:    $STAT_CREATED"
echo "    Updated:    $STAT_UPDATED"
echo "    Unchanged:  $STAT_UNCHANGED"
echo "    Version:    $VERSION_STATUS"
echo "    Output:     $SKILLS_ROOT"

# A regression means upstream appears to have moved backwards (e.g. force-push).
# Exit 3 so the bump workflow can revert this power's changes and flag it, rather
# than committing content with a stale version.
if [ "$VERSION_STATUS" = "regression" ]; then
    exit 3
fi

if [ ${#ORPHANS[@]} -gt 0 ]; then
    echo ""
    echo "  ${#ORPHANS[@]} local skill(s) no longer exist upstream:"
    for o in "${ORPHANS[@]}"; do echo "    $o"; done
    printf "  Remove with: git rm -r"
    for o in "${ORPHANS[@]}"; do printf " skills/%s" "$o"; done
    printf "\n"
fi
