# dotnet-msbuild

Packages the [dotnet/skills](https://github.com/dotnet/skills) `dotnet-msbuild` plugin as a Kiro [power](https://kiro.dev/docs/powers), so its MSBuild skills, agents, and the binlog MCP server install in one step and activate on demand.

`dotnet-msbuild` is the .NET team's set of MSBuild and build skills: binary-log failure diagnosis, build-performance optimization, project-file code review, and modernization. It bundles the [`Microsoft.AITools.BinlogMcp`](https://www.nuget.org/packages/Microsoft.AITools.BinlogMcp) MCP server, which lets the skills query a `.binlog` through structured tools instead of parsing text logs. See the upstream [dotnet-msbuild plugin](https://github.com/dotnet/skills/tree/main/plugins/dotnet-msbuild) for the source.

## Prerequisite: ndx

The binlog MCP server is a .NET tool run from NuGet. Upstream launches it with `dotnet dnx`; this power uses [`ndx`](https://github.com/devlooped/ndx) (native `dotnet execute`) instead — a drop-in, Native-AOT-compiled runner with the same `PACKAGE[@VERSION]` identity and restore flags. Cached startup drops from roughly half a second to tens of milliseconds, which matters for a server the agent spawns repeatedly.

`ndx` is therefore a required, implicit dependency of this power (as `dnx`/the .NET SDK is for the upstream). Install it once:

```bash
# macOS / Linux
curl -fsSL https://github.com/devlooped/ndx/releases/latest/download/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://github.com/devlooped/ndx/releases/latest/download/install.ps1 | iex
```

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/dotnet-msbuild
```

To install a local checkout instead, choose **Import power from a folder** and select the `dotnet-msbuild` directory. Install [`ndx`](#prerequisite-ndx) first, and remove any [manual `binlog` entry](#the-mcp-server) after installing.

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask about a build failure and `binlog-failure-analysis` (plus the `binlog` MCP tools) come into play; ask why a build is slow and `build-perf` / `build-perf-baseline` engage; ask to review a `.csproj` and `msbuild-code-review` runs. Generate a binlog with `dotnet build /bl:{}` (`binlog-generation` covers the conventions) and the analysis skills consume it through the MCP server.

## The MCP server

`mcp.json` declares the `binlog` server:

```json
{
  "command": "ndx",
  "args": ["Microsoft.AITools.BinlogMcp", "--prerelease"]
}
```

- **`ndx` is invoked directly**, not via `dotnet dnx`.
- **`--prerelease`** matches upstream (the plugin passes `--prerelease` too).
- **No `--source`.** `Microsoft.AITools.BinlogMcp` is published on nuget.org, so the default feed resolves it; upstream also [dropped the dnceng source](https://github.com/dotnet/skills/pull/984) once the package was public. Add a `--source` back if you need a preview that only exists on the dnceng dotnet-public feed.

With no version pinned, `ndx` runs the server [evergreen](https://github.com/devlooped/ndx#evergreen): it starts the latest matching package and hot-restarts when a newer one lands on the feed. For a local diagnostic server that auto-upgrade is a feature; pin a version in `mcp.json` to freeze it.

Kiro installs a power's MCP server internally, namespaced (e.g. `power-dotnet-msbuild-binlog`), and activates it with the power — it is not written to your `~/.kiro/settings/mcp.json`.

> **If you already run the binlog server manually:** remove your hand-added `binlog` entry from `~/.kiro/settings/mcp.json` after installing this power, so the server has a single source of truth. Otherwise you will have two binlog servers (your manual one and the power's).

## Agents become skills

Upstream ships three agents (`build-perf`, `msbuild-code-review`, `msbuild`) in the plugin's `agents/` array. Kiro does not consume the Agent Plugins `agents` field — it loads skills, MCP servers, and steering, but silently ignores `agents`. So the sync converts each agent into a skill under `skills/`, which is how Kiro users reach the same content Claude Code / Codex users get from the agents natively.

- `build-perf` and `msbuild-code-review` keep their names.
- `msbuild` is renamed to **`msbuild-expert`** — a bare `msbuild` is too broad for an auto-activating skill sitting alongside twenty others.

The conversion strips agent-only frontmatter (`user-invokable`) and preserves the rest. These activate on description match — Kiro loads a skill when your request matches its `description` — so the perf skill engages on a slow build and the review skill on a project-file audit, the same intents the agents served.

The `msbuild-expert` skill references GitHub Copilot / Codex tools (`#tool:agent/runSubagent`, `#tool:web/fetch`) that do not exist on Kiro. Rather than rewrite the prose, the sync appends a short "Kiro tool interpretation" note to each converted skill mapping those references to their Kiro equivalents (`invoke_sub_agent`, `web_fetch`) at read time.

## What differs from upstream

The upstream `plugin.json` does not load as a Kiro power as-is. It is missing the required `$schema` field and carries `skills`, `agents`, and `mcpServers` as top-level keys that the Agent Plugins 1.0.0 schema does not define (`additionalProperties: false`), so Kiro strips them and the power loads with no components. Reported upstream as [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087).

This mirror's manifest fixes that: `plugin.json` is identity-only with `$schema`, skills are discovered from `skills/`, and the MCP server lives in a sibling `mcp.json` — the layout the spec requires. The upstream `.claude-plugin/`, `.codex-plugin/`, and `version.json` (other-host discovery and NBGV versioning) are not mirrored.

The power's version is also **decoupled from upstream's**. Upstream bumps all its plugins together on a weekly task (`0.1.7`, `0.1.8`, `0.1.9`, …); this power instead derives its version from the UTC commit date of the upstream `plugins/dotnet-msbuild` path it mirrors, formatted `yyMM.dHH.mss`, via the shared `.github/scripts/lib/version.sh`. The `sync-dotnet-msbuild.sh` maintainer tool grabs the tree on a schedule and stamps its own date-based version, so the number reflects *when the mirrored content changed*, not upstream's semver.

## Structure

```
dotnet-msbuild/
├── plugin.json                 ← power manifest (identity only, $schema)
├── mcp.json                    ← binlog MCP server (ndx)
├── skills/                     ← mirror of upstream + converted agents
│   ├── binlog-failure-analysis/
│   │   └── SKILL.md
│   ├── msbuild-antipatterns/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── msbuild-expert/         ← converted from agents/msbuild.agent.md
│   │   └── SKILL.md
│   └── ...
└── sync-dotnet-msbuild.sh      ← maintainer tool
```

## Links

- [dotnet/skills](https://github.com/dotnet/skills)
- [dotnet-msbuild source](https://github.com/dotnet/skills/tree/main/plugins/dotnet-msbuild)
- [ndx](https://github.com/devlooped/ndx)
- [Microsoft.AITools.BinlogMcp](https://www.nuget.org/packages/Microsoft.AITools.BinlogMcp)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Manifest-compliance issue #1087](https://github.com/dotnet/skills/issues/1087)
