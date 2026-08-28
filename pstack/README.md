# pstack

Packages [pstack](https://github.com/cursor/plugins/tree/main/pstack) skills and principles as a Kiro [power](https://kiro.dev/docs/powers), so they install in one step and activate on keyword.

`pstack` is a set of rigorous engineering workflows by Lauren Tan ([github](https://github.com/poteto), [twitter](https://twitter.com/poteto)). It includes many skills and principles covering bug fixes, performance, architecture, code review, and more. See the pstack [README](https://github.com/cursor/plugins/blob/main/pstack/README.md) or [guide](https://hustlecoding.github.io/pstack-explained/) for more details.

## Why this works with no conversion

pstack already follows the open [Agent Skills](https://agentskills.io/specification) standard, which Kiro implements. Each skill is a directory holding a `SKILL.md` plus optional `playbooks/`, `references/`, and `scripts/`. Kiro reads that format directly, so `skills/` here is a near-verbatim mirror of upstream.

Only immediate subdirectories of `skills/` count as skills, and clients do not search deeper. Nested markdown under `playbooks/` and `references/` is therefore only read when a skill points at it, which is exactly how pstack expects it to be used.

One fix is applied during the sync. The spec requires each skill's `name` to match its directory name, and upstream `poteto-mode` declares `Poteto Mode`. Kiro rejects a mismatched name silently, so the skill would not load at all. The sync normalizes it. Reported upstream as [cursor/plugins#237](https://github.com/cursor/plugins/issues/237).

## Install

Powers panel, then **Add Custom Power**, then **Import power from GitHub**:

```
https://github.com/gitfool/kiro-dungeon/tree/main/pstack
```

To install a local checkout instead, choose **Import power from a folder** and select the `pstack` directory.

Then copy the steering files to your global steering directory:

```bash
# macOS / Linux
cp ~/.kiro/powers/installed/pstack/steering/*.md ~/.kiro/steering/

# Windows (PowerShell)
Copy-Item "$env:USERPROFILE\.kiro\powers\installed\pstack\steering\*.md" "$env:USERPROFILE\.kiro\steering\"
```

This does two things:

1. Activates the **unslop** skill on every turn, so all prose output follows its rules without needing a keyword.
2. Provides **Cursor runtime rules** that tell the agent how to interpret Cursor-specific terminology in pstack skills, since pstack was written for Cursor. These interpretation rules let the agent adapt the instructions to Kiro at read time rather than relying on brittle text substitutions.

These rules are split into two files. `cursor-runtime.md` is generic. It interprets Cursor runtime operations for any Cursor-origin plugin, so it is reusable beyond pstack. `pstack.md` layers on the mappings specific to pstack and its `cursor-team-kit` dependencies plus the always-applies directive. Install the generic file once; each Cursor-origin power you add can reuse it.

## Usage

Skills activate when you include a power keyword in your message: `poteto`, `pstack`, `unslop`, `rigorous engineering`, or `engineering principles`. Prefix your request with a keyword, optionally naming the skill you want.

```
poteto this pr has a subtle bug where the scroll drifts every 750ms even when idle
pstack how do we cancel runs? do we have an n+1 when we look up every run to cancel?
poteto why is this feature flag not on yet?
pstack interrogate this pr
unslop the README
```

`poteto` and `pstack` are interchangeable. On their own they route through the `poteto-mode` hub skill, which matches the request to a playbook and pulls in the other skills as its steps need them. Name a skill after the keyword, as in the `how` and `interrogate` examples, to go straight there and skip the hub.

`unslop` is both a keyword and a skill name, so it needs no prefix.

## What does not carry over from Cursor

Skills, playbooks, principles, and reference material all port cleanly. The global steering files (`steering/cursor-runtime.md` and `steering/pstack.md`) handle most Cursor terminology at read time. These remain as limitations:

- **Explicit-only invocation.** Most pstack skills set `disable-model-invocation: true` so that `/poteto-mode` decides what runs. In this power, the keyword gate serves a similar role: skills only activate when you mention a keyword. However, once activated all skills in the power become available to the agent for that turn, rather than only the one the hub selects. Raised as [kirodotdev/Kiro#10985](https://github.com/kirodotdev/Kiro/issues/10985).
- **Per-role model routing.** Skills prescribe different models per sub-agent role. Kiro does not support per-sub-agent model override ([kirodotdev/Kiro#6637](https://github.com/kirodotdev/Kiro/issues/6637)). Kiro Crew `spawn_run` does support this. Skills degrade gracefully to using the session model for all sub-agents.
- **Cursor built-ins.** Skills referencing `control-cli`, `control-ui`, or other `cursor-team-kit` tools have no Kiro equivalent. The pstack steering file instructs the agent to skip these when unavailable.
- **Transcript mining.** The `recall` and `reflect` skills depend on Cursor's JSONL transcripts and are not operational on Kiro. `show-me-your-work` works except for its transcript audit step, which should be skipped.
- **Deeply coupled playbooks.** `orchestrate`, `shipping`, `autopilot-full`, `autopilot-stack`, `session-pickup`, and `pause-safely` depend on Cursor cloud agents and tooling. They carry guards and are preserved for methodology reference only.

## Structure

```
pstack/
├── plugin.json                 ← power manifest
├── steering/                   ← global steering
│   ├── cursor-runtime.md       ← generic Cursor runtime
│   └── pstack.md               ← pstack-specific rules
├── skills/                     ← mirror of upstream
│   ├── poteto-mode/
│   │   ├── SKILL.md
│   │   ├── playbooks/
│   │   ├── references/
│   │   └── scripts/
│   ├── principle-laziness-protocol/
│   │   └── SKILL.md
│   └── ...
└── sync-pstack.sh              ← maintainer tool
```

Principles keep their upstream `principle-` prefix and sit alongside the other skills, because the spec requires every skill to be an immediate child of `skills/`.

## Links

- [pstack source](https://github.com/cursor/plugins/tree/main/pstack)
- [pstack guide](https://hustlecoding.github.io/pstack-explained/)
- [Agent Skills specification](https://agentskills.io/specification)
- [Agent Plugins specification](https://agent-plugins.org)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Claude Code port](https://github.com/ennioferreirab/poteto-mode) of the same skills
