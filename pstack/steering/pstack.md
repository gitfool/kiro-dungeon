---
inclusion: always
---

## Always applies

Apply the pstack power `unslop` skill to all prose you produce, including chat replies, commit messages, issue descriptions, merge/pull request descriptions, and documentation. Read the skill in full before writing at length. The rules apply to your own output, not to code or user-provided text you're quoting.

## Plugin compatibility

pstack was written for Cursor. Generic Cursor runtime interpretation lives in `cursor-runtime.md`. The rules below are specific to pstack and its `cursor-team-kit` dependencies:

- `/setup-pstack` command or `pstack-models.mdc` model config file → ignore; there is no such mechanism on Kiro
- `subagent_type: "poteto-agent"` → ensure the sub-agent reads the poteto-mode skill
- `deslop` from `cursor-team-kit` → the **unslop** skill (already always-on via this steering)
- `control-cli` / `control-ui` from `cursor-team-kit` → use the matching control tool for the surface, if available; otherwise skip
- `Graphite` / `gt` → interpret as available stacked-PR workflow tools; otherwise fall back to normal merge workflow

### Skills that are not operational

Some playbooks have a `> **Kiro compatibility:**` guard at the top indicating they are not operational on Kiro. When you encounter one, tell the user and stop. Do not attempt to execute the playbook steps.
