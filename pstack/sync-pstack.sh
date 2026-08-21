#!/usr/bin/env bash
set -euo pipefail

# sync-pstack.sh — Mirrors pstack skills from GitHub into this power's skills/ directory.
#
# Downloads the pstack plugin from the cursor/plugins repo and mirrors its
# skills into ./skills/, so this directory can be installed as a Kiro power.
#
# Content is copied verbatim apart from one fix. The Agent Skills spec requires
# each skill's name field to match its directory name exactly, and upstream
# poteto-mode declares "Poteto Mode". Kiro rejects skills whose name does not
# match, silently, so the name is normalized during the sync. See
# https://github.com/cursor/plugins/issues/237.
#
# Support directories (playbooks, references, scripts) are mirrored as-is.
# Only immediate subdirectories of skills/ are treated as skills, so nested
# markdown is never loaded and needs no special handling.
#
# This is a maintainer tool, not an installer. Run it to refresh skills/ when
# upstream changes, then commit the result.
#
# Usage:
#   sync-pstack.sh [--dry-run]

DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# --- Upstream source ---
REPOSITORY="cursor/plugins"
BRANCH="main"
BASE_PATH="pstack/skills"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_ROOT="$SCRIPT_DIR/skills"

echo "sync-pstack: $REPOSITORY@$BRANCH ($BASE_PATH)"
if [ "$DRY_RUN" = true ]; then echo "  [DRY RUN]"; fi

# --- Download and extract archive ---
# Uses the tarball rather than the zip, since tar is always present while unzip
# is not installed on a minimal Linux. The pwsh twin uses the zip, because
# Expand-Archive is built in there.
TEMP_DIR=$(mktemp -d)
TARBALL_PATH="$TEMP_DIR/archive.tar.gz"

echo "  Downloading archive..."
ARCHIVE_URL="https://github.com/$REPOSITORY/archive/refs/heads/$BRANCH.tar.gz"
if ! curl -fsSL "$ARCHIVE_URL" -o "$TARBALL_PATH"; then
    echo "Error: Failed to download archive" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "  Extracting..."
tar -xzf "$TARBALL_PATH" -C "$TEMP_DIR"
rm "$TARBALL_PATH"

# Find extracted root (GitHub archives have a top-level folder like plugins-main/)
EXTRACTED_ROOT=$(find "$TEMP_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)
SOURCE_ROOT="$EXTRACTED_ROOT/$BASE_PATH"

if [ ! -d "$SOURCE_ROOT" ]; then
    echo "Error: Skills path not found in archive: $BASE_PATH" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Normalize the skill name to match its directory ---
set_skill_name() {
    local source_file="$1"
    local skill_name="$2"
    local dest_file="$3"

    awk -v name="$skill_name" '
        BEGIN { fm = 0 }
        /^---[[:space:]]*$/ { fm++; print; next }
        fm == 1 && /^name:/ { print "name: " name; next }
        { print }
    ' "$source_file" > "$dest_file"
}

# --- Stats ---
STAT_CREATED=0
STAT_UPDATED=0
STAT_UNCHANGED=0
STAT_NORMALIZED=0

# --- File output ---
# Compares with CR removed. Comparing this way avoids reporting every file as
# changed on a Windows working tree, where text=auto yields CRLF while upstream
# archives are always LF.
copy_output_file() {
    local source_path="$1"
    local dest_path="$2"
    local relative_path="./${dest_path#$SCRIPT_DIR/}"

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
        elif [ "$name" = "SKILL.md" ]; then
            # Transform to a temp file, then take the same compare and copy path
            # as every other file, so output stays byte-exact.
            local staged="$TEMP_DIR/SKILL.md.staged"
            set_skill_name "$item" "$skill_name" "$staged"
            if ! diff -q "$item" "$staged" >/dev/null 2>&1; then
                echo "    [name] normalized to '$skill_name'"
                STAT_NORMALIZED=$((STAT_NORMALIZED + 1))
            fi
            copy_output_file "$staged" "$local_base/SKILL.md"
            rm -f "$staged"
        else
            copy_output_file "$item" "$local_base/$name"
        fi
    done
}

# --- Main sync ---
SKILLS=()
PRINCIPLES=()

for dir in "$SOURCE_ROOT"/*/; do
    if [ ! -d "$dir" ]; then continue; fi
    name=$(basename "$dir")
    case "$name" in
        principle-*) PRINCIPLES+=("$name") ;;
        *)           SKILLS+=("$name") ;;
    esac
done

echo "  Found $((${#SKILLS[@]} + ${#PRINCIPLES[@]})) skills (${#SKILLS[@]} skills, ${#PRINCIPLES[@]} principles)"

echo "  Syncing skills..."
for s in "${SKILLS[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$s" "$s"
done

echo "  Syncing principles..."
for p in "${PRINCIPLES[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$p" "$p"
done

# --- Orphan detection ---
ORPHANS=()
if [ -d "$SKILLS_ROOT" ]; then
    for dir in "$SKILLS_ROOT"/*/; do
        if [ ! -d "$dir" ]; then continue; fi
        name=$(basename "$dir")
        if [ ! -d "$SOURCE_ROOT/$name" ]; then
            ORPHANS+=("$name")
        fi
    done
fi

# --- Cleanup temp ---
rm -rf "$TEMP_DIR"

# --- Summary ---
echo ""
echo "  Done."
echo "    Created:    $STAT_CREATED"
echo "    Updated:    $STAT_UPDATED"
echo "    Unchanged:  $STAT_UNCHANGED"
echo "    Normalized: $STAT_NORMALIZED skill name(s)"
echo "    Output:     $SKILLS_ROOT"

if [ ${#ORPHANS[@]} -gt 0 ]; then
    echo ""
    echo "  ${#ORPHANS[@]} local skill(s) no longer exist upstream:"
    for o in "${ORPHANS[@]}"; do echo "    $o"; done
    printf "  Remove with: git rm -r"
    for o in "${ORPHANS[@]}"; do printf " skills/%s" "$o"; done
    printf "\n"
fi
