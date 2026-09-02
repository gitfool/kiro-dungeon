#!/usr/bin/env bash

# version.sh — Shared version-derivation helpers for power sync scripts and the
# bump workflow. Source this file; it defines functions and sets no state.
#
# The scheme: a power's version is derived from the UTC commit date of the
# upstream path it mirrors, formatted yyMM.dHH.mss (leading zeros stripped from
# minor and patch). The same derivation seeds a new power (sync --ref <tag>) and
# bumps an existing one (bump workflow, ref = default branch), so there is one
# source of truth.
#
# Requires: curl, jq, date (GNU), git. A GH_TOKEN in the environment (or via
# `gh auth token`) raises the GitHub API rate limit but is not required.

# --- Derive a version from a UTC ISO 8601 commit date ---
# Format: yyMM.dHH.mss (leading zeros stripped from minor/patch, min one digit)
derive_version() {
    local iso_date="$1"

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

    # 10# forces base-10 so a leading zero is not read as octal
    minor=$((10#$minor))
    patch=$((10#$patch))

    echo "${major}.${minor}.${patch}"
}

# --- Query the latest upstream commit for a path at a ref ---
# Echoes two lines: the committer date (ISO 8601) and the full SHA.
# Args: <owner/repo> <path> [<ref>]   (ref defaults to the repo's default branch)
# Returns non-zero and echoes nothing usable if the query fails.
latest_commit_for_path() {
    local repo="$1"
    local path="$2"
    local ref="${3:-}"

    local token
    token="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"

    local curl_opts=(-fsSL -H "Accept: application/vnd.github+json" -w '\n%{http_code}')
    if [ -n "$token" ]; then
        curl_opts+=(-H "Authorization: token $token")
    fi

    local url="https://api.github.com/repos/${repo}/commits?path=${path}&per_page=1"
    if [ -n "$ref" ]; then
        url="${url}&sha=${ref}"
    fi

    # One initial attempt plus up to 3 retries on transient failures, with
    # exponential backoff between attempts. No sleep after the last attempt.
    local retries=3 delay=2
    local response code json date sha attempt reason
    for ((attempt = 0; attempt <= retries; attempt++)); do
        response=$(curl "${curl_opts[@]}" "$url" 2>/dev/null) || true
        code="${response##*$'\n'}"
        json="${response%$'\n'*}"
        if [ "$code" = "200" ]; then
            date=$(echo "$json" | jq -r '.[0].commit.committer.date')
            sha=$(echo "$json" | jq -r '.[0].sha')
            if [ -n "$date" ] && [ "$date" != "null" ]; then
                echo "$date"
                echo "$sha"
                return 0
            fi
            reason="unexpected response"
        else
            reason="request failed (HTTP ${code:-000})"
        fi
        echo "latest_commit_for_path: ${repo} ${path}${ref:+@$ref}: ${reason} (attempt $((attempt + 1))/$((retries + 1)))" >&2
        if [ "$attempt" -lt "$retries" ]; then
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    return 1
}

# --- Compare semver (major.minor.patch only, ignoring metadata) ---
# Prints: -1 if a < b, 0 if a == b, 1 if a > b
semver_compare() {
    local a="$1" b="$2"
    # Strip build metadata and prerelease
    a="${a%%+*}"
    b="${b%%+*}"
    a="${a%%-*}"
    b="${b%%-*}"

    local a_major="${a%%.*}" b_major="${b%%.*}"
    local a_rest="${a#*.}" b_rest="${b#*.}"
    local a_minor="${a_rest%%.*}" b_minor="${b_rest%%.*}"
    local a_patch="${a_rest#*.}" b_patch="${b_rest#*.}"

    if ((a_major > b_major)); then
        echo 1
        return
    fi
    if ((a_major < b_major)); then
        echo -1
        return
    fi
    if ((a_minor > b_minor)); then
        echo 1
        return
    fi
    if ((a_minor < b_minor)); then
        echo -1
        return
    fi
    if ((a_patch > b_patch)); then
        echo 1
        return
    fi
    if ((a_patch < b_patch)); then
        echo -1
        return
    fi
    echo 0
}

# --- Regression guard ---
# Returns 0 (ok to apply) when next >= current, 1 (regression) when next < current.
# A regression means upstream appears to have gone backwards (e.g. a force-push):
# the caller should refuse to write the version and investigate.
is_version_regression() {
    local current="$1" next="$2"
    [ "$(semver_compare "$current" "$next")" = "1" ]
}

# --- Write a version into a plugin.json and optional POWER.md ---
# Args: <version> <plugin.json path> [<POWER.md path>]
# Uses jq for the JSON and sed for the POWER.md frontmatter, matching the
# formats both files already use.
write_power_version() {
    local version="$1"
    local plugin_json="$2"
    local power_md="${3:-}"

    jq --arg v "$version" '.version = $v' "$plugin_json" >"$plugin_json.tmp"
    mv "$plugin_json.tmp" "$plugin_json"

    if [ -n "$power_md" ] && [ -f "$power_md" ]; then
        sed -i "s/^version: .*/version: \"${version}\"/" "$power_md"
    fi
}
