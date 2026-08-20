#!/usr/bin/env bash
set -euo pipefail

# sync-pstack.sh — Syncs pstack skills from GitHub to Kiro global steering.
#
# Downloads the pstack plugin repo as a zip archive, extracts SKILL.md files,
# injects Kiro front-matter (inclusion mode), and writes them to
# ~/.kiro/steering/pstack/. Support files (playbooks, references) are renamed
# to .txt so Kiro's recursive .md scanner does not auto-load them. Scripts
# directories are skipped entirely.
#
# On first run, creates a default config at sync-pstack.config.json next to
# this script. Edit that file to control which skills are always-on, auto, or
# manual (the default).
#
# Usage:
#   sync-pstack.sh [--init] [--dry-run]

INIT=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --init)    INIT=true ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            sed -n '3,/^$/s/^# //p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/sync-pstack.config.json"
STEERING_ROOT="$HOME/.kiro/steering/pstack"

# --- Default config ---
DEFAULT_CONFIG='{
  "repository": "cursor/plugins",
  "branch": "main",
  "basePath": "pstack/skills",
  "includeAlways": [
    "principle-laziness-protocol",
    "unslop"
  ],
  "includeAuto": []
}'

# --- Ensure config exists ---
if [ "$INIT" = true ] || [ ! -f "$CONFIG_PATH" ]; then
    action="Created"
    [ -f "$CONFIG_PATH" ] && action="Recreated"
    echo "$DEFAULT_CONFIG" > "$CONFIG_PATH"
    echo "  $action config: $CONFIG_PATH"
    if [ "$INIT" = true ]; then
        echo "  Edit includeAlways/includeAuto to control skill inclusion modes."
        exit 0
    fi
fi

# --- Load config (requires jq) ---
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install with: brew install jq / apt install jq" >&2
    exit 1
fi

REPOSITORY=$(jq -r '.repository' "$CONFIG_PATH")
BRANCH=$(jq -r '.branch' "$CONFIG_PATH")
BASE_PATH=$(jq -r '.basePath' "$CONFIG_PATH")

INCLUDE_ALWAYS=()
while IFS= read -r line; do
    INCLUDE_ALWAYS+=("$line")
done < <(jq -r '.includeAlways[]' "$CONFIG_PATH")

INCLUDE_AUTO=()
while IFS= read -r line; do
    INCLUDE_AUTO+=("$line")
done < <(jq -r '.includeAuto[]' "$CONFIG_PATH")

echo "sync-pstack: $REPOSITORY@$BRANCH ($BASE_PATH)"
[ "$DRY_RUN" = true ] && echo "  [DRY RUN]"

# --- Download and extract archive ---
TEMP_DIR=$(mktemp -d)
ZIP_PATH="$TEMP_DIR/archive.zip"

echo "  Downloading archive..."
ARCHIVE_URL="https://github.com/$REPOSITORY/archive/refs/heads/$BRANCH.zip"
if ! curl -fsSL "$ARCHIVE_URL" -o "$ZIP_PATH"; then
    echo "Error: Failed to download archive" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "  Extracting..."
unzip -q "$ZIP_PATH" -d "$TEMP_DIR"
rm "$ZIP_PATH"

# Find extracted root (GitHub archives have a top-level folder like plugins-main/)
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
STAT_SUPPORT=0

# --- Helpers ---
is_include_always() {
    local name="$1"
    for item in "${INCLUDE_ALWAYS[@]}"; do
        [ "$item" = "$name" ] && return 0
    done
    return 1
}

is_include_auto() {
    local name="$1"
    for item in "${INCLUDE_AUTO[@]}"; do
        [ "$item" = "$name" ] && return 0
    done
    return 1
}

# --- Parse upstream front-matter ---
get_upstream_description() {
    local content="$1"
    # Extract description from YAML front-matter between --- delimiters
    local desc
    desc=$(echo "$content" | sed -n '1,/^---$/!b; /^---$/,/^---$/{/^description:/s/^description:[[:space:]]*"\{0,1\}\(.*\)"\{0,1\}[[:space:]]*$/\1/p}')
    # Try alternate: content between first and second ---
    if [ -z "$desc" ]; then
        desc=$(echo "$content" | awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[[:space:]]*"?/, ""); sub(/"?[[:space:]]*$/, ""); print; exit}')
    fi
    echo "$desc"
}

# --- Front-matter injection ---
add_kiro_front_matter() {
    local content="$1"
    local skill_name="$2"
    local inclusion_mode="$3"

    # Extract description from upstream front-matter
    local description
    description=$(get_upstream_description "$content")
    if [ -z "$description" ]; then
        description="pstack skill: $skill_name"
    fi

    # Strip existing Cursor front-matter
    local stripped
    stripped=$(echo "$content" | sed '1{/^---$/,/^---$/d}')
    stripped=$(echo "$stripped" | sed '/./,$!d')

    printf '%s%s' "---
inclusion: $inclusion_mode
name: pstack-$skill_name
description: \"$description\"
---

" "$stripped"
}

# --- File output ---
write_output_file() {
    local local_path="$1"
    local content="$2"
    local relative_path="${local_path#$STEERING_ROOT}"
    relative_path="~/.kiro/steering/pstack$relative_path"

    if [ "$DRY_RUN" = true ]; then
        local action="create"
        [ -f "$local_path" ] && action="update"
        echo "    [$action] $relative_path"
        if [ "$action" = "create" ]; then
            STAT_CREATED=$((STAT_CREATED + 1))
        else
            STAT_UPDATED=$((STAT_UPDATED + 1))
        fi
        return
    fi

    mkdir -p "$(dirname "$local_path")"

    if [ -f "$local_path" ]; then
        existing=$(cat "$local_path")
        if [ "$existing" = "$content" ]; then
            echo "    [unchanged] $relative_path"
            STAT_UNCHANGED=$((STAT_UNCHANGED + 1))
            return
        fi
        echo "    [updated] $relative_path"
        STAT_UPDATED=$((STAT_UPDATED + 1))
    else
        echo "    [created] $relative_path"
        STAT_CREATED=$((STAT_CREATED + 1))
    fi

    printf '%s' "$content" > "$local_path"
}

# --- Sync support subdirectory (playbooks, references) ---
sync_support_dir() {
    local source_dir="$1"
    local dest_dir="$2"

    for item in "$source_dir"/*; do
        [ ! -e "$item" ] && continue
        if [ -d "$item" ]; then
            sync_support_dir "$item" "$dest_dir/$(basename "$item")"
        else
            local content
            content=$(cat "$item")
            local name
            name=$(basename "$item")
            # Rename .md to .md.txt
            if [[ "$name" == *.md ]]; then
                name="${name}.txt"
            fi
            write_output_file "$dest_dir/$name" "$content"
            STAT_SUPPORT=$((STAT_SUPPORT + 1))
        fi
    done
}

# --- Sync a single skill folder ---
sync_skill_folder() {
    local source_dir="$1"
    local skill_name="$2"
    local category="$3"

    local local_base
    if [ "$category" = "principles" ]; then
        local short_name="${skill_name#principle-}"
        local_base="$STEERING_ROOT/principles/$short_name"
    else
        local_base="$STEERING_ROOT/skills/$skill_name"
    fi

    local inclusion_mode="manual"
    if is_include_always "$skill_name"; then
        inclusion_mode="always"
    elif is_include_auto "$skill_name"; then
        inclusion_mode="auto"
    fi

    for item in "$source_dir"/*; do
        [ ! -e "$item" ] && continue
        local name
        name=$(basename "$item")

        if [ -d "$item" ]; then
            sync_support_dir "$item" "$local_base/$name"
        elif [ "$name" = "SKILL.md" ]; then
            local content
            content=$(cat "$item")
            local display_name="$skill_name"
            [ "$category" = "principles" ] && display_name="${skill_name#principle-}"
            local transformed
            transformed=$(add_kiro_front_matter "$content" "$display_name" "$inclusion_mode")
            write_output_file "$local_base/SKILL.md" "$transformed"
        fi
    done
}

# --- Main sync ---
SKILLS=()
PRINCIPLES=()

for dir in "$SOURCE_ROOT"/*/; do
    [ ! -d "$dir" ] && continue
    name=$(basename "$dir")
    if [[ "$name" == principle-* ]]; then
        PRINCIPLES+=("$name")
    else
        SKILLS+=("$name")
    fi
done

echo "  Found $((${#SKILLS[@]} + ${#PRINCIPLES[@]})) skills (${#SKILLS[@]} skills, ${#PRINCIPLES[@]} principles)"

echo "  Syncing skills..."
for s in "${SKILLS[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$s" "$s" "skills"
done

echo "  Syncing principles..."
for p in "${PRINCIPLES[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$p" "$p" "principles"
done

# --- Cleanup temp ---
rm -rf "$TEMP_DIR"

# --- Summary ---
echo ""
echo "  Done."
echo "    Created:   $STAT_CREATED"
echo "    Updated:   $STAT_UPDATED"
echo "    Unchanged: $STAT_UNCHANGED"
echo "    Support:   $STAT_SUPPORT (playbooks/references as .md.txt)"
echo "    Output:    $STEERING_ROOT"

if [ ${#INCLUDE_ALWAYS[@]} -gt 0 ]; then
    echo "    Always-on: $(IFS=', '; echo "${INCLUDE_ALWAYS[*]}")"
fi
if [ ${#INCLUDE_AUTO[@]} -gt 0 ]; then
    echo "    Auto:      $(IFS=', '; echo "${INCLUDE_AUTO[*]}")"
fi
