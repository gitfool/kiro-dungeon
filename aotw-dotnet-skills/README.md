# aotw-dotnet-skills

Packages Aaron Stannard's [dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) plugin as a Kiro [power](https://kiro.dev/docs/powers), so its .NET development skills and specialist agents install in one step and activate on demand.

`dotnet-skills` is a comprehensive collection of production-tested .NET patterns covering modern C#, Akka.NET, .NET Aspire, EF Core, testing (Testcontainers, Playwright, snapshot/Verify), serialization, dependency injection and configuration, performance, and Roslyn source generators. Patterns are drawn from production systems including [Akka.NET](https://getakka.net/) and [Petabridge](https://petabridge.com/). See the upstream [repository](https://github.com/Aaronontheweb/dotnet-skills) for the source.

This is a **skills-only power** — no bundled MCP server. Upstream declares no `mcpServers`, so there is nothing to install alongside the skills and no `mcp.json`. It does ship six specialist agents, which this power converts to skills (see [below](#agents-become-skills)).

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/aotw-dotnet-skills
```

To install a local checkout instead, choose **Import power from a folder** and select the `aotw-dotnet-skills` directory.

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask about actor supervision or clustering and the `akka-*` skills engage; ask to wire up Aspire integration tests and `aspire-integration-testing` runs; ask about nullable reference types, records, or type-design performance and the matching `csharp-*` skill takes over; ask to add Testcontainers-backed integration tests or snapshot tests and `testcontainers` / `snapshot-testing` come into play. Skills that carry their own reference `.md` files bring the detail along with them.

## Agents become skills

Upstream ships six agents in the plugin's `agents/` array. Kiro does not consume the Agent Plugins `agents` field — it loads skills, MCP servers, and steering, but silently ignores `agents`. So the sync converts each agent into a skill under `skills/`, which is how Kiro users reach the same content Claude Code / Codex users get from the agents natively:

| Agent (now a skill)                         | Expertise                                                            |
| ------------------------------------------- | -------------------------------------------------------------------- |
| **akka-net-specialist**                     | Actor systems, clustering, persistence, Akka.Streams, message patterns |
| **docfx-specialist**                        | DocFX builds, API documentation, markdown linting                    |
| **dotnet-benchmark-designer**               | BenchmarkDotNet setup, custom benchmarks, measurement strategies     |
| **dotnet-concurrency-specialist**           | Threading, async/await, race conditions, deadlock analysis           |
| **dotnet-performance-analyst**              | Profiler analysis, benchmark interpretation, regression detection    |
| **roslyn-incremental-generator-specialist** | `IIncrementalGenerator` pipeline discipline, parser/emitter separation |

Every agent name is already descriptive, so — unlike the sibling [`dotnet-msbuild`](../dotnet-msbuild) power's bare `msbuild` agent, which is renamed to `msbuild-expert` — they keep their names. The conversion strips agent-only frontmatter (`user-invokable`, `tools`), normalizes the `name` to the skill directory, and preserves the rest, including the multi-line body. Each converted skill activates on description match — Kiro loads a skill when your request matches its `description` — the same intent the agent served.

Upstream agent files carry a doubled frontmatter delimiter (an empty `---`/`---` block before the real one); the converter drops the empty leading block so the resulting skill has one clean frontmatter block. The agents also reference editor/host tools (`task`, `web_fetch`, `web_search`, `skill`) that do not exist by those names on Kiro. Rather than rewrite the prose, the sync appends a short "Kiro tool interpretation" note to each converted skill mapping those references to their Kiro equivalents (`invoke_sub_agent`, `web_fetch`, `disclose_context`) at read time. This power ships no MCP server, so the note makes no mention of one.

## What differs from upstream

The upstream `.claude-plugin/plugin.json` does not load as a Kiro power as-is. It is missing the required `$schema` field and carries `skills` and `agents` as top-level keys that the Agent Plugins 1.0.0 schema does not define (`additionalProperties: false`), so Kiro strips them and the power loads with no components. This is the same manifest-compliance issue reported for the .NET team's plugins as [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087).

This mirror's manifest fixes that: `plugin.json` is identity-only with `$schema`, and skills are discovered from `skills/` — the layout the spec requires. The upstream `.claude-plugin/`, `.codex-plugin/`, `.agents/`, `scripts/`, and top-level docs (other-host discovery and repo tooling) are not mirrored.

The power's version is also **decoupled from upstream's**. Upstream bumps a plugin-wide semver (`1.6.0`, …); this power instead derives its version from the UTC commit date of the upstream repo it mirrors, formatted `yyMM.dHH.mss`, via the shared `.github/scripts/lib/version.sh`. The `sync-aotw-dotnet-skills.sh` maintainer tool grabs the tree on a schedule and stamps its own date-based version, so the number reflects *when the mirrored content changed*, not upstream's semver. Upstream's default branch is `master`, so the sync tracks `master` rather than `main`.

## Structure

```
aotw-dotnet-skills/
├── plugin.json                     ← power manifest (identity only, $schema)
├── POWER.md                        ← Powers panel presentation (keywords, author)
├── skills/                         ← mirror of upstream + converted agents
│   ├── akka-best-practices/
│   │   ├── SKILL.md
│   │   └── *.md                    ← sibling reference docs
│   ├── csharp-coding-standards/
│   │   └── SKILL.md
│   ├── testcontainers/
│   │   └── SKILL.md
│   ├── akka-net-specialist/        ← converted from agents/akka-net-specialist.md
│   │   └── SKILL.md
│   ├── dotnet-performance-analyst/ ← converted from agents/dotnet-performance-analyst.md
│   │   └── SKILL.md
│   └── ...
└── sync-aotw-dotnet-skills.sh      ← maintainer tool
```

## Links

- [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills)
- [Aaron Stannard](https://aaronstannard.com/) ([@Aaronontheweb](https://github.com/Aaronontheweb)) · [Petabridge](https://petabridge.com/) · [Akka.NET](https://getakka.net/)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Manifest-compliance issue #1087](https://github.com/dotnet/skills/issues/1087)
