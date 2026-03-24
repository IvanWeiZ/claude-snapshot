# CLAUDE.md

## Project Overview

**claude-snapshot** is a shell-based tool that auto-snapshots `~/.claude/` configuration to a git repository. It hooks into Claude Code's event system (SessionStart, PostToolUse) to automatically commit config changes with zero user effort.

## Repository Structure

```
├── setup.sh              # Main entry point: install, restore, uninstall, status, diff, log
├── snapshot.sh            # Core snapshot logic (copied to ~/.claude/hooks/ at install time)
├── install-remote.sh      # One-liner remote installer (curl | bash)
├── test.sh                # Test runner — executes all tests/test_*.sh
├── tests/
│   ├── helpers.sh         # Shared test setup: sandbox creation, assertions (pass/fail)
│   ├── test_setup.sh      # Install, idempotency, preserving existing hooks
│   ├── test_snapshot.sh   # Config capture, change detection, PostToolUse filtering
│   ├── test_restore.sh    # --restore flow
│   ├── test_uninstall.sh  # --uninstall flow
│   ├── test_commands.sh   # --status, --diff, --log, --help
│   ├── test_security.sh   # Secret detection, auto-push
│   └── test_remote_install.sh  # Remote installer simulation
├── .github/workflows/test.yml  # CI: runs tests on ubuntu + macOS
├── claude-snapshot.md     # Project memory tag
├── .gitignore             # Optional exclusions for sensitive data
├── LICENSE                # MIT
└── README.md              # User-facing documentation
```

## Key Files

- **`setup.sh`** — All user-facing commands. Functions: `do_install`, `do_restore`, `do_uninstall`, `do_status`, `do_diff`, `do_log`. Uses `jq` to idempotently register/deregister hooks in `settings.json`.
- **`snapshot.sh`** — The hook script. Copies config categories (config, plugins, hooks, commands, scripts, skills, agents, memory) from `~/.claude/` to the repo via `rsync`/`cp`, runs secret detection, then `git add -A && git commit`. For PostToolUse events, filters stdin JSON to only trigger on `claude plugin install/uninstall`.
- **`tests/helpers.sh`** — Creates an isolated sandbox (`$HOME` redirected to temp dir), provides `pass()`/`fail()` assertions, `setup_sandbox()` to populate sample config, and `install_snapshot()` to run setup.

## Development Workflow

### Running Tests

```bash
bash test.sh
```

Tests run in isolated sandboxes (temp dirs with `$HOME` overridden). Each test file is independent — no shared state between suites. The test runner reports pass/fail counts per suite.

### CI

GitHub Actions runs `bash test.sh` on both `ubuntu-latest` and `macos-latest` on pushes/PRs to `main`.

### Prerequisites

- `bash`, `git`, `rsync`, `jq`
- No build step, no dependencies to install

## Conventions

- **Pure shell (bash):** No Python, Node, or other runtimes. All scripts use `#!/bin/bash` with `set -e`.
- **Idempotent operations:** `setup.sh` and hook registration can be run multiple times safely. The `jq` filters check for existing entries before adding.
- **Sandbox testing:** Tests never touch the real `~/.claude/`. Each test creates a temp dir, sets `$HOME` to it, and cleans up via `trap`.
- **Assertions:** Use `pass "description"` and `fail "description"` from `helpers.sh`. Test results are counted by grepping for `PASS:` and `FAIL:` in output.
- **Error handling:** Use `die()` for fatal errors. Scripts exit 0 on success, 1 on failure.
- **No `--no-verify` in user commits:** The snapshot script uses `--no-verify` for its own auto-commits only (these are internal bookkeeping, not user code).

## Architecture Notes

- The snapshot hook (`snapshot.sh`) is **copied** to `~/.claude/hooks/claude-snapshot.sh` at install time. The repo path is stored in `~/.claude/.snapshot-repo`.
- Hook registration modifies `~/.claude/settings.json` using `jq`. A backup is created at `settings.json.pre-snapshot-backup` before changes.
- Memory files use a portable path extraction: project directories like `-Users-alice-projects-foo` get simplified to just `foo`.
- Auto-push is opt-in via `CLAUDE_SNAPSHOT_PUSH=1` environment variable.
- Secret detection scans `settings.json` and `settings.local.json` for API keys/tokens and warns on stderr (does not block commits).
