---
inclusion: always
---

## Cursor runtime

Agent instructions are portable; agent operations are not. A `SKILL.md` says what should happen, but it may invoke operations belonging to a specific agent runtime. This file teaches the host to interpret Cursor runtime operations at read time, so plugins and skills authored for Cursor can run here without editing the source.

These rules apply whenever you read a skill, playbook, rule, or command that was authored for Cursor. Prefer the intent of the original instruction over its literal reference to a Cursor mechanism. Do not mechanically rewrite the source; interpret it.

### Sub-agent invocation

- `Task` tool calls, `subagent_type: generalPurpose` → use `invoke_sub_agent` (or `spawn_run` on Kiro Crew)
- `run_in_background: true` → dispatch sub-agents in parallel (multiple `invoke_sub_agent` calls in one response)
- `environment: "cloud"` / `environment: "local"` → ignore; all sub-agents run in the host environment
- `cloud_base_branch` → ignore; not applicable
- `readonly: true` / `readonly: false` / "agent mode" / "Ask mode" → sub-agents always have full tool access on Kiro; enforce read-only posture via the prompt if needed

### Model selection

- Explicit `model:` directives per sub-agent are advisory only. Kiro does not support per-sub-agent model override. Kiro Crew `spawn_run` does support `model` override.
- References to a per-model configuration rule file (e.g. under `~/.cursor/rules/`) or a model-setup command → ignore; there is no per-sub-agent model configuration mechanism on Kiro

### Cursor paths and tools

- Any `~/.cursor/` path → interpret as the equivalent Kiro location, or ignore if no equivalent exists
- `.cursor/skills/` → skill installation paths (powers install to `~/.kiro/powers/installed/`; `~/.kiro/crew/skills/` on Kiro Crew)
- `AskQuestion` tool → ask the user directly in chat
- `/loop` command → continue autonomously until done or blocked
- `create-skill` built-in authoring skill → no host equivalent; author the `SKILL.md` directly
- `bugbot` / "agentic security review" → interpret as any automated code reviewer that commented
- References to "Cursor" as a product → interpret as "the host" (the current IDE or agent runtime)

### When no equivalent exists

- When a Cursor mechanism has a direct host equivalent, use it.
- When it has no equivalent but the underlying intent is reachable, execute the intent directly rather than pretending the Cursor mechanism exists.
- When the intent itself is not reachable (for example, it depends on cloud agents or transcript mining that the host does not provide), tell the user and stop rather than faking a result. Skills may mark these with a `> **Kiro compatibility:**` guard.
