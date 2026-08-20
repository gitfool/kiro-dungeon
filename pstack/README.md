# pstack

Syncs [pstack](https://github.com/cursor/plugins/tree/main/pstack) skills and principles to the global [steering](https://kiro.dev/docs/steering) directory, so they work as native steering files without losing functionality.

`pstack` is a set of rigorous engineering workflows by Lauren Tan ([github](https://github.com/poteto), [twitter](https://twitter.com/poteto)). It includes many skills and principles covering bug fixes, performance, architecture, code review, and more. See the pstack [README](https://github.com/cursor/plugins/blob/main/pstack/README.md) or [guide](https://hustlecoding.github.io/pstack-explained/) for more details.

## How it works

The sync script downloads the pstack repo, extracts each skill's `SKILL.md`, injects Kiro-compatible front-matter (inclusion mode, name, description), and writes them to `~/.kiro/steering/pstack/`. Support files (playbooks, references) are renamed from `.md` to `.md.txt` so Kiro's recursive steering scanner doesn't auto-load them as separate entries.

The upstream description field from each skill is preserved in the front-matter, enabling Kiro's `inclusion: auto` mode to semantically match skills to your requests.

## Install

Download `sync-pstack.ps1` (Windows/WSL/any pwsh 7) or `sync-pstack.sh` (macOS/Linux) to `~/.local/bin/`:

### Linux / macOS

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/gitfool/kiro-dungeon/main/pstack/sync-pstack.sh -o ~/.local/bin/sync-pstack.sh
chmod +x ~/.local/bin/sync-pstack.sh
```

Requires `bash`, `curl`, `unzip`, and `jq`.

### Windows (PowerShell 7)

```powershell
New-Item -ItemType Directory -Path "$HOME\.local\bin" -Force
Invoke-WebRequest https://raw.githubusercontent.com/gitfool/kiro-dungeon/main/pstack/sync-pstack.ps1 -OutFile "$HOME\.local\bin\sync-pstack.ps1"
```

Then add to PATH with scoop:

```powershell
scoop shim add sync-pstack "$HOME\.local\bin\sync-pstack.ps1"
```

Or add `~/.local/bin` to your PATH manually.

## Usage

```sh
# First run creates a config file and syncs everything
sync-pstack.sh

# Preview what would change without writing
sync-pstack.sh --dry-run

# Reset config to defaults
sync-pstack.sh --init
```

PowerShell equivalent: `sync-pstack.ps1`, `sync-pstack.ps1 -DryRun`, `sync-pstack.ps1 -Init`.

## Configuration

On first run, the script creates `sync-pstack.config.json` next to itself:

```json
{
  "repository": "cursor/plugins",
  "branch": "main",
  "basePath": "pstack/skills",
  "includeAlways": [
    "principle-laziness-protocol",
    "unslop"
  ],
  "includeAuto": []
}
```

| Field | What it does |
|-------|-------------|
| `includeAlways` | Skills set to `inclusion: always` (loaded every session) |
| `includeAuto` | Skills set to `inclusion: auto` (loaded when Kiro matches the description to your request) |
| Everything else | Defaults to `inclusion: manual` (invoke with `#pstack-skillname` in chat) |

## Output structure

```
~/.kiro/steering/pstack/
├── skills/
│   ├── poteto-mode/
│   │   ├── SKILL.md              ← steering entry (with Kiro front-matter)
│   │   ├── playbooks/            ← support files (*.md.txt, not scanned)
│   │   └── references/
│   ├── how/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── unslop/
│   │   └── SKILL.md
│   └── ...
└── principles/
    ├── laziness-protocol/
    │   └── SKILL.md
    ├── prove-it-works/
    │   └── SKILL.md
    └── ...
```

## Editor setup

To get markdown highlighting for `.md.txt` files, add to your VS Code / Kiro settings:

```json
"files.associations": {
    "*.md.txt": "markdown"
}
```

## Updating

Run the sync script again. It compares content and only updates files that changed upstream.

## Links

- [pstack source](https://github.com/cursor/plugins/tree/main/pstack)
- [pstack community guide](https://hustlecoding.github.io/pstack-explained/)
- [Kiro steering docs](https://kiro.dev/docs/steering)
- [Kiro powers docs](https://kiro.dev/docs/powers) (future: this could become a Kiro power)
- [Claude Code port](https://github.com/ennioferreirab/poteto-mode) (similar effort for Claude Code)
