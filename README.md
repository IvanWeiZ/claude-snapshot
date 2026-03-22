# claude-snapshot

[![Tests](https://github.com/IvanWeiZ/claude-snapshot/actions/workflows/test.yml/badge.svg)](https://github.com/IvanWeiZ/claude-snapshot/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)

Your Claude Code config, version-controlled automatically.

Every session start, every plugin change — captured in git with zero effort.

## Why?

You spend hours customizing Claude Code — hooks, commands, agents, CLAUDE.md rules, plugin configs. But:

- **No backup.** One bad `rm` or reinstall and it's gone.
- **No history.** What did your config look like last week? No idea.
- **No sync.** New machine means starting from scratch.

claude-snapshot fixes all three. It hooks into Claude Code's event system and auto-commits your config on every session. Your `~/.claude/` becomes a git repo with full history.

## Quick Start

**One-liner install** (no clone needed):

```bash
curl -fsSL https://raw.githubusercontent.com/IvanWeiZ/claude-snapshot/main/install-remote.sh | bash
```

**Or clone and setup:**

```bash
git clone https://github.com/IvanWeiZ/claude-snapshot ~/claude-config
cd ~/claude-config
./setup.sh
```

**Or use as a template** (fork your own config repo):

```bash
gh repo create my-claude-config --template IvanWeiZ/claude-snapshot --private --clone
cd my-claude-config
./setup.sh
```

## What It Looks Like

```
$ ./setup.sh --log
3 minutes ago  auto: sync config ( 2 files changed, 5 insertions(+), 1 deletion(-))
2 hours ago    auto: install pua@pua-skills ( 1 file changed, 3 insertions(+))
1 day ago      auto: sync config ( 1 file changed, 12 insertions(+))
3 days ago     auto: sync config ( 4 files changed, 47 insertions(+), 2 deletions(-))
```

```
$ ./setup.sh --status
claude-snapshot status

  Hook:   ~/.claude/hooks/claude-snapshot.sh (installed)
  Repo:   ~/claude-config (42 commits, last: 3 minutes ago)
  Hooks:  registered in settings.json
  Push:   disabled (set CLAUDE_SNAPSHOT_PUSH=1 to enable)

  Tracking:
    config/ (5 files)
    hooks/ (6 files)
    commands/ (4 files)
    agents/ (35 files)
    skills/ (12 files)
    memory/ (8 files)
```

## What Gets Tracked

| Category | Source | Files |
|---|---|---|
| Config | `~/.claude/` | `settings.json`, `*.md` (CLAUDE.md, etc.), `keybindings.json` |
| Plugins | `~/.claude/plugins/` | `installed_plugins.json`, `known_marketplaces.json`, `blocklist.json` |
| Hooks | `~/.claude/hooks/` | `*.sh` |
| Commands | `~/.claude/commands/` | `*.md` |
| Scripts | `~/.claude/scripts/` | `*.sh` |
| Skills | `~/.claude/skills/` | All files (follows symlinks) |
| Agents | `~/.claude/agents/` | All files |
| Memory | `~/.claude/projects/*/memory/` | All files (organized by project) |

## How It Works

```
~/.claude/ (live config)
    |
    |-- SessionStart -----------> snapshot.sh --> git add -A && git commit
    |-- plugin install/uninstall --> snapshot.sh --> git add -A && git commit
    |
    v
your-config-repo/
    config/     settings, CLAUDE.md, plugin metadata
    hooks/      hook scripts
    commands/   slash commands
    scripts/    shell scripts
    agents/     agent definitions
    skills/     skills
    memory/     auto-memory by project
```

**Triggers:**
- **SessionStart** — captures all changes made between sessions
- **PostToolUse:Bash** — captures `claude plugin install/uninstall` in real-time

**Performance:** ~60ms per snapshot. You won't notice it.

## Commands

```bash
./setup.sh              # Install hooks and run first snapshot
./setup.sh --restore    # Restore config from repo to ~/.claude/
./setup.sh --uninstall  # Remove hooks (keeps your repo)
./setup.sh --status     # Health check: what's installed and tracked
./setup.sh --diff       # Show changes since last snapshot
./setup.sh --log [N]    # Show last N snapshots (default: 10)
./setup.sh --help       # Show all commands
```

## Auto-Push to Remote

Opt-in: set `CLAUDE_SNAPSHOT_PUSH=1` to auto-push after each commit.

```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc):
export CLAUDE_SNAPSHOT_PUSH=1
```

## Restore on New Machine

```bash
git clone https://github.com/you/my-claude-config ~/claude-config
cd ~/claude-config
./setup.sh --restore
```

Copies all config back to `~/.claude/` and re-registers the hooks.

## Security

- **Secret detection:** Warns if `settings.json` contains API keys, tokens, or credentials
- **Private repos recommended:** Your config may contain permission rules and project context
- **Customize `.gitignore`:** Uncomment lines to exclude `memory/` or `settings.local.json`

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `git`, `rsync`, `jq` (pre-installed on most systems)
- macOS or Linux

## FAQ

**Multiple machines?**
Use one repo per machine. `settings.json` contains absolute paths that differ. Or add `config/settings.json` to `.gitignore`.

**Can I customize what's tracked?**
Edit `snapshot.sh` — comment out any section you don't need.

**How often does it commit?**
Once per session start + once per plugin change. Typically 1-5 commits per day.

## License

MIT
