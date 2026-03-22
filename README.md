# claude-snapshot

Auto-snapshot your Claude Code config to git. Every session, every plugin change — captured automatically.

No external tools. No cron jobs. Just a hook and git.

## Quick Start

```bash
# 1. Create your config repo (private recommended)
gh repo create my-claude-config --template IvanWeiZ/claude-snapshot --private --clone
cd my-claude-config

# 2. Run setup
./setup.sh

# 3. Done. Open Claude Code — your config auto-snapshots.
```

Or without GitHub CLI:

```bash
git clone https://github.com/IvanWeiZ/claude-snapshot ~/claude-config
cd ~/claude-config
./setup.sh
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
    |-- SessionStart ---------> snapshot.sh --> git add -A && git commit
    |-- plugin install/uninstall --> snapshot.sh --> git add -A && git commit
    |
    v
your-config-repo/
    config/        <-- settings, CLAUDE.md, plugin metadata
    hooks/         <-- hook scripts
    commands/      <-- slash commands
    scripts/       <-- shell scripts
    agents/        <-- agent definitions
    skills/        <-- skills
    memory/        <-- auto-memory by project
```

**Triggers:**
- **SessionStart** — captures all changes made between sessions
- **PostToolUse:Bash** — captures `claude plugin install/uninstall` in real-time

**Performance:** ~60ms per snapshot. You won't notice it.

## Restore on New Machine

```bash
git clone https://github.com/you/my-claude-config ~/claude-config
cd ~/claude-config
./setup.sh --restore
```

This copies all config back to `~/.claude/` and re-registers the hooks.

## Uninstall

```bash
./setup.sh --uninstall
```

Removes the hooks from `settings.json` and deletes the hook file. Your config repo is preserved.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `git`, `rsync`, `jq` (pre-installed on most systems)
- macOS or Linux

## FAQ

**Should I make my config repo public or private?**
Private is recommended. Your `settings.json` may contain permission rules, and `memory/` can contain project context. If you want a public repo, add sensitive paths to `.gitignore`.

**Multiple machines?**
Use one repo per machine. `settings.json` contains absolute paths that differ between machines. Alternatively, add `config/settings.json` to `.gitignore` and manage it separately.

**What about secrets?**
The snapshot only captures config files, not credentials or session tokens. Still, review your `CLAUDE.md` and `settings.json` before making a repo public.

**Can I customize what gets tracked?**
Edit `snapshot.sh` — it's a simple bash script. Comment out any section you don't want captured.

**How often does it commit?**
Once per Claude Code session (on start), plus once per plugin install/uninstall. Typically 1-5 commits per day.

## License

MIT
