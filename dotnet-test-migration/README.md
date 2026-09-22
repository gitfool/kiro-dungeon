# dotnet-test-migration

Packages the [dotnet/skills](https://github.com/dotnet/skills) `dotnet-test-migration` plugin as a Kiro [power](https://kiro.dev/docs/powers), so its .NET test-migration skills install in one step and activate on demand.

`dotnet-test-migration` is the .NET team's set of skills for migrating test frameworks and platforms: MSTest version upgrades (v1/v2 → v3 → v4), xUnit.net v2 → v3, cross-framework conversion (xUnit or NUnit → MSTest v4), and test-platform migration (VSTest → Microsoft.Testing.Platform). An orchestrator agent auto-detects the current framework/version/platform and routes to the right skill, sequencing multi-step upgrades. See the upstream [dotnet-test-migration plugin](https://github.com/dotnet/skills/tree/main/plugins/dotnet-test-migration) for the source.

This is a **skills-only power** — no bundled MCP server. Unlike the sibling [`dotnet-msbuild`](../dotnet-msbuild) power, upstream `dotnet-test-migration` declares no `mcpServers`, so there is nothing to install alongside the skills and no `mcp.json`. It does ship one agent, which this power converts to a skill (see [below](#agent-becomes-a-skill)).

This power is the framework/platform-migration companion to [`dotnet-test`](../dotnet-test) (running, generating, and analyzing tests), split out upstream. The two are designed to work together — see [Companion power](#companion-power-dotnet-test).

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/dotnet-test-migration
```

To install a local checkout instead, choose **Import power from a folder** and select the `dotnet-test-migration` directory.

## Prerequisites

- .NET SDK installed (`dotnet` on PATH).
- A project with an existing test framework (MSTest, xUnit, NUnit, or TUnit).

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask to upgrade MSTest and `migrate-mstest-v1v2-to-v3` / `migrate-mstest-v3-to-v4` engage; ask to move to xUnit v3 and `migrate-xunit-to-xunit-v3` runs; ask to port xUnit or NUnit tests to MSTest and `migrate-xunit-to-mstest` / `migrate-nunit-to-mstest` take over; ask to switch off the VSTest runner and `migrate-vstest-to-mtp` handles it. Ask broadly to "migrate my tests" and the converted `test-migration` skill runs detection first, then recommends and sequences the path (e.g. MSTest v1 → v3 → v4, committing between steps).

## Agent becomes a skill

Upstream ships one agent (`test-migration`) in the plugin's `agents/` array. Kiro does not consume the Agent Plugins `agents` field — it loads skills, MCP servers, and steering, but silently ignores `agents`. So the sync converts that agent into a skill under `skills/`, which is how Kiro users reach the same content Claude Code / Codex users get from the agent natively.

The `test-migration` agent is a user-facing entry point (`user-invokable: true`): it auto-detects the framework, version, and platform, then routes to the correct migration skill and orders multi-step upgrades. That is substantial standalone content, not an internal pipeline stub, so it is converted (contrast the sibling `dotnet-test` power, which skips eight internal `user-invocable: false` subagents). The name is already descriptive, so — unlike the sibling `dotnet-msbuild` power's bare `msbuild` agent, renamed to `msbuild-expert` — it keeps its name. The conversion strips agent-only frontmatter (`user-invokable`, `tools`, and the multi-line `handoffs:` block) and preserves the rest. It activates on description match — the same intent the agent served: detecting and routing test-framework/platform migrations.

`disable-model-invocation` is kept verbatim rather than stripped. Kiro does not honor it yet — it is a silent no-op ([kirodotdev/Kiro#10985](https://github.com/kirodotdev/Kiro/issues/10985)) — so the skill auto-activates on description match today, which is the intent for a user-facing entry point. Preserving the key is harmless now and keeps the upstream author's intent intact for the day Kiro implements it.

The agent references GitHub Copilot / Codex tools (`task` / `runSubagent`, `web_fetch`, `web_search`, `skill`) that do not exist on Kiro. Rather than rewrite the prose, the sync appends a short "Kiro tool interpretation" note mapping those references to their Kiro equivalents (`invoke_sub_agent`, `web_fetch`, `disclose_context`) at read time.

## Companion power: dotnet-test

The migration skills and the `test-migration` agent reference several skills and agents that live in the sibling [`dotnet-test`](../dotnet-test) power, not in this one:

- **Skills**: `platform-detection` (framework/platform detection), `writing-mstest-tests` (idiomatic MSTest polish), and `run-tests` (post-migration verification).
- **Agent handoffs**: `test-quality-auditor` and `testability-migration` (which `dotnet-test` converts to skills).

Install [`dotnet-test`](../dotnet-test) alongside this power to get the full workflow — detection → migrate → verify → audit. Without it, the migration skills still run, but the referenced detection and verification steps fall back to the agent's own inline knowledge rather than the dedicated sibling skills. The converted `test-migration` skill's "Kiro tool interpretation" note spells out which references are local versus cross-power.

## What differs from upstream

The upstream `plugin.json` does not load as a Kiro power as-is. It is missing the required `$schema` field and carries `skills` and `agents` as top-level keys that the Agent Plugins 1.0.0 schema does not define (`additionalProperties: false`), so Kiro strips them and the power loads with no components. Reported upstream as [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087).

This mirror's manifest fixes that: `plugin.json` is identity-only with `$schema`, and skills are discovered from `skills/` — the layout the spec requires. The upstream `.claude-plugin/`, `.codex-plugin/`, and `version.json` (other-host discovery and NBGV versioning) are not mirrored.

The power's version is also **decoupled from upstream's**. Upstream bumps all its plugins together on a weekly task (`0.1.8`, `0.1.9`, …); this power instead derives its version from the UTC commit date of the upstream `plugins/dotnet-test-migration` path it mirrors, formatted `yyMM.dHH.mss`, via the shared `.github/scripts/lib/version.sh`. The `sync-dotnet-test-migration.sh` maintainer tool grabs the tree on a schedule and stamps its own date-based version, so the number reflects *when the mirrored content changed*, not upstream's semver.

## Structure

```
dotnet-test-migration/
├── plugin.json                     ← power manifest (identity only, $schema)
├── skills/                         ← mirror of upstream + converted agent
│   ├── migrate-mstest-v1v2-to-v3/
│   │   └── SKILL.md
│   ├── migrate-mstest-v3-to-v4/
│   │   └── SKILL.md
│   ├── migrate-xunit-to-xunit-v3/
│   │   └── SKILL.md
│   ├── migrate-xunit-to-mstest/
│   │   └── SKILL.md
│   ├── migrate-nunit-to-mstest/
│   │   └── SKILL.md
│   ├── migrate-vstest-to-mtp/
│   │   └── SKILL.md
│   └── test-migration/             ← converted from agents/test-migration.agent.md
│       └── SKILL.md
└── sync-dotnet-test-migration.sh   ← maintainer tool
```

## Links

- [dotnet/skills](https://github.com/dotnet/skills)
- [dotnet-test-migration source](https://github.com/dotnet/skills/tree/main/plugins/dotnet-test-migration)
- [dotnet-test power](../dotnet-test) (companion)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Manifest-compliance issue #1087](https://github.com/dotnet/skills/issues/1087)
- [Explicit-invocation feature request #10985](https://github.com/kirodotdev/Kiro/issues/10985)
```
