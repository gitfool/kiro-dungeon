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

## Making a skill always-on

Power skills activate on keyword, not every turn. To make one always-on, ask Kiro to create a global steering file. For example:

> Create a global steering file that always applies pstack's unslop skill

That writes a small file to `~/.kiro/steering/` with `inclusion: always` and a directive referring to the skill. The keyword in the directive triggers the power, and the agent loads the skill every turn without being asked.

## What does not carry over from Cursor

Skills, playbooks, principles, and reference material all port cleanly. These do not:

- **Explicit-only invocation.** Most pstack skills set `disable-model-invocation: true` so that `/poteto-mode` decides what runs. In this power, the keyword gate serves a similar role: skills only activate when you mention a keyword. However, once activated all skills in the power become available to the agent for that turn, rather than only the one the hub selects. Raised as [kirodotdev/Kiro#10985](https://github.com/kirodotdev/Kiro/issues/10985).
- **Per-role model routing.** Cursor's `/setup-pstack` maps roles to different models. Kiro uses one model per turn, so skills fall back to their documented defaults.
- **Subagent routing.** References to `subagent_type: "poteto-agent"` have no Kiro equivalent.
- **Cursor built-ins.** Skills that reach for `/loop`, `/create-skill`, `deslop`, `control-cli`, or `control-ui` need those separately. The last three ship in Cursor's `cursor-team-kit`, not in pstack.

## Structure

```
pstack/
├── plugin.json                 ← power manifest
├── skills/                     ← mirror of upstream pstack/skills
│   ├── poteto-mode/
│   │   ├── SKILL.md
│   │   ├── playbooks/
│   │   ├── references/
│   │   └── scripts/
│   ├── principle-laziness-protocol/
│   │   └── SKILL.md
│   └── ...
├── sync-pstack.ps1             ← maintainer tool
└── sync-pstack.sh
```

Principles keep their upstream `principle-` prefix and sit alongside the other skills, because the spec requires every skill to be an immediate child of `skills/`.

## Links

- [pstack source](https://github.com/cursor/plugins/tree/main/pstack)
- [pstack guide](https://hustlecoding.github.io/pstack-explained/)
- [Agent Skills specification](https://agentskills.io/specification)
- [Agent Plugins specification](https://agent-plugins.org)
- [Kiro powers](https://kiro.dev/docs/powers) and [skills](https://kiro.dev/docs/skills) docs
- [Claude Code port](https://github.com/ennioferreirab/poteto-mode) of the same skills
