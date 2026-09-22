# dotnet-test

Packages the [dotnet/skills](https://github.com/dotnet/skills) `dotnet-test` plugin as a Kiro [power](https://kiro.dev/docs/powers), so its test skills install in one step and activate on demand.

`dotnet-test` is the .NET team's set of skills for running, generating, analyzing, and improving tests: test execution with project-system/platform/framework detection, filter syntax, MTP hot reload, a multi-agent test-generation pipeline, MSTest authoring, coverage and CRAP-score analysis, testability refactoring, and a suite of test-quality audits (anti-patterns, smells, assertion quality, gap analysis, tagging, grading). The test-generation pipeline and the six quality-analysis skills are **polyglot** — beyond .NET they also work with Python, TypeScript/JavaScript, Java, Go, Ruby, Rust, Swift, Kotlin, PowerShell, and C++. See the upstream [dotnet-test plugin](https://github.com/dotnet/skills/tree/main/plugins/dotnet-test) for the source.

This is a **skills-only power** — no bundled MCP server. Unlike the sibling [`dotnet-msbuild`](../dotnet-msbuild) power, upstream `dotnet-test` declares no `mcpServers`, so there is nothing to install alongside the skills and no `mcp.json`. It does ship agents, two of which this power converts to skills (see [below](#agents-become-skills)).

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/dotnet-test
```

To install a local checkout instead, choose **Import power from a folder** and select the `dotnet-test` directory.

## Prerequisites

The .NET-only skills (`run-tests`, `mtp-hot-reload`, `scaffold-dotnet-test-project`, `writing-mstest-tests`, coverage/CRAP, and the testability skills) need the .NET SDK (`dotnet` on PATH) and a project with an existing test framework (MSTest, xUnit, NUnit, or TUnit). The polyglot test-generation and analysis skills just need a working test runtime for the language you target (e.g. `python` + `pytest`, `node` + `npm test`, `go`, `cargo test`, `pwsh` + Pester); they detect the framework automatically.

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask to run a project's tests and `run-tests` engages (with `platform-detection` / `filter-syntax` as shared references); ask to generate tests and the `code-testing-agent` pipeline runs; ask to audit test quality and `test-quality-auditor` routes to `test-anti-patterns`, `assertion-quality`, `test-gap-analysis`, and friends; ask to make static-bound code testable and `testability-migration` drives detect → wrap → migrate → test. Skills that carry their own reference data (`code-testing-extensions`, `test-analysis-extensions`) bring it along when a consumer loads them.

## Agents become skills

Upstream ships ten agents in the plugin's `agents/` array. Kiro does not consume the Agent Plugins `agents` field — it loads skills, MCP servers, and steering, but silently ignores `agents`. The sync converts the **two user-facing entry-point agents** into skills under `skills/`, which is how Kiro users reach the same content Claude Code / Codex users get from the agents natively:

- **`test-quality-auditor`** — runs multi-skill audit pipelines for a comprehensive, polyglot test-suite health check.
- **`testability-migration`** — end-to-end .NET testability improvement: detect static dependencies → generate wrappers → migrate call sites → add deterministic tests.

Both names are already descriptive, so — unlike the sibling `dotnet-msbuild` power's bare `msbuild` agent, which is renamed to `msbuild-expert` — neither is renamed.

The other **eight agents are skipped**. They are `user-invocable: false` internal pipeline stages (`code-testing-generator`, `-researcher`, `-planner`, `-implementer`, `-builder`, `-tester`, `-fixer`, `-linter`) that form a nested GitHub Copilot / VS Code sub-agent fan-out — a swarm Kiro cannot reproduce natively (the analog of pstack's skipped `poteto-agent` routing stub).

Skipping them is safe, and converting them would be worse. Two facts make this the faithful mapping rather than a lossy shortcut:

- **The logic lives in the skill, not the agents.** The public entry point is the **`code-testing-agent` skill**, which is mirrored like any other skill. Its execution contract explicitly handles the agents' absence: *"If `code-testing-generator` is unavailable, do not skip the workflow. Execute the same Research → Plan → Implement sequence inline... apply the same completion contract."* And the common focused case ("tests for X") is told to skip the sub-agent fan-out entirely and work inline regardless. Upstream frames the fan-out itself as an optimization — its own README notes that without nested delegation the implementer *"still builds, tests, fixes, and lints — it just does that work inline instead of delegating... results are unaffected."* So the eight agents are a parallelism accelerator, not the pipeline logic.
- **Converting them would pollute the skill menu.** They are internal stages, not entry points — descriptions like "runs build/compile commands and reports results" only make sense mid-pipeline. As standalone auto-activating skills they would compete for activation and fire on unrelated requests. (This matters more on Kiro because it does not yet honor `disable-model-invocation`, per [#10985](https://github.com/kirodotdev/Kiro/issues/10985), so there is no way to mark a converted stage explicit-only.)

The one real tradeoff is speed, not capability: on Kiro a broad project-wide generation runs the pipeline inline (one agent, sequential Research → Plan → Implement → Build → Test → Fix → Lint) rather than fanning out to parallel workers. That is the same tradeoff upstream documents for VS Code users who leave nested delegation off — slower on large scopes, identical results.

Note that Kiro ignores the Agent Plugins `agents` field for *every* power, so none of the ten agents would load as agents even if mirrored; converting a `.agent.md` to a `skills/<name>/SKILL.md` is the only way to surface its content on Kiro at all. The choice here is therefore "convert vs. leave behind" per agent, and only the two coherent entry points earn conversion.

The converted agents reference GitHub Copilot / Codex tools (`task` / `runSubagent`, `web_fetch`, `web_search`, `skill`) and agent handoffs that do not exist on Kiro. Rather than rewrite the prose, the conversion strips the agent-only frontmatter (`user-invokable`, `tools`, and the multi-line `handoffs:` / `agents:` blocks that name other agents) and appends a short "Kiro tool interpretation" note mapping those references to their Kiro equivalents (`invoke_sub_agent`, `web_fetch`, `disclose_context`) at read time.

`disable-model-invocation` is kept verbatim rather than stripped. Kiro does not honor it yet — it is a silent no-op ([kirodotdev/Kiro#10985](https://github.com/kirodotdev/Kiro/issues/10985)) — so both converted skills auto-activate on description match today, which is the intent for user-facing entry points. Preserving the key is harmless now and keeps the upstream author's explicit-invocation intent intact for the day Kiro implements it; stripping it would silently drop that constraint if upstream ever set it to `true`, with no diff to flag the loss.

## What differs from upstream

The upstream `plugin.json` does not load as a Kiro power as-is. It is missing the required `$schema` field and carries `skills` and `agents` as top-level keys that the Agent Plugins 1.0.0 schema does not define (`additionalProperties: false`), so Kiro strips them and the power loads with no components. Reported upstream as [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087).

This mirror's manifest fixes that: `plugin.json` is identity-only with `$schema`, and skills are discovered from `skills/` — the layout the spec requires. The upstream `OVERLAYS.md`, `.claude-plugin/`, `.codex-plugin/`, and `version.json` (repository-overlay pilot, other-host discovery, and NBGV versioning) are not mirrored.

The power's version is also **decoupled from upstream's**. Upstream bumps all its plugins together on a weekly task (`0.2.21`, `0.2.22`, …); this power instead derives its version from the UTC commit date of the upstream `plugins/dotnet-test` path it mirrors, formatted `yyMM.dHH.mss`, via the shared `.github/scripts/lib/version.sh`. The `sync-dotnet-test.sh` maintainer tool grabs the tree on a schedule and stamps its own date-based version, so the number reflects *when the mirrored content changed*, not upstream's semver.

## Structure

```
dotnet-test/
├── plugin.json                 ← power manifest (identity only, $schema)
├── skills/                     ← mirror of upstream + 2 converted agents
│   ├── run-tests/
│   │   └── SKILL.md
│   ├── code-testing-agent/     ← public entry to the test-generation pipeline
│   │   └── SKILL.md
│   ├── test-quality-auditor/   ← converted from agents/test-quality-auditor.agent.md
│   │   └── SKILL.md
│   ├── testability-migration/  ← converted from agents/testability-migration.agent.md
│   │   └── SKILL.md
│   └── ...
└── sync-dotnet-test.sh         ← maintainer tool
```

## Links

- [dotnet/skills](https://github.com/dotnet/skills)
- [dotnet-test source](https://github.com/dotnet/skills/tree/main/plugins/dotnet-test)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Manifest-compliance issue #1087](https://github.com/dotnet/skills/issues/1087)
- [Explicit-invocation feature request #10985](https://github.com/kirodotdev/Kiro/issues/10985)
```
