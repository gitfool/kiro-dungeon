#!/usr/bin/env bash
set -euo pipefail

# sync-pstack.sh — Mirrors pstack skills and selected agents from GitHub into this
# power skills/ directory.
#
# Downloads the pstack plugin from the cursor/plugins repo and mirrors its skills
# into ./skills/, so this directory can be installed as a Kiro power.
#
# Additionally, selected agent definitions from the upstream agents/ directory
# are converted to skills. The AGENTS_TO_CONVERT list controls which agents are
# included; others (like poteto-agent, which is a routing stub) are skipped.
# Conversion strips agent-specific frontmatter (is_background), normalizes the
# name, and adds disable-model-invocation: true so the skill only fires on
# explicit request.
#
# Content is copied verbatim apart from one fix. The Agent Skills spec requires
# each skill's name field to match its directory name exactly, and upstream
# poteto-mode declares "Poteto Mode". Kiro rejects skills whose name does not
# match, silently, so the name is normalized during the sync. See
# https://github.com/cursor/plugins/issues/237.
#
# After syncing, a Kiro compatibility pass applies guards to skills that need
# prerequisites or are not operational on Kiro. Content-level Cursor terminology
# (Task calls, subagent_type, ~/.cursor/ paths, etc.) is NOT rewritten by this
# script; instead, global steering files (steering/cursor-runtime.md for generic
# Cursor runtime operations, steering/pstack.md for pstack-specific mappings)
# provide interpretation rules the agent applies at read time. This avoids brittle
# regex substitutions on varied prose.
# Skills that are entirely Cursor-specific (grokbot, setup-pstack) are excluded
# from the sync entirely.
#
# Support directories (playbooks, references, scripts) are mirrored as-is. Only
# immediate subdirectories of skills/ are treated as skills, so nested markdown
# is never loaded and needs no special handling.
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
AGENTS_PATH="pstack/agents"

# Agents to convert to skills. Others (e.g. poteto-agent) are skipped because
# they're routing stubs with no standalone value.
AGENTS_TO_CONVERT=(comment-sicko)

# Skills to exclude entirely (Cursor-specific, no Kiro equivalent).
SKILLS_TO_EXCLUDE=(grokbot setup-pstack)

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_ROOT="$SCRIPT_DIR/skills"

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${GREEN}sync-pstack: $REPOSITORY@$BRANCH ($BASE_PATH)${RESET}"
if [ "$DRY_RUN" = true ]; then echo -e "  ${YELLOW}[DRY RUN]${RESET}"; fi

# --- Download and extract archive ---
# Uses the tarball rather than the zip, since tar is always present while unzip
# is not installed on a minimal Linux. The pwsh twin uses the zip, because
# Expand-Archive is built in there.
TEMP_DIR=$(mktemp -d)
TARBALL_PATH="$TEMP_DIR/archive.tar.gz"

echo -e "${BLUE}  Downloading archive...${RESET}"
ARCHIVE_URL="https://github.com/$REPOSITORY/archive/refs/heads/$BRANCH.tar.gz"
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

# --- Convert an agent .md to a skill SKILL.md ---
# Strips agent-specific frontmatter fields (is_background), normalizes the name,
# and adds disable-model-invocation: true so the skill only activates on explicit
# request.
convert_agent_to_skill() {
    local source_file="$1"
    local skill_name="$2"
    local dest_file="$3"

    awk -v name="$skill_name" '
        BEGIN { fm = 0; added_dmi = 0 }
        /^---[[:space:]]*$/ {
            fm++
            if (fm == 2 && !added_dmi) {
                print "disable-model-invocation: true"
            }
            print
            next
        }
        fm == 1 && /^name:/ { print "name: " name; next }
        fm == 1 && /^is_background:/ { next }
        fm == 1 && /^disable-model-invocation:/ { added_dmi = 1; print; next }
        { print }
    ' "$source_file" > "$dest_file"
}

# --- Kiro guards ---
# Prepends a compatibility note after the frontmatter closing '---'.
# Usage: prepend_kiro_guard <file> <guard_text>
prepend_kiro_guard() {
    local file="$1"
    local guard="$2"
    local tmp="$file.kiro-tmp"

    awk -v guard="$guard" '
        BEGIN { fm = 0; done = 0 }
        /^---[[:space:]]*$/ {
            fm++
            print
            if (fm == 2 && !done) {
                print ""
                print "> **Kiro compatibility:** " guard
                print ""
                done = 1
            }
            next
        }
        { print }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
}

# --- Main sync ---
SKILLS=()
PRINCIPLES=()

for dir in "$SOURCE_ROOT"/*/; do
    if [ ! -d "$dir" ]; then continue; fi
    name=$(basename "$dir")
    # Skip excluded skills (Cursor-specific, no Kiro equivalent)
    skip=false
    for ex in "${SKILLS_TO_EXCLUDE[@]}"; do
        if [ "$ex" = "$name" ]; then skip=true; break; fi
    done
    if [ "$skip" = true ]; then
        echo "    [excluded] $name (Cursor-specific)"
        continue
    fi
    case "$name" in
        principle-*) PRINCIPLES+=("$name") ;;
        *)           SKILLS+=("$name") ;;
    esac
done

echo "  Found $((${#SKILLS[@]} + ${#PRINCIPLES[@]})) skills (${#SKILLS[@]} skills, ${#PRINCIPLES[@]} principles)"

echo -e "${BLUE}  Syncing skills...${RESET}"
for s in "${SKILLS[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$s" "$s"
done

echo -e "${BLUE}  Syncing principles...${RESET}"
for p in "${PRINCIPLES[@]}"; do
    sync_skill_folder "$SOURCE_ROOT/$p" "$p"
done

# --- Sync agents (converted to skills) ---
AGENTS_ROOT="$EXTRACTED_ROOT/$AGENTS_PATH"
STAT_AGENTS_CONVERTED=0
STAT_AGENTS_SKIPPED=0

if [ -d "$AGENTS_ROOT" ]; then
    echo -e "${BLUE}  Syncing agents as skills...${RESET}"
    for af in "$AGENTS_ROOT"/*.md; do
        if [ ! -f "$af" ]; then continue; fi
        agent_name=$(basename "$af" .md)

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

        echo "    [convert] agents/$(basename "$af") -> skills/$agent_name/SKILL.md"
        STAT_AGENTS_CONVERTED=$((STAT_AGENTS_CONVERTED + 1))

        local_staged="$TEMP_DIR/SKILL.md.agent-staged"
        convert_agent_to_skill "$af" "$agent_name" "$local_staged"
        copy_output_file "$local_staged" "$SKILLS_ROOT/$agent_name/SKILL.md"
        rm -f "$local_staged"
    done
else
    echo "  No agents/ directory found upstream, skipping."
fi

# --- Orphan detection ---
ORPHANS=()
if [ -d "$SKILLS_ROOT" ]; then
    for dir in "$SKILLS_ROOT"/*/; do
        if [ ! -d "$dir" ]; then continue; fi
        name=$(basename "$dir")
        # Skip if it exists upstream in skills/
        if [ -d "$SOURCE_ROOT/$name" ]; then continue; fi
        # Skip if it's an agent-converted skill
        found=false
        for a in "${AGENTS_TO_CONVERT[@]}"; do
            if [ "$a" = "$name" ]; then found=true; break; fi
        done
        if [ "$found" = true ]; then continue; fi
        # Skip excluded skills (they're intentionally not synced)
        for ex in "${SKILLS_TO_EXCLUDE[@]}"; do
            if [ "$ex" = "$name" ]; then found=true; break; fi
        done
        if [ "$found" = true ]; then continue; fi
        ORPHANS+=("$name")
    done
fi

# --- Cleanup temp ---
rm -rf "$TEMP_DIR"

# --- Kiro transform pass ---
# Applies guards to skills/playbooks that need them. Content transforms are
# handled by the global steering files (see steering/cursor-runtime.md and
# steering/pstack.md) rather than by sed, because prose varies too much for
# reliable regex substitution.
STAT_GUARDED=0

if [ -d "$SKILLS_ROOT" ]; then
    echo -e "${BLUE}  Applying Kiro guards...${RESET}"

    # Short-circuit guards for skills with partial limitations
    declare -A TIER1_GUARDS=(
        [show-me-your-work]="The transcript audit step requires session history access. Skip that step if unavailable."
    )

    for skill in "${!TIER1_GUARDS[@]}"; do
        skill_file="$SKILLS_ROOT/$skill/SKILL.md"
        if [ -f "$skill_file" ]; then
            if [ "$DRY_RUN" = false ]; then
                prepend_kiro_guard "$skill_file" "${TIER1_GUARDS[$skill]}"
            fi
            echo "    [guard] $skill (partial limitation)"
            STAT_GUARDED=$((STAT_GUARDED + 1))
        fi
    done

    # Not-operational guards for skills/playbooks that cannot work on Kiro
    declare -A TIER2_SKILL_GUARDS=(
        [recall]="Not operational on Kiro. Requires Cursor transcript file access for context reconstruction. No equivalent mechanism exists."
        [reflect]="Not operational on Kiro. Requires Cursor transcript file access for learning extraction. No equivalent mechanism exists."
    )

    for skill in "${!TIER2_SKILL_GUARDS[@]}"; do
        skill_file="$SKILLS_ROOT/$skill/SKILL.md"
        if [ -f "$skill_file" ]; then
            if [ "$DRY_RUN" = false ]; then
                prepend_kiro_guard "$skill_file" "${TIER2_SKILL_GUARDS[$skill]}"
            fi
            echo "    [guard] $skill (not operational)"
            STAT_GUARDED=$((STAT_GUARDED + 1))
        fi
    done

    declare -A TIER2_PLAYBOOK_GUARDS=(
        [orchestrate]="Not operational on Kiro. Requires Cursor-specific orchestration tooling (cloud agents, orch.ts state CLI). Read for methodology only."
        [shipping]="Not operational on Kiro. Requires Graphite stack model and cloud agents for per-PR verification. Read for methodology only."
        [autopilot-full]="Not operational on Kiro. Requires Cursor cloud agents and Graphite for autonomous merge. Read for methodology only."
        [autopilot-stack]="Not operational on Kiro. Requires Cursor cloud agents and Graphite for autonomous stack delivery. Read for methodology only."
        [session-pickup]="Not operational on Kiro. Requires Cursor transcript file access for session resumption."
        [pause-safely]="Not operational on Kiro. References Cursor restart and transcript persistence behavior. On Kiro, session state is managed by the platform."
        [worktree-cleanup]="References Cursor worktree layout. On Kiro, use \`git worktree list\` directly and skip \`.cursor/worktrees/\` references."
    )

    for playbook in "${!TIER2_PLAYBOOK_GUARDS[@]}"; do
        playbook_file="$SKILLS_ROOT/poteto-mode/playbooks/$playbook.md"
        if [ -f "$playbook_file" ]; then
            if [ "$DRY_RUN" = false ]; then
                # Playbooks don't have frontmatter, so prepend the guard directly
                tmp="$playbook_file.kiro-tmp"
                {
                    echo "> **Kiro compatibility:** ${TIER2_PLAYBOOK_GUARDS[$playbook]}"
                    echo ""
                    cat "$playbook_file"
                } > "$tmp"
                mv "$tmp" "$playbook_file"
            fi
            echo "    [guard] playbooks/$playbook (not operational)"
            STAT_GUARDED=$((STAT_GUARDED + 1))
        fi
    done
fi

# --- Summary ---
echo ""
echo -e "${GREEN}  Done.${RESET}"
echo "    Created:    $STAT_CREATED"
echo "    Updated:    $STAT_UPDATED"
echo "    Unchanged:  $STAT_UNCHANGED"
echo "    Normalized: $STAT_NORMALIZED skill name(s)"
echo "    Agents:     $STAT_AGENTS_CONVERTED converted, $STAT_AGENTS_SKIPPED skipped"
echo "    Excluded:   ${#SKILLS_TO_EXCLUDE[@]} skill(s) (Cursor-specific)"
echo "    Guards:     $STAT_GUARDED"
echo "    Output:     $SKILLS_ROOT"

if [ ${#ORPHANS[@]} -gt 0 ]; then
    echo ""
    echo "  ${#ORPHANS[@]} local skill(s) no longer exist upstream:"
    for o in "${ORPHANS[@]}"; do echo "    $o"; done
    printf "  Remove with: git rm -r"
    for o in "${ORPHANS[@]}"; do printf " skills/%s" "$o"; done
    printf "\n"
fi
