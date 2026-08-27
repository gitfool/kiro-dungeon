---
inclusion: always
---

## Always applies

Apply the pstack power `unslop` skill to all prose you produce, including chat replies, commit messages, issue descriptions, merge/pull request descriptions, and documentation. Read the skill in full before writing at length. The rules apply to your own output, not to code or user-provided text you're quoting.

## Cursor compatibility rules

The pstack skills were written for Cursor and contain Cursor-specific terminology and APIs. When reading any pstack skill, apply these interpretation rules:

### Sub-agent invocation

- `Task` tool calls, `subagent_type: generalPurpose` → use `invoke_sub_agent` (or `spawn_run` on Kiro Crew)
- `subagent_type: "poteto-agent"` → ensure the sub-agent reads the poteto-mode skill
- `run_in_background: true` → dispatch sub-agents in parallel (multiple `invoke_sub_agent` calls in one response)
- `environment: "cloud"` / `environment: "local"` → ignore; all sub-agents run in the host environment
- `cloud_base_branch` → ignore; not applicable
- `readonly: true` / `readonly: false` / "agent mode" / "Ask mode" → sub-agents always have full tool access on Kiro; enforce read-only posture via the prompt if needed

### Model selection

- Explicit `model:` directives per sub-agent are advisory only. Kiro does not support per-sub-agent model override. Kiro Crew `spawn_run` does support `model` override.
- References to `~/.cursor/rules/pstack-models.mdc` or `/setup-pstack` → ignore; there is no model configuration mechanism on Kiro

### Cursor paths and tools

- Any `~/.cursor/` path → interpret as the equivalent Kiro location, or ignore if no equivalent exists
- `.cursor/skills/` → skill installation paths (powers install to `~/.kiro/powers/installed/`; `~/.kiro/crew/skills/` on Kiro Crew)
- `AskQuestion` tool → ask the user directly in chat
- `/loop` command → continue autonomously until done or blocked
- `Cursor's built-in create-skill` → author the SKILL.md directly
- `deslop` from `cursor-team-kit` → the **unslop** skill (already always-on via this steering)
- `control-cli` / `control-ui` from `cursor-team-kit` → use the matching control tool for the surface, if available; otherwise skip
- `Graphite` / `gt` → interpret as available stacked-PR workflow tools; otherwise fallback to normal merge workflow
- `bugbot` / "agentic security review" → interpret as any automated code reviewer that commented
- References to "Cursor" as a product → interpret as "the host" (the current IDE or agent runtime)

### Skills that are not operational

Some playbooks have a `> **Kiro compatibility:**` guard at the top indicating they are not operational on Kiro. When you encounter one, tell the user and stop. Do not attempt to execute the playbook steps.
