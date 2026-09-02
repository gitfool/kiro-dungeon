# windbg

Packages the [windbg-mcp](https://github.com/glslang/windbg-mcp) server and its `windbg-debugging` skill as a Kiro [power](https://kiro.dev/docs/powers), so they install in one step and the skill activates on keyword.

`windbg-mcp` wraps WinDbg/DbgEng for four kinds of Windows debugging: dump analysis (crash, hang, or snapshot — user-mode and kernel), live user-mode debugging, kernel debugging, and Time Travel Debugging (TTD) of `.run` traces. The `windbg-debugging` skill knows how to drive it, with playbooks for setup, dump triage, live/kernel debugging, heap/pool walking, driver IOCTL discovery, and TTD. See the windbg-mcp [README](https://github.com/glslang/windbg-mcp/blob/main/README.md) for more details.

## How this works with no conversion

windbg-mcp already ships an [Agent Skill](https://agentskills.io/specification) and an MCP server, both formats Kiro implements directly. This power is a thin wrapper:

- `mcp.json` declares the `windbg` server (agent-plugins form).
- `skills/windbg-debugging/` is a near-verbatim mirror of the upstream skill.

Unlike a Cursor-origin power, there is no runtime terminology to reinterpret. The skill drives its own MCP tools, so the port is direct.

## The binary is not bundled — Scoop provides it

The upstream Claude Code plugin ships source and points at a built binary under the plugin directory. This power takes a different route: it references `windbg-mcp` on `PATH`, installed by Scoop.

`mcp.json` declares a single bare command:

```json
{
  "mcpServers": {
    "windbg": {
      "type": "stdio",
      "command": "windbg-mcp"
    }
  }
}
```

The command is a single token with no path and no `.exe`, so it resolves through the Scoop shim on `PATH`. This decouples the power from the binary's version and location: a `scoop update windbg-mcp` upgrades the server and engine, and the power stays put.

## Prerequisites

Install the server from the community [`gitfool/scoop-dungeon`](https://github.com/gitfool/scoop-dungeon) bucket:

```pwsh
scoop bucket add dungeon https://github.com/gitfool/scoop-dungeon
scoop install windbg-mcp
```

This puts `windbg-mcp` on `PATH`. Its `post_install` also bundles the WinDbg engine DLLs (plus the `ttd\`, `winext\` and `winxp\` payloads, and the 32-bit `x86\` engine) next to the binary **when the `Microsoft.WinDbg` Store package is installed** — those are what enable TTD `.run` replay, `!analyze` triage, the kernel driver-object tools, and SOS on 32-bit .NET (WoW64) targets. Basic live and dump debugging works without them, on the in-box `System32` engine. If WinDbg was not installed when Scoop ran, install it from the Store and `scoop update --force windbg-mcp` to bundle the engine.

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/windbg
```

To install a local checkout instead, choose **Import power from a folder** and select the `windbg` directory.

Kiro reads `mcp.json` and connects the `windbg` server, and the `windbg-debugging` skill becomes available. Verify the server is connected from the MCP Server view in the Kiro feature panel.

## Updating

**Disconnect the `windbg` MCP server before `scoop update windbg-mcp`.** A connected client holds `windbg-mcp.exe` open — the server re-executes its own image to spawn engine workers, so the file is locked while a client is attached, and the update fails. Disable the `windbg` server (or close Kiro), run the update, then reconnect.

## Usage

The skill is keyword-gated: it activates when your message matches its keywords — `windbg`, `dbgeng`, `dump analysis`, `kernel debugging`, `time travel debugging` — or its description. Matching is semantic, not exact-string, so you do not have to type a keyword verbatim. Related phrasing routes there too: a hang, crash, or snapshot `.dmp`; opening or triaging a dump; attaching to a process or the kernel; recording, opening, or navigating a `.run` / TTD trace; walking the pool or a segment heap; enumerating a driver's IOCTLs. Naming the tool (`windbg`) or the engine (`dbgeng`) is the most reliable trigger when a request is ambiguous. Once active, it reads your target and picks the matching playbook.

```
windbg triage this dump: C:\dumps\app.dmp
analyze this hang dump with windbg
windbg open the kernel minidump and find the faulting driver
windbg attach to the kernel and enumerate mydriver's IOCTLs
windbg record a TTD trace of this repro and find every call to NtCreateFile
windbg walk the segment heap and show the heaviest allocations
```

Once the skill is active, the `windbg` MCP server's [tools](https://github.com/glslang/windbg-mcp/blob/main/README.md#tools) are available for the agent to drive.

## What is not vendored

The upstream `docs/` and `examples/` directories are intentionally **not** mirrored into this power. They are heavy (long walkthroughs, sample dumps, a recorded cast, a large GIF) and change often, and the MCP server never reads them — only the skill and the model do, and the skill already carries the runtime knowledge in its playbooks.

The skill's playbooks link to the walkthroughs by upstream URL (the sync rewrites the repo-relative paths). For the full teaching material and reference, go upstream:

- [Walkthroughs index](https://github.com/glslang/windbg-mcp/blob/main/docs/walkthroughs.md) — crash-dump, TTD, driver-IOCTL, and live worked examples with real debugger output
- [Install guide](https://github.com/glslang/windbg-mcp/blob/main/docs/install.md) — build/download, engine bundling
- [Tool surface](https://github.com/glslang/windbg-mcp/blob/main/docs/tool-surface.md) and [architecture](https://github.com/glslang/windbg-mcp/blob/main/docs/architecture.md)
- [Remote listener](https://github.com/glslang/windbg-mcp/blob/main/docs/remote-listener.md) — running the server on another machine over HTTP

## Structure

```
windbg/
├── plugin.json                 ← power manifest
├── POWER.md                    ← power manifest (legacy)
├── mcp.json                    ← mcp server
├── sync-windbg.sh              ← maintainer tool
└── skills/
    └── windbg-debugging/       ← mirror of upstream
        ├── SKILL.md
        ├── setup.md
        ├── crash-dump.md
        ├── live-and-kernel.md
        ├── driver-ioctl.md
        ├── heap-walking.md
        └── ttd.md
```

## Maintenance

`sync-windbg.sh` mirrors `skills/windbg-debugging` from upstream and rewrites the playbooks' repo-relative `../../docs/` links to absolute upstream URLs, so they resolve from the standalone power. It is a maintainer tool, not an installer; run it to refresh the skill when upstream changes, then commit the result. Version bumping is handled separately by the repo's `bump` workflow, which derives a date-based version from the upstream commit date.

```bash
./windbg/sync-windbg.sh --dry-run   # preview
./windbg/sync-windbg.sh             # apply
```

## Links

- [windbg-mcp source](https://github.com/glslang/windbg-mcp)
- [windbg-mcp on scoop-dungeon](https://github.com/gitfool/scoop-dungeon/blob/main/bucket/windbg-mcp.json)
- [Agent Plugins specification](https://agent-plugins.org)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
