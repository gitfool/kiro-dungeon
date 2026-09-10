#!/usr/bin/env bash
set -euo pipefail

# sync-dotnet-msbuild.sh — Mirrors the dotnet/skills dotnet-msbuild plugin skills
# and agents from GitHub into this power's skills/ directory.
#
# Downloads the dotnet-msbuild plugin from the dotnet/skills repo and mirrors its
# skills into ./skills/, so this directory can be installed as a Kiro power.
#
# Additionally, the plugin's agent definitions (agents/*.agent.md) are converted to
# skills. Kiro does not consume the Agent Plugins "agents" manifest field, so the
# agent content would otherwise be dropped. Conversion strips agent-specific
# frontmatter (user-invokable), keeps disable-model-invocation so the skill's
# activation intent is preserved, and — for the routing agent — renames it (see
# AGENT_RENAMES).
#
# One agent carries GitHub Copilot tool references (#tool:agent/runSubagent,
# #tool:web/fetch) that mean nothing on Kiro. Rather than rewrite the prose, the
# sync appends a short "Kiro tool interpretation" note to each converted agent
# skill, mapping those references to Kiro equivalents at read time. The note is
# injected into all converted agents (harmless for those that don't use the tools,
# future-proof if upstream adds such references later).
#
# The manifests (plugin.json, mcp.json), README, and this script are maintained by
# hand and are NOT touched by the sync — it only writes under skills/. Upstream's
# plugin.json is intentionally NOT mirrored: it is non-compliant with Agent Plugins
# 1.0.0 (missing $schema, and carries skills/agents/mcpServers keys Kiro strips).
# See https://github.com/dotnet/skills/issues/1087. The .claude-plugin/,
# .codex-plugin/, and version.json entries live outside skills/ and agents/, so
# they are naturally excluded.
#
# Support directories (references, scripts) under a skill are mirrored as-is. Only
# immediate subdirectories of skills/ are treated as skills by Kiro, so nested
# markdown is never loaded and needs no special handling.
#
# This is a maintainer tool, not an installer. Run it to refresh skills/ when
# upstream changes, then commit the result.
#
# Usage:
#   sync-dotnet-msbuild.sh [--dry-run] [--ref <branch|tag|sha>]

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
REPOSITORY="dotnet/skills"
BASE_PATH="plugins/dotnet-msbuild/skills"
AGENTS_PATH="plugins/dotnet-msbuild/agents"
# Path within the upstream repo whose commit date drives this power's version.
# The whole plugin dir, not just skills/, so a change to the agents (which we
# convert) or other plugin content is still reflected in the version.
UPSTREAM_PATH="plugins/dotnet-msbuild"
# Default ref when --ref is not given (the bump workflow's path).
REF="${REF:-main}"

# Agent basenames (without the .agent.md suffix) to convert to skills. All three
# are substantial standalone content, not routing stubs, so all are converted.
AGENTS_TO_CONVERT=(build-perf msbuild-code-review msbuild)

# Agent -> skill directory renames. The bare "msbuild" name is too broad for an
# auto-activating skill sitting alongside 20 others, so it becomes "msbuild-expert".
declare -A AGENT_RENAMES=(
    [msbuild]=msbuild-expert
)

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_ROOT="$SCRIPT_DIR/skills"
PLUGIN_JSON="$SCRIPT_DIR/plugin.json"

# Shared version-derivation helpers (derive_version, latest_commit_for_path,
# is_version_regression, write_power_version).
source "$SCRIPT_DIR/../.github/scripts/lib/version.sh"

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${GREEN}sync-dotnet-msbuild: $REPOSITORY@$REF ($BASE_PATH)${RESET}"
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

# Find extracted root (GitHub archives have a top-level folder like skills-main/)
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
# Skill names already match their directory names upstream (unlike pstack's
# poteto-mode), so no name normalization is needed; SKILL.md is copied verbatim.
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

# --- Convert an agent .agent.md to a skill SKILL.md ---
# Strips agent-only frontmatter (user-invokable), normalizes the name to the skill
# directory name, and appends a Kiro tool-interpretation note after the body.
convert_agent_to_skill() {
    local source_file="$1"
    local skill_name="$2"
    local dest_file="$3"

    awk -v name="$skill_name" '
        BEGIN { fm = 0 }
        /^---[[:space:]]*$/ { fm++; print; next }
        fm == 1 && /^name:/ { print "name: " name; next }
        fm == 1 && /^user-invokable:/ { next }
        { print }
    ' "$source_file" > "$dest_file"

    # Append the Kiro tool-interpretation note (idempotent: only if not present).
    if ! grep -q "Kiro tool interpretation" "$dest_file"; then
        # Ensure the body ends with a newline so the heading isn't glued to the
        # last source line (source files may lack a trailing newline).
        [ -n "$(tail -c1 "$dest_file")" ] && printf '\n' >> "$dest_file"
        cat >> "$dest_file" <<'EOF'

## Kiro tool interpretation

This skill was converted from a GitHub Copilot / Codex agent definition. Interpret
its tool references as their Kiro equivalents:

- `#tool:agent/runSubagent` → dispatch a Kiro sub-agent with `invoke_sub_agent`
  (e.g. the `general-task-execution` or `context-gatherer` agent) for a focused,
  isolated sub-task.
- `#tool:web/fetch` → use Kiro's `web_fetch` (or `web_search` to find a URL first).

The `binlog` MCP server referenced by this skill is provided by this power's
`mcp.json`; its tools are available whenever the power is active.
EOF
    fi
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

# --- Sync agents (converted to skills) ---
AGENTS_ROOT="$EXTRACTED_ROOT/$AGENTS_PATH"
STAT_AGENTS_CONVERTED=0
STAT_AGENTS_SKIPPED=0

if [ -d "$AGENTS_ROOT" ]; then
    echo -e "${BLUE}  Syncing agents as skills...${RESET}"
    for af in "$AGENTS_ROOT"/*.agent.md; do
        if [ ! -f "$af" ]; then continue; fi
        agent_name=$(basename "$af" .agent.md)

        # Check if this agent is in the convert list
        found=false
        for a in "${AGENTS_TO_CONVERT[@]}"; do
            if [ "$a" = "$agent_name" ]; then found=true; break; fi
        done

        if [ "$found" = false ]; then
            echo "    [skipped] agents/$(basename "$af") (not in convert list)"
            STAT_AGENTS_SKIPPED=$((STAT_AGENTS_SKIPPED + 1))
            continue
        fi

        # Apply rename if configured
        skill_name="$agent_name"
        if [ -n "${AGENT_RENAMES[$agent_name]:-}" ]; then
            skill_name="${AGENT_RENAMES[$agent_name]}"
            echo "    [convert] agents/$(basename "$af") -> skills/$skill_name/SKILL.md (renamed from '$agent_name')"
        else
            echo "    [convert] agents/$(basename "$af") -> skills/$skill_name/SKILL.md"
        fi
        STAT_AGENTS_CONVERTED=$((STAT_AGENTS_CONVERTED + 1))

        local_staged="$TEMP_DIR/SKILL.md.agent-staged"
        convert_agent_to_skill "$af" "$skill_name" "$local_staged"
        copy_output_file "$local_staged" "$SKILLS_ROOT/$skill_name/SKILL.md"
        rm -f "$local_staged"
    done
else
    echo "  No agents/ directory found upstream, skipping."
fi

# --- Orphan detection ---
# A local skill is an orphan if it maps to neither an upstream skill nor a
# converted agent (accounting for renames).
ORPHANS=()
if [ -d "$SKILLS_ROOT" ]; then
    # Build the set of expected converted-agent skill directory names.
    CONVERTED_NAMES=()
    for a in "${AGENTS_TO_CONVERT[@]}"; do
        if [ -n "${AGENT_RENAMES[$a]:-}" ]; then
            CONVERTED_NAMES+=("${AGENT_RENAMES[$a]}")
        else
            CONVERTED_NAMES+=("$a")
        fi
    done

    for dir in "$SKILLS_ROOT"/*/; do
        if [ ! -d "$dir" ]; then continue; fi
        name=$(basename "$dir")
        # Skip if it exists upstream in skills/
        if [ -d "$SOURCE_ROOT/$name" ]; then continue; fi
        # Skip if it's a converted-agent skill
        found=false
        for c in "${CONVERTED_NAMES[@]}"; do
            if [ "$c" = "$name" ]; then found=true; break; fi
        done
        if [ "$found" = true ]; then continue; fi
        ORPHANS+=("$name")
    done
fi

# --- Cleanup temp ---
rm -rf "$TEMP_DIR"

# --- Versioning ---
# Derive the version from the commit date of UPSTREAM_PATH at REF, and write it
# to plugin.json. This is the same derivation whether REF is a seed tag (e.g.
# v0.1.8) or the default branch (the bump workflow's path), so there is one
# source of truth. The regression guard refuses a version that would move
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
            write_power_version "$next_version" "$PLUGIN_JSON"
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
echo "    Agents:     $STAT_AGENTS_CONVERTED converted, $STAT_AGENTS_SKIPPED skipped"
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
