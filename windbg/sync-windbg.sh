#!/usr/bin/env bash

# sync-windbg.sh — Mirrors the windbg-debugging skill from GitHub into this
# power's skills/ directory.
#
# Downloads the windbg-mcp repo and mirrors skills/windbg-debugging into
# ./skills/, so this directory can be installed as a Kiro power.
#
# Only the skill is mirrored. The upstream docs/ (walkthroughs, reference) and
# examples/ are NOT vendored — they are heavy, change often, and the MCP server
# never reads them. The README links to them upstream instead.
#
# One transform is applied during the sync. The skill's playbooks link to the
# upstream walkthroughs with repo-relative paths like
# ](../../docs/crash-dump-walkthrough.md). Those paths dangle once the skill is
# mirrored on its own, so the sync rewrites the markdown-link form
# ](../../docs/  ->  ](https://github.com/glslang/windbg-mcp/blob/main/docs/
# This touches only genuine markdown links; bare prose mentions of docs/ or
# examples/ (e.g. `examples/sweep_ioctls.ps1`, "Save it under docs/") are left
# as-is, since they read fine as references and are not clickable links.
#
# The skill's own sibling links (setup.md, ttd.md, crash-dump.md, ...) resolve
# within the mirrored directory and need no rewrite.
#
# This is a maintainer tool, not an installer. Run it to refresh skills/ when
# upstream changes, then commit the result.
#
# Usage:
#   sync-windbg.sh [--dry-run] [--ref <branch|tag|sha>]

set -euo pipefail

DRY_RUN=false
REF="main"

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
        -h | --help)
            sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# --- Upstream source ---
REPOSITORY="glslang/windbg-mcp"
BASE_PATH="skills"
# Path within the upstream repo whose commit date drives this power's version.
UPSTREAM_PATH="skills/windbg-debugging"

# The docs-link rewrite target: the upstream docs/ tree on GitHub.
DOCS_URL_BASE="https://github.com/glslang/windbg-mcp/blob/main/docs/"

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

echo -e "${GREEN}sync-windbg: $REPOSITORY@$REF ($BASE_PATH)${RESET}"
if [ "$DRY_RUN" = true ]; then echo -e "  ${YELLOW}[DRY RUN]${RESET}"; fi

# --- Download and extract archive ---
# Uses the tarball rather than the zip, since tar is always present while unzip
# is not installed on a minimal Linux.
TEMP_DIR=$(mktemp -d)
TARBALL_PATH="$TEMP_DIR/archive.tar.gz"

echo -e "${BLUE}  Downloading archive...${RESET}"
# The generic archive/<ref> form resolves a branch, tag, or commit SHA.
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

# Find extracted root (GitHub archives have a top-level folder like windbg-mcp-<ref>/)
EXTRACTED_ROOT=$(find "$TEMP_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)
SOURCE_ROOT="$EXTRACTED_ROOT/$BASE_PATH"

if [ ! -d "$SOURCE_ROOT" ]; then
    echo "Error: Skills path not found in archive: $BASE_PATH" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Rewrite dangling ../../docs/ markdown links to upstream URLs ---
# Only the markdown-link form ](../../docs/ is rewritten. Bare prose is untouched.
rewrite_docs_links() {
    local source_file="$1"
    local dest_file="$2"
    sed "s#](\.\./\.\./docs/#](${DOCS_URL_BASE}#g" "$source_file" >"$dest_file"
}

# --- Stats ---
STAT_CREATED=0
STAT_UPDATED=0
STAT_UNCHANGED=0
STAT_REWRITTEN=0

# --- File output ---
# Compares with CR removed. Comparing this way avoids reporting every file as
# changed on a Windows working tree, where text=auto yields CRLF while upstream
# archives are always LF.
copy_output_file() {
    local source_path="$1"
    local dest_path="$2"
    local relative_path="./${dest_path#"$SCRIPT_DIR"/}"

    if [ -f "$dest_path" ]; then
        if diff -q <(tr -d '\r' <"$source_path") <(tr -d '\r' <"$dest_path") >/dev/null 2>&1; then
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

# --- Mirror one skill folder ---
# Every .md file is passed through the docs-link rewrite. The rewrite is a no-op
# for files with no such link, so the compare/copy path stays byte-exact.
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
        elif [[ "$name" == *.md ]]; then
            # Rewrite to a temp file, then take the same compare/copy path as
            # every other file. A file with no ../../docs/ link comes through
            # unchanged, so this stays byte-exact for those.
            local staged="$TEMP_DIR/$name.staged"
            rewrite_docs_links "$item" "$staged"
            if ! diff -q "$item" "$staged" >/dev/null 2>&1; then
                echo "    [rewrite] $name (../../docs/ links -> upstream URL)"
                STAT_REWRITTEN=$((STAT_REWRITTEN + 1))
            fi
            copy_output_file "$staged" "$local_base/$name"
            rm -f "$staged"
        else
            copy_output_file "$item" "$local_base/$name"
        fi
    done
}

# --- Mirror a directory tree verbatim (for any nested support dirs) ---
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

# --- Main sync ---
SKILLS=()
for dir in "$SOURCE_ROOT"/*/; do
    if [ ! -d "$dir" ]; then continue; fi
    SKILLS+=("$(basename "$dir")")
done

echo "  Found ${#SKILLS[@]} skill(s)"

echo -e "${BLUE}  Syncing skills...${RESET}"
for s in "${SKILLS[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$s" "$s"
done

# --- Orphan detection ---
ORPHANS=()
if [ -d "$SKILLS_ROOT" ]; then
    for dir in "$SKILLS_ROOT"/*/; do
        if [ ! -d "$dir" ]; then continue; fi
        name=$(basename "$dir")
        if [ -d "$SOURCE_ROOT/$name" ]; then continue; fi
        ORPHANS+=("$name")
    done
fi

rm -rf "$TEMP_DIR"

# --- Version ---
# Derive the version from the commit date of UPSTREAM_PATH at REF, and write it
# to plugin.json and POWER.md. This is the same derivation whether REF is a seed
# tag (e.g. v1.0.0) or the default branch (the bump workflow's path), so there
# is one source of truth. The regression guard refuses a version that would move
# backwards, which usually means an upstream force-push worth investigating.
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
echo "    Rewritten:  $STAT_REWRITTEN file(s) (docs links)"
echo "    Version:    $VERSION_STATUS"
echo "    Output:     $SKILLS_ROOT"

# A regression means upstream appears to have moved backwards (e.g. force-push).
# Exit non-zero so a caller (the bump workflow) can revert this power's changes
# and flag it, rather than committing content with a stale version.
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
