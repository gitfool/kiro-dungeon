# dotnet-upgrade

Packages the [dotnet/skills](https://github.com/dotnet/skills) `dotnet-upgrade` plugin as a Kiro [power](https://kiro.dev/docs/powers), so its .NET migration skills install in one step and activate on demand.

`dotnet-upgrade` is the .NET team's set of upgrade and migration skills: moving projects across framework versions (.NET 8→9→10→11), adopting nullable reference types, checking Native AOT compatibility, and removing `Thread.Abort`. See the upstream [dotnet-upgrade plugin](https://github.com/dotnet/skills/tree/main/plugins/dotnet-upgrade) for the source.

This is a **skills-only power** — no bundled MCP server. Unlike the sibling [`dotnet-msbuild`](../dotnet-msbuild) power, upstream `dotnet-upgrade` declares only skills (no `agents`, no `mcpServers`), so there is nothing to convert and no `mcp.json` to install. That is a normal, valid power shape (`pstack` and `power-builder` are skills-only too).

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/dotnet-upgrade
```

To install a local checkout instead, choose **Import power from a folder** and select the `dotnet-upgrade` directory.

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask to upgrade a project from .NET 9 to .NET 10 and `migrate-dotnet9-to-dotnet10` engages; ask about enabling nullable reference types and `migrate-nullable-references` runs; ask whether code is Native AOT compatible and `dotnet-aot-compat` comes into play. Each migration skill carries its own `references/` with the framework-specific detail, which rides along with the skill.

## What differs from upstream

The upstream `plugin.json` does not load as a Kiro power as-is. It is missing the required `$schema` field and carries `skills` as a top-level key that the Agent Plugins 1.0.0 schema does not define (`additionalProperties: false`), so Kiro strips it and the power loads with no components. Reported upstream as [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087).

This mirror's manifest fixes that: `plugin.json` is identity-only with `$schema`, and skills are discovered from `skills/` — the layout the spec requires. The upstream `.claude-plugin/`, `.codex-plugin/`, and `version.json` (other-host discovery and NBGV versioning) are not mirrored.

The power's version is also **decoupled from upstream's**. Upstream bumps all its plugins together on a weekly task (`0.1.0`, `0.1.1`, …); this power instead derives its version from the UTC commit date of the upstream `plugins/dotnet-upgrade` path it mirrors, formatted `yyMM.dHH.mss`, via the shared `.github/scripts/lib/version.sh`. The `sync-dotnet-upgrade.sh` maintainer tool grabs the tree on a schedule and stamps its own date-based version, so the number reflects *when the mirrored content changed*, not upstream's semver.

## Structure

```
dotnet-upgrade/
├── plugin.json                 ← power manifest (identity only, $schema)
├── skills/                     ← mirror of upstream skills
│   ├── dotnet-aot-compat/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── migrate-dotnet9-to-dotnet10/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── migrate-nullable-references/
│   │   ├── SKILL.md
│   │   └── references/
│   └── ...
└── sync-dotnet-upgrade.sh      ← maintainer tool
```

## Links

- [dotnet/skills](https://github.com/dotnet/skills)
- [dotnet-upgrade source](https://github.com/dotnet/skills/tree/main/plugins/dotnet-upgrade)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Manifest-compliance issue #1087](https://github.com/dotnet/skills/issues/1087)
