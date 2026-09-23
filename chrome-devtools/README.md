# chrome-devtools

Packages the [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) plugin as a Kiro [power](https://kiro.dev/docs/powers), so its Chrome DevTools skills and the `chrome-devtools` MCP server install in one step and activate on demand.

`chrome-devtools-mcp` is the Chrome team's plugin for driving a live Chrome browser from a coding agent: recording performance traces and extracting actionable insights, inspecting network requests and console messages (with source-mapped stack traces), reading the DOM through accessibility snapshots, and automating interactions via Puppeteer. The MCP server exposes these as structured tools; the bundled skills carry the workflow knowledge for using them well — page targeting, snapshot-then-interact ordering, and focused debugging playbooks. See the upstream [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) repo for the source.

## Requirements

The MCP server runs from npm via `npx`, so it needs:

- [Node.js](https://nodejs.org/) LTS
- [Chrome](https://www.google.com/chrome/) current stable or newer (the server starts the browser automatically on the first tool call that needs it)

No separate install step for the server itself — `npx` fetches it on first run. Upstream officially supports Google Chrome and [Chrome for Testing](https://developer.chrome.com/blog/chrome-for-testing/) only.

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/chrome-devtools
```

To install a local checkout instead, choose **Import power from a folder** and select the `chrome-devtools` directory. Remove any [manual `chrome-devtools` entry](#the-mcp-server) from your MCP settings after installing, so the server has a single source of truth.

## The MCP server

`mcp.json` declares the `chrome-devtools` server:

```json
{
  "command": "npx",
  "args": ["-y", "chrome-devtools-mcp@latest", "--no-usage-statistics"]
}
```

- **`npx -y chrome-devtools-mcp@latest`** is the upstream-documented invocation. `@latest` keeps the server evergreen — each launch resolves the newest published version. Pin a version (`chrome-devtools-mcp@1.9.0`) in `mcp.json` to freeze it.
- **`--no-usage-statistics`** opts out of the usage statistics Google collects by default (tool success rates, latency, environment info). Drop the flag to allow collection; see the upstream [README](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/README.md) for what is collected. Note that performance tools may still send trace URLs to the Google CrUX API for real-user data — add `--no-performance-crux` to disable that too.
- **Additional tooling is gated behind flags.** Extension tools require `--categoryExtensions`; memory-debugging tools require `--memoryDebugging`. Add these to `args` if a skill (e.g. `memory-leak-debugging`) asks for tools that are not in the default set. Basic browsing can be narrowed with `--slim`, but note the core `chrome-devtools` skill states it does not apply in `--slim` mode.

Kiro installs a power's MCP server internally, namespaced (e.g. `power-chrome-devtools-chrome-devtools`), and activates it with the power — it is not written to your `~/.kiro/settings/mcp.json`.

> **If you already run the Chrome DevTools server manually:** remove your hand-added `chrome-devtools` entry from `~/.kiro/settings/mcp.json` after installing this power, so the server has a single source of truth. Otherwise you will have two servers, each launching its own Chrome.

## Usage

The skills activate on demand from their descriptions — no keyword prefix. Ask to debug a slow page load and `debug-optimize-lcp` engages; report a layout or contrast problem and `a11y-debugging` comes into play; chase a leak and `memory-leak-debugging` runs (enable `--memoryDebugging` first). The core `chrome-devtools` skill carries the general workflow — page targeting with `pageId`, `take_snapshot` → interact ordering, snapshot vs screenshot vs `evaluate_script` — and the MCP tools drive the actual browser.

```
check the performance of https://developers.chrome.com
why is the largest contentful paint slow on this page?
debug the failed network requests on localhost:3000
audit this page for accessibility issues
find the memory leak on this page
```

Once a skill is active, the `chrome-devtools` MCP server's [tools](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md) are available for the agent to drive.

## Skills

Seven skills are mirrored verbatim from upstream:

| Skill | Covers |
| --- | --- |
| `chrome-devtools` | Core workflow: browser lifecycle, page targeting, snapshot/interact patterns, tool selection, extension testing |
| `chrome-devtools-cli` | Using the DevTools CLI (the non-MCP path the upstream also provides) |
| `a11y-debugging` | Accessibility inspection and remediation |
| `cookie-debugging` | Inspecting and diagnosing cookie behavior |
| `debug-optimize-lcp` | Diagnosing and improving Largest Contentful Paint |
| `memory-leak-debugging` | Heap-snapshot-driven memory-leak hunting (needs `--memoryDebugging`) |
| `troubleshooting` | Recovering when the server or Chrome misbehaves |

There are no agents to convert — unlike the dotnet powers, this upstream ships skills and an MCP server only, both formats Kiro implements directly.

## What differs from upstream

Little, by design. Upstream's `plugin.json` is **already** Agent Plugins 1.0.0 compliant — it has the required `$schema` and is identity-only (no top-level `skills`/`agents`/`mcpServers` keys), so it is not the [dotnet/skills#1087](https://github.com/dotnet/skills/issues/1087) case the dotnet mirrors have to fix. This power still carries its own `plugin.json` (its own author, homepage, and decoupled version) plus a sibling `mcp.json`, which is the layout Kiro discovers components from.

The power's version is **decoupled from upstream's** semver. This power derives its version from the UTC commit date of the upstream `skills/` tree it mirrors, formatted `yyMM.dHH.mss`, via the shared [`.github/scripts/lib/version.sh`](../.github/scripts/lib/version.sh). Versioning off `skills/` (not the repo root) means the number tracks *when the mirrored skills changed*, not every commit to the server code, docs, or tests.

## Structure

```
chrome-devtools/
├── plugin.json                 ← power manifest (identity only, $schema)
├── POWER.md                    ← power manifest (Powers panel display)
├── mcp.json                    ← chrome-devtools MCP server (npx)
├── skills/                     ← verbatim mirror of upstream skills/
│   ├── chrome-devtools/
│   │   └── SKILL.md
│   ├── a11y-debugging/
│   │   └── SKILL.md
│   ├── debug-optimize-lcp/
│   │   └── SKILL.md
│   └── ...
└── sync-chrome-devtools.sh     ← maintainer tool
```

## Links

- [chrome-devtools-mcp source](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- [Tool reference](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md) and [troubleshooting](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/troubleshooting.md)
- [Chrome DevTools for agents](https://developer.chrome.com/docs/devtools/agents)
- [Agent Plugins specification](https://agent-plugins.org) and [Agent Skills specification](https://agentskills.io/specification)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
