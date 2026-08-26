#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Mirrors pstack skills and selected agents from GitHub into this power's skills/ directory.

.DESCRIPTION
    Downloads the pstack plugin from the cursor/plugins repo and mirrors its
    skills into ./skills/, so this directory can be installed as a Kiro power.

    Additionally, selected agent definitions from the upstream agents/ directory
    are converted to skills. The $AgentsToConvert list controls which agents are
    included; others (like poteto-agent, which is a routing stub) are skipped.
    Conversion strips agent-specific frontmatter (is_background), normalizes the
    name, and adds disable-model-invocation: true so the skill only fires on
    explicit request.

    Content is copied verbatim apart from one fix. The Agent Skills spec
    requires each skill's name field to match its directory name exactly, and
    upstream poteto-mode declares "Poteto Mode". Kiro rejects skills whose name
    does not match, silently, so the name is normalized during the sync. See
    https://github.com/cursor/plugins/issues/237.

    Support directories (playbooks, references, scripts) are mirrored as-is.
    Only immediate subdirectories of skills/ are treated as skills, so nested
    markdown is never loaded and needs no special handling.

    This is a maintainer tool, not an installer. Run it to refresh skills/ when
    upstream changes, then commit the result.

.PARAMETER DryRun
    Show what would change without writing anything.

.EXAMPLE
    sync-pstack.ps1
    sync-pstack.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Upstream source ---
$Repository = 'cursor/plugins'
$Branch = 'main'
$BasePath = 'pstack/skills'
$AgentsPath = 'pstack/agents'

# Agents to convert to skills. Others (e.g. poteto-agent) are skipped because
# they're routing stubs with no standalone value.
$AgentsToConvert = @('comment-sicko')

# --- Paths ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SkillsRoot = Join-Path $ScriptDir 'skills'

Write-Host "sync-pstack: $Repository@$Branch ($BasePath)" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  [DRY RUN]" -ForegroundColor Yellow }

# --- Download and extract archive ---
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sync-pstack-$PID"
$ZipPath = "$TempDir.zip"

Write-Host "  Downloading archive..." -ForegroundColor Gray
$archiveUrl = "https://github.com/$Repository/archive/refs/heads/$Branch.zip"
$ghToken = if ($env:GH_TOKEN) { $env:GH_TOKEN } else { gh auth token 2>$null }
$headers = @{}
if ($ghToken) { $headers['Authorization'] = "token $ghToken" }
$prevProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Headers $headers -Uri $archiveUrl -OutFile $ZipPath -UseBasicParsing
}
catch {
    $ProgressPreference = $prevProgress
    Write-Error "Failed to download archive: $($_.Exception.Message)"
    exit 1
}

Write-Host "  Extracting..." -ForegroundColor Gray
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force
$ProgressPreference = $prevProgress
Remove-Item $ZipPath -Force

# Find extracted root (GitHub archives have a top-level folder like plugins-main/)
$extractedRoot = Get-ChildItem $TempDir -Directory | Select-Object -First 1
$SourceRoot = Join-Path $extractedRoot.FullName $BasePath

if (-not (Test-Path $SourceRoot)) {
    Write-Error "Skills path not found in archive: $BasePath"
    Remove-Item $TempDir -Recurse -Force
    exit 1
}

# --- Normalize the skill name to match its directory ---
function Set-SkillName {
    param(
        [string]$Content,
        [string]$SkillName
    )

    $match = [regex]::Match($Content, '\A(---\s*\r?\n)(.*?)(\r?\n---\s*\r?\n)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { return $Content }

    $frontMatter = $match.Groups[2].Value
    $fixed = [regex]::Replace($frontMatter, '(?m)^name:.*$', "name: $SkillName")
    if ($fixed -eq $frontMatter) { return $Content }

    return $match.Groups[1].Value + $fixed + $match.Groups[3].Value + $Content.Substring($match.Length)
}

# --- File output ---
$stats = @{ created = 0; updated = 0; unchanged = 0; normalized = 0 }

# Signature of a file's bytes with CR removed. Comparing this way avoids
# reporting every file as changed on a Windows working tree, where text=auto
# yields CRLF while upstream archives are always LF.
function Get-Signature {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return [Convert]::ToBase64String([byte[]]@($bytes | Where-Object { $_ -ne 13 }))
}

function Copy-OutputFile {
    param(
        [string]$SourcePath,
        [string]$DestPath
    )

    $relativePath = $DestPath.Replace($ScriptDir, '.').Replace('\', '/')

    if (Test-Path $DestPath) {
        if ((Get-Signature $SourcePath) -eq (Get-Signature $DestPath)) {
            Write-Host "    [unchanged] $relativePath" -ForegroundColor DarkGray
            $stats.unchanged++
            return
        }
        Write-Host "    [updated] $relativePath" -ForegroundColor Yellow
        $stats.updated++
    }
    else {
        Write-Host "    [created] $relativePath" -ForegroundColor Green
        $stats.created++
    }

    if ($DryRun) { return }

    $dir = Split-Path -Parent $DestPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -Path $SourcePath -Destination $DestPath -Force
}

# --- Mirror a directory tree verbatim ---
function Sync-SupportDir {
    param(
        [string]$SourceDir,
        [string]$DestDir
    )

    foreach ($item in Get-ChildItem $SourceDir | Sort-Object Name) {
        if ($item.PSIsContainer) {
            Sync-SupportDir -SourceDir $item.FullName -DestDir (Join-Path $DestDir $item.Name)
        }
        else {
            Copy-OutputFile -SourcePath $item.FullName -DestPath (Join-Path $DestDir $item.Name)
        }
    }
}

# --- Mirror one skill folder ---
function Sync-SkillFolder {
    param(
        [string]$SourceDir,
        [string]$SkillName
    )

    $localBase = Join-Path $SkillsRoot $SkillName

    foreach ($item in Get-ChildItem $SourceDir | Sort-Object Name) {
        if ($item.PSIsContainer) {
            Sync-SupportDir -SourceDir $item.FullName -DestDir (Join-Path $localBase $item.Name)
        }
        elseif ($item.Name -eq 'SKILL.md') {
            # Transform to a temp file, then take the same compare and copy path
            # as every other file, so output stays byte-exact.
            $content = Get-Content $item.FullName -Raw
            $fixed = Set-SkillName -Content $content -SkillName $SkillName
            if ($fixed -ne $content) {
                Write-Host "    [name] normalized to '$SkillName'" -ForegroundColor Magenta
                $stats.normalized++
            }
            $staged = Join-Path $TempDir 'SKILL.md.staged'
            Set-Content -Path $staged -Value $fixed -NoNewline -Encoding utf8NoBOM
            Copy-OutputFile -SourcePath $staged -DestPath (Join-Path $localBase 'SKILL.md')
            Remove-Item $staged -Force
        }
        else {
            Copy-OutputFile -SourcePath $item.FullName -DestPath (Join-Path $localBase $item.Name)
        }
    }
}

# --- Convert an agent .md to a skill SKILL.md ---
# Strips agent-specific frontmatter fields (is_background) and normalizes the
# name to match the target skill directory. Adds disable-model-invocation: true
# so the skill only activates on explicit request.
function Convert-AgentToSkill {
    param(
        [string]$Content,
        [string]$SkillName
    )

    $match = [regex]::Match($Content, '\A(---\s*\r?\n)(.*?)(\r?\n---\s*\r?\n)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { return $Content }

    $frontMatter = $match.Groups[2].Value
    $body = $Content.Substring($match.Length)

    # Normalize name
    $frontMatter = [regex]::Replace($frontMatter, '(?m)^name:.*$', "name: $SkillName")

    # Strip agent-specific fields
    $frontMatter = [regex]::Replace($frontMatter, '(?m)^is_background:.*\r?\n?', '')

    # Add disable-model-invocation if not present
    if ($frontMatter -notmatch 'disable-model-invocation') {
        $frontMatter = $frontMatter.TrimEnd() + "`ndisable-model-invocation: true"
    }

    return $match.Groups[1].Value + $frontMatter + $match.Groups[3].Value + $body
}

# --- Main sync ---
$upstream = Get-ChildItem $SourceRoot -Directory | Sort-Object Name
$skills = $upstream | Where-Object { $_.Name -notlike 'principle-*' }
$principles = $upstream | Where-Object { $_.Name -like 'principle-*' }

Write-Host "  Found $($upstream.Count) skills ($($skills.Count) skills, $($principles.Count) principles)" -ForegroundColor Gray

Write-Host "  Syncing skills..." -ForegroundColor Gray
foreach ($s in $skills) {
    Sync-SkillFolder -SourceDir $s.FullName -SkillName $s.Name
}

Write-Host "  Syncing principles..." -ForegroundColor Gray
foreach ($p in $principles) {
    Sync-SkillFolder -SourceDir $p.FullName -SkillName $p.Name
}

# --- Sync agents (converted to skills) ---
$AgentsRoot = Join-Path $extractedRoot.FullName $AgentsPath
$agentStats = @{ converted = 0; skipped = 0 }

if (Test-Path $AgentsRoot) {
    Write-Host "  Syncing agents as skills..." -ForegroundColor Gray
    $agentFiles = Get-ChildItem $AgentsRoot -Filter '*.md' | Sort-Object Name

    foreach ($af in $agentFiles) {
        $agentName = $af.BaseName  # filename without .md
        if ($AgentsToConvert -notcontains $agentName) {
            Write-Host "    [skipped] agents/$($af.Name) (not in convert list)" -ForegroundColor DarkGray
            $agentStats.skipped++
            continue
        }

        Write-Host "    [convert] agents/$($af.Name) -> skills/$agentName/SKILL.md" -ForegroundColor Cyan
        $agentStats.converted++

        $content = Get-Content $af.FullName -Raw
        $skillContent = Convert-AgentToSkill -Content $content -SkillName $agentName

        $staged = Join-Path $TempDir 'SKILL.md.agent-staged'
        Set-Content -Path $staged -Value $skillContent -NoNewline -Encoding utf8NoBOM
        Copy-OutputFile -SourcePath $staged -DestPath (Join-Path $SkillsRoot "$agentName\SKILL.md")
        Remove-Item $staged -Force
    }
}
else {
    Write-Host "  No agents/ directory found upstream, skipping." -ForegroundColor DarkGray
}

# --- Orphan detection ---
$orphans = @()
if (Test-Path $SkillsRoot) {
    $upstreamNames = @($upstream | Select-Object -ExpandProperty Name)
    # Agent-converted skills are not orphans
    $upstreamNames += $AgentsToConvert
    $orphans = @(Get-ChildItem $SkillsRoot -Directory | Where-Object { $upstreamNames -notcontains $_.Name })
}

# --- Cleanup temp ---
Remove-Item $TempDir -Recurse -Force

# --- Summary ---
Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host "    Created:    $($stats.created)" -ForegroundColor Green
Write-Host "    Updated:    $($stats.updated)" -ForegroundColor Yellow
Write-Host "    Unchanged:  $($stats.unchanged)" -ForegroundColor Gray
Write-Host "    Normalized: $($stats.normalized) skill name(s)" -ForegroundColor Magenta
Write-Host "    Agents:     $($agentStats.converted) converted, $($agentStats.skipped) skipped" -ForegroundColor Cyan
Write-Host "    Output:     $SkillsRoot" -ForegroundColor Cyan

if ($orphans.Count -gt 0) {
    Write-Host ""
    Write-Host "  $($orphans.Count) local skill(s) no longer exist upstream:" -ForegroundColor Yellow
    foreach ($o in $orphans) { Write-Host "    $($o.Name)" -ForegroundColor Yellow }
    Write-Host "  Remove with: git rm -r $(($orphans | ForEach-Object { "skills/$($_.Name)" }) -join ' ')" -ForegroundColor Gray
}
