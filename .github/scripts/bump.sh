#!/usr/bin/env bash

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

if [ "$DRY_RUN" = true ]; then echo -e "${YELLOW}[DRY RUN]${RESET}"; fi

# --- Upstream mapping ---
# Each power directory maps to its upstream repo and path.
# Format: "owner/repo:path"
declare -A UPSTREAM=(
    [pstack]="cursor/plugins:pstack"
)

# --- Derive version from a UTC commit date ---
# Format: yyMM.dHH.mss (leading zeros stripped from minor/patch)
derive_version() {
    local iso_date="$1"

    # Parse UTC components from ISO 8601 date
    local yy mm dd hh mi ss
    yy=$(date -u -d "$iso_date" +%y)
    mm=$(date -u -d "$iso_date" +%m)
    dd=$(date -u -d "$iso_date" +%d)
    hh=$(date -u -d "$iso_date" +%H)
    mi=$(date -u -d "$iso_date" +%M)
    ss=$(date -u -d "$iso_date" +%S)

    local major="${yy}${mm}"
    local minor="${dd}${hh}"
    local patch="${mi}${ss}"

    # Strip leading zeros (but keep at least one digit)
    minor=$((10#$minor))
    patch=$((10#$patch))

    echo "${major}.${minor}.${patch}"
}

# --- Compare semver (major.minor.patch only, ignoring metadata) ---
# Prints: -1 if a < b, 0 if a == b, 1 if a > b
semver_compare() {
    local a="$1" b="$2"
    # Strip build metadata
    a="${a%%+*}"
    b="${b%%+*}"
    # Strip prerelease
    a="${a%%-*}"
    b="${b%%-*}"

    local a_major="${a%%.*}" b_major="${b%%.*}"
    local a_rest="${a#*.}" b_rest="${b#*.}"
    local a_minor="${a_rest%%.*}" b_minor="${b_rest%%.*}"
    local a_patch="${a_rest#*.}" b_patch="${b_rest#*.}"

    if (( a_major > b_major )); then echo 1; return; fi
    if (( a_major < b_major )); then echo -1; return; fi
    if (( a_minor > b_minor )); then echo 1; return; fi
    if (( a_minor < b_minor )); then echo -1; return; fi
    if (( a_patch > b_patch )); then echo 1; return; fi
    if (( a_patch < b_patch )); then echo -1; return; fi
    echo 0
}

if [ "$DRY_RUN" = false ]; then
    echo -e "Configuring git user"
    git config set color.ui always
    git config set user.name "github-actions[bot]"
    git config set user.email "github-actions[bot]@users.noreply.github.com"
fi

# Resolve auth token: GH_TOKEN env var or gh CLI
GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"

echo -e "${CYAN}Running pstack sync...${RESET}"
./pstack/sync-pstack.sh

echo -e "${BLUE}Diffing changes...${RESET}"
git --no-pager diff --color=always

if git diff --quiet && [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}Nothing changed${RESET}"
    exit 0
fi

# Version each power that has changes, based on the upstream commit date.
echo -e "${BLUE}Versioning...${RESET}"
for plugin in */plugin.json; do
    dir="${plugin%/plugin.json}"
    if [ "$DRY_RUN" = false ] && git diff --quiet -- "$dir"; then
        continue
    fi

    upstream="${UPSTREAM[$dir]:-}"
    if [ -z "$upstream" ]; then
        echo -e "${YELLOW}  ${dir}: no upstream mapping, skipping version${RESET}"
        continue
    fi

    repo="${upstream%%:*}"
    path="${upstream#*:}"

    echo -e "  ${dir}: querying upstream ${repo} path ${path}..."

    # Get the latest commit for this path from the upstream repo
    curl_opts=(-fsSL -H "Accept: application/vnd.github+json")
    if [ -n "$GH_TOKEN" ]; then
        curl_opts+=(-H "Authorization: token $GH_TOKEN")
    fi
    commit_json=$(curl "${curl_opts[@]}" \
        "https://api.github.com/repos/${repo}/commits?path=${path}&per_page=1")

    commit_date=$(echo "$commit_json" | jq -r '.[0].commit.committer.date')
    commit_sha=$(echo "$commit_json" | jq -r '.[0].sha')

    if [ -z "$commit_date" ] || [ "$commit_date" = "null" ]; then
        echo -e "${RED}  ${dir}: failed to get upstream commit date${RESET}"
        continue
    fi

    next=$(derive_version "$commit_date")
    current=$(jq -r '.version // "0.0.0"' "$plugin")
    short_sha="${commit_sha:0:7}"

    echo -e "  ${CYAN}${dir}:${RESET} ${RED}${current}${RESET} ${CYAN}->${RESET} ${GREEN}${next} (${short_sha})${RESET}"

    # Check for version regression (current > next means upstream went backwards)
    if [ "$(semver_compare "$current" "$next")" = "1" ]; then
        echo "::warning::Version regression in ${dir}: current=${current} > next=${next}. This may indicate a force-push upstream. Investigate manually."
        echo -e "${RED}  Reverting changes to ${dir}...${RESET}"
        git checkout -- "$dir"
        continue
    fi

    jq --arg v "$next" '.version = $v' "$plugin" > "$plugin.tmp"
    if [ "$DRY_RUN" = false ]; then
        mv "$plugin.tmp" "$plugin"
        # Also bump version in POWER.md frontmatter if present
        power_md="${dir}/POWER.md"
        if [ -f "$power_md" ]; then
            sed -i "s/^version: .*/version: \"${next}\"/" "$power_md"
        fi
        git add -A -- "$dir"
        git commit -m "Bump ${dir} to ${next} (${short_sha})"
    else
        rm "$plugin.tmp"
    fi
done

# If all powers regressed, nothing to commit
if git diff --quiet origin/"${GITHUB_REF_NAME:-main}"..HEAD 2>/dev/null && git diff --quiet; then
    echo -e "${YELLOW}Nothing to commit${RESET}"
    exit 0
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run complete. No changes committed.${RESET}"
    git checkout -- .
    git clean -fd -- */skills/ >/dev/null 2>&1 || true
    exit 0
fi

echo -e "${BLUE}Pushing changes to origin/${GITHUB_REF_NAME}...${RESET}"
git push origin "${GITHUB_REF_NAME}"
