# dotnet-diag

Packages the [dotnet/skills](https://github.com/dotnet/skills) `dotnet-diag` plugin as a Kiro [power](https://kiro.dev/docs/powers), so its .NET diagnostics skills install in one step and activate on demand.

`dotnet-diag` is the .NET team's set of performance-investigation, debugging, and incident-analysis skills: scanning code for performance anti-patterns, microbenchmarking, collecting traces and crash dumps, CLR activation debugging, and Android/Apple crash symbolication. See the upstream [dotnet-diag plugin](https://github.com/dotnet/skills/tree/main/plugins/dotnet-diag) for the source.

This is a **skills-only power** — no bundled MCP server. Unlike the sibling [`dotnet-msbuild`](../dotnet-msbuild) power, upstream `dotnet-diag` declares no `mcpServers`, so there is nothing to install alongside the skills and no `mcp.json`. It does ship one agent, which this power converts to a skill (see [below](#agent-becomes-a-skill)).

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/dotnet-diag
```

To install a local checkout instead, choose **Import power from a folder** and select the `dotnet-diag` directory.

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask why a hot path is slow or how to cut allocations and `optimizing-dotnet-performance` / `analyzing-dotnet-performance` engage; ask to write a benchmark and `microbenchmarking` runs; ask to capture a trace or a crash dump from a production process and `dotnet-trace-collect` / `dump-collect` come into play; ask to symbolicate an Android tombstone or Apple crash report and the matching symbolication skill takes over. Skills that carry their own `references/` bring the detail along with them.

## Agent becomes a skill

Upstream ships one agent (`optimizing-dotnet-performance`) in the plugin's `agents/` array. Kiro does not consume the Agent Plugins `agents` field — it loads skills, MCP servers, and steering, but silently ignores `agents`. So the sync converts that agent into a skill under `skills/`, which is how Kiro users reach the same content Claude Code / Codex users get from the agent natively.

The name is already descriptive, so — unlike the sibling `dotnet-msbuild` power's bare `msbuild` agent, which is renamed to `msbuild-expert` — it keeps its name. The conversion strips agent-only frontmatter (`user-invokable`, `tools`) and preserves the rest. It activates on description match — Kiro loads a skill when your request matches its `description` — the same intent the agent served: reviewing .NET code for performance, optimizing hot paths, reducing allocations, and tuning async/concurrency.

The agent references editor/host tools (`task`, `web_fetch`, `web_search`, `skill`) that do not exist by those names on Kiro. Rather than rewrite the prose, the sync appends a short "Kiro tool interpretation" note to the converted skill mapping those references to their Kiro equivalents (`invoke_sub_agent`, `web_fetch`, `disclose_context`) at read time. Its two-pass workflow loads the `analyzing-dotnet-performance` skill in Pass 2; that skill is a sibling in this same power.

## What differs from upstream

The upstream `plugin.json` does not load as a Kiro power as-is. It is missing the required `$schema` field and carries `skills` and `agents` as top-level keys that the Agent Plugins 1.0.0 schema does not define (`additionalProperties: false`), so Kiro strips them and the power loads with no components. Reported upstream as [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087).

This mirror's manifest fixes that: `plugin.json` is identity-only with `$schema`, and skills are discovered from `skills/` — the layout the spec requires. The upstream `.claude-plugin/`, `.codex-plugin/`, `training-logs/`, and `version.json` (other-host discovery, training data, and NBGV versioning) are not mirrored.

The power's version is also **decoupled from upstream's**. Upstream bumps all its plugins together on a weekly task (`0.1.1`, `0.1.2`, …); this power instead derives its version from the UTC commit date of the upstream `plugins/dotnet-diag` path it mirrors, formatted `yyMM.dHH.mss`, via the shared `.github/scripts/lib/version.sh`. The `sync-dotnet-diag.sh` maintainer tool grabs the tree on a schedule and stamps its own date-based version, so the number reflects *when the mirrored content changed*, not upstream's semver.

## Structure

```
dotnet-diag/
├── plugin.json                 ← power manifest (identity only, $schema)
├── skills/                     ← mirror of upstream + converted agent
│   ├── analyzing-dotnet-performance/
│   │   └── SKILL.md
│   ├── optimizing-dotnet-performance/   ← converted from agents/optimizing-dotnet-performance.agent.md
│   │   └── SKILL.md
│   ├── microbenchmarking/
│   │   └── SKILL.md
│   ├── dotnet-trace-collect/
│   │   └── SKILL.md
│   ├── dump-collect/
│   │   └── SKILL.md
│   └── ...
└── sync-dotnet-diag.sh         ← maintainer tool
```

## Links

- [dotnet/skills](https://github.com/dotnet/skills)
- [dotnet-diag source](https://github.com/dotnet/skills/tree/main/plugins/dotnet-diag)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Manifest-compliance issue #1087](https://github.com/dotnet/skills/issues/1087)
