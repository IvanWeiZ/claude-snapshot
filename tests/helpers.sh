#!/bin/bash
# Shared test helpers for claude-snapshot tests
# Source this file in each test: source "$(dirname "$0")/helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX"
CLAUDE_DIR="$SANDBOX/.claude"
REPO="$SANDBOX/claude-snapshot"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Isolated git identity (sandbox has no ~/.gitconfig)
git config --global user.email "test@claude-snapshot.dev"
git config --global user.name "claude-snapshot-test"

# Reset ~/.claude to minimal state
reset_claude_dir() {
  rm -rf "$CLAUDE_DIR"
  mkdir -p "$CLAUDE_DIR"
  echo '{}' > "$CLAUDE_DIR/settings.json"
}

# Copy project files to a target directory
copy_project_files() {
  local target="$1"
  mkdir -p "$target"
  cp "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/snapshot.sh" "$target/"
  [ -f "$SCRIPT_DIR/.gitignore" ] && cp "$SCRIPT_DIR/.gitignore" "$target/"
  [ -f "$SCRIPT_DIR/install-remote.sh" ] && cp "$SCRIPT_DIR/install-remote.sh" "$target/"
  chmod +x "$target/setup.sh" "$target/snapshot.sh"
}

# Create a clean sandbox with sample config
setup_sandbox() {
  rm -rf "$SANDBOX"/*
  mkdir -p "$CLAUDE_DIR"/{hooks,commands,scripts,plugins,agents/engineering,projects/-sandbox-myproject/memory,skills/my-skill}

  echo '{}' > "$CLAUDE_DIR/settings.json"
  echo "# My Instructions" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{"test": true}' > "$CLAUDE_DIR/settings.local.json"

  echo '[]' > "$CLAUDE_DIR/plugins/installed_plugins.json"
  echo '[]' > "$CLAUDE_DIR/plugins/known_marketplaces.json"

  echo '#!/bin/bash' > "$CLAUDE_DIR/hooks/my-hook.sh"
  chmod +x "$CLAUDE_DIR/hooks/my-hook.sh"
  echo "# My command" > "$CLAUDE_DIR/commands/my-cmd.md"
  echo '#!/bin/bash' > "$CLAUDE_DIR/scripts/my-script.sh"
  chmod +x "$CLAUDE_DIR/scripts/my-script.sh"

  echo "# My Agent" > "$CLAUDE_DIR/agents/engineering/coder.md"
  echo "# My Skill" > "$CLAUDE_DIR/skills/my-skill/README.md"
  echo "# Memory note" > "$CLAUDE_DIR/projects/-sandbox-myproject/memory/note.md"

  copy_project_files "$REPO"
}

# Install and run first snapshot
install_snapshot() {
  bash "$REPO/setup.sh" > /dev/null 2>&1
}

# Print test results and exit with appropriate code
results() {
  echo ""
  echo "  $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}
