#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Syncs pstack skills from GitHub to Kiro global steering directory.

.DESCRIPTION
    Downloads the pstack plugin repo as a zip archive, extracts SKILL.md files,
    injects Kiro front-matter (inclusion mode), and writes them to
    ~/.kiro/steering/pstack/. Support files (playbooks, references) are renamed
    to .txt so Kiro's recursive .md scanner does not auto-load them as steering
    entries. Scripts directories are skipped entirely.

    On first run, creates a default config at sync-pstack.config.json next to
    this script. Edit that file to control which skills are always-on, auto, or
    manual (the default).

.PARAMETER Init
    Recreate the config file with defaults (overwrites existing config).

.PARAMETER DryRun
    Show what would be synced without writing anything.

.EXAMPLE
    sync-pstack.ps1
    sync-pstack.ps1 -Init
    sync-pstack.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Init,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'sync-pstack.config.json'
$SteeringRoot = Join-Path $HOME '.kiro' 'steering' 'pstack'

# --- Default config ---
$DefaultConfig = @{
    repository    = 'cursor/plugins'
    branch        = 'main'
    basePath      = 'pstack/skills'
    includeAlways = @(
        'principle-laziness-protocol'
        'unslop'
    )
    includeAuto   = @()
}

# --- Ensure config exists ---
if ($Init -or -not (Test-Path $ConfigPath)) {
    $action = if (Test-Path $ConfigPath) { 'Recreated' } else { 'Created' }
    $DefaultConfig | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding utf8NoBOM
    Write-Host "  $action config: $ConfigPath" -ForegroundColor Green
    if ($Init) {
        Write-Host "  Edit includeAlways/includeAuto to control skill inclusion modes." -ForegroundColor Gray
        exit 0
    }
}

# --- Load config ---
$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$Repository = $Config.repository
$Branch = $Config.branch
$BasePath = $Config.basePath
$IncludeAlways = @($Config.includeAlways)
$IncludeAuto = @($Config.includeAuto)

Write-Host "sync-pstack: $Repository@$Branch ($BasePath)" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  [DRY RUN]" -ForegroundColor Yellow }

# --- Download and extract archive ---
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "sync-pstack-$PID"
$ZipPath = "$TempDir.zip"

Write-Host "  Downloading archive..." -ForegroundColor Gray
$archiveUrl = "https://github.com/$Repository/archive/refs/heads/$Branch.zip"
$prevProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri $archiveUrl -OutFile $ZipPath -UseBasicParsing
}
catch {
    $ProgressPreference = $prevProgress
    Write-Error "Failed to download archive: $($_.Exception.Message)"
    exit 1
}
$ProgressPreference = $prevProgress

Write-Host "  Extracting..." -ForegroundColor Gray
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
$prevProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
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

# --- Parse upstream front-matter ---
function Get-UpstreamDescription {
    param([string]$Content)

    $match = [regex]::Match($Content, '\A---\s*\r?\n(.*?)\r?\n---\s*\r?\n', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        $yaml = $match.Groups[1].Value
        $descMatch = [regex]::Match($yaml, '(?m)^description:\s*"?(.+?)"?\s*$')
        if ($descMatch.Success) {
            return $descMatch.Groups[1].Value
        }
    }
    return $null
}

# --- Front-matter injection ---
function Add-KiroFrontMatter {
    param(
        [string]$Content,
        [string]$SkillName,
        [string]$InclusionMode
    )

    # Extract description from upstream front-matter
    $description = Get-UpstreamDescription -Content $Content
    if (-not $description) {
        $description = "pstack skill: $SkillName"
    }

    # Strip existing Cursor front-matter
    $stripped = $Content
    $match = [regex]::Match($stripped, '\A---\s*\r?\n.*?\r?\n---\s*\r?\n', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        $stripped = $stripped.Substring($match.Length)
    }

    $fm = "---`ninclusion: $InclusionMode`nname: pstack-$SkillName`ndescription: `"$description`"`n---`n`n"
    return $fm + $stripped.TrimStart()
}

# --- File output ---
$stats = @{ created = 0; updated = 0; unchanged = 0; support = 0 }

function Write-OutputFile {
    param(
        [string]$LocalPath,
        [string]$Content
    )

    $relativePath = $LocalPath.Replace($SteeringRoot, '~/.kiro/steering/pstack').Replace('\', '/')

    if ($DryRun) {
        $action = if (Test-Path $LocalPath) { "update" } else { "create" }
        Write-Host "    [$action] $relativePath" -ForegroundColor DarkGray
        if ($action -eq 'create') { $stats.created++ } else { $stats.updated++ }
        return
    }

    $dir = Split-Path -Parent $LocalPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (Test-Path $LocalPath) {
        $existing = Get-Content $LocalPath -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $Content) {
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

    Set-Content -Path $LocalPath -Value $Content -NoNewline -Encoding utf8NoBOM
}

# --- Sync support subdirectory (playbooks, references) ---
function Sync-SupportDir {
    param(
        [string]$SourceDir,
        [string]$DestDir
    )

    foreach ($item in Get-ChildItem $SourceDir) {
        if ($item.PSIsContainer) {
            Sync-SupportDir -SourceDir $item.FullName -DestDir (Join-Path $DestDir $item.Name)
        }
        else {
            $content = Get-Content $item.FullName -Raw
            $destName = if ($item.Extension -eq '.md') { $item.Name + '.txt' } else { $item.Name }
            $destPath = Join-Path $DestDir $destName
            Write-OutputFile -LocalPath $destPath -Content $content
            $stats.support++
        }
    }
}

# --- Sync a single skill folder ---
function Sync-SkillFolder {
    param(
        [string]$SourceDir,
        [string]$SkillName,
        [string]$Category
    )

    $localBase = if ($Category -eq 'principles') {
        $shortName = $SkillName -replace '^principle-', ''
        Join-Path $SteeringRoot 'principles' $shortName
    } else {
        Join-Path $SteeringRoot 'skills' $SkillName
    }

    $inclusionMode = if ($IncludeAlways -contains $SkillName) {
        'always'
    } elseif ($IncludeAuto -contains $SkillName) {
        'auto'
    } else {
        'manual'
    }

    foreach ($item in Get-ChildItem $SourceDir) {
        if ($item.PSIsContainer) {
            Sync-SupportDir -SourceDir $item.FullName -DestDir (Join-Path $localBase $item.Name)
        }
        elseif ($item.Name -eq 'SKILL.md') {
            $content = Get-Content $item.FullName -Raw
            $displayName = if ($Category -eq 'principles') { $SkillName -replace '^principle-', '' } else { $SkillName }
            $transformed = Add-KiroFrontMatter -Content $content -SkillName $displayName -InclusionMode $inclusionMode
            $localPath = Join-Path $localBase 'SKILL.md'
            Write-OutputFile -LocalPath $localPath -Content $transformed
        }
    }
}

# --- Main sync ---
$skillFolders = Get-ChildItem $SourceRoot -Directory
$skills = $skillFolders | Where-Object { $_.Name -notlike 'principle-*' }
$principles = $skillFolders | Where-Object { $_.Name -like 'principle-*' }

Write-Host "  Found $($skillFolders.Count) skills ($($skills.Count) skills, $($principles.Count) principles)" -ForegroundColor Gray

Write-Host "  Syncing skills..." -ForegroundColor Gray
foreach ($s in $skills) {
    Sync-SkillFolder -SourceDir $s.FullName -SkillName $s.Name -Category 'skills'
}

Write-Host "  Syncing principles..." -ForegroundColor Gray
foreach ($p in $principles) {
    Sync-SkillFolder -SourceDir $p.FullName -SkillName $p.Name -Category 'principles'
}

# --- Cleanup temp ---
Remove-Item $TempDir -Recurse -Force

# --- Summary ---
Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host "    Created:   $($stats.created)" -ForegroundColor Green
Write-Host "    Updated:   $($stats.updated)" -ForegroundColor Yellow
Write-Host "    Unchanged: $($stats.unchanged)" -ForegroundColor Gray
Write-Host "    Support:   $($stats.support) (playbooks/references as .md.txt)" -ForegroundColor Gray
Write-Host "    Output:    $SteeringRoot" -ForegroundColor Cyan

if ($IncludeAlways.Count -gt 0) {
    Write-Host "    Always-on: $($IncludeAlways -join ', ')" -ForegroundColor Magenta
}
if ($IncludeAuto.Count -gt 0) {
    Write-Host "    Auto:      $($IncludeAuto -join ', ')" -ForegroundColor Blue
}
