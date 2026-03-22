#!/bin/bash
# claude-snapshot setup
# Usage:
#   ./setup.sh              Install: register hooks, run first snapshot
#   ./setup.sh --restore    Restore: copy config from repo to ~/.claude/
#   ./setup.sh --uninstall  Remove: deregister hooks, clean up
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HOOK_FILE="claude-snapshot.sh"
HOOK_PATH="$CLAUDE_DIR/hooks/$HOOK_FILE"
MARKER="$CLAUDE_DIR/.snapshot-repo"
SETTINGS="$CLAUDE_DIR/settings.json"

# Resolved absolute path for hook command (Claude Code requires absolute paths)
HOOK_CMD="bash $HOME/.claude/hooks/$HOOK_FILE"

# --- Helpers ---

die() { echo "Error: $1" >&2; exit 1; }

check_prereqs() {
  for cmd in git rsync jq; do
    command -v "$cmd" >/dev/null || die "$cmd is required but not installed"
  done
  [ -d "$CLAUDE_DIR" ] || die "$CLAUDE_DIR not found. Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
}

register_hooks() {
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

  # Backup
  cp "$SETTINGS" "$SETTINGS.pre-snapshot-backup"

  # Add SessionStart hook (idempotent)
  jq --arg cmd "$HOOK_CMD" '
    .hooks //= {} |
    .hooks.SessionStart //= [] |
    if (.hooks.SessionStart | map(select(.hooks[]?.command == $cmd)) | length) > 0
    then .
    else .hooks.SessionStart += [{"hooks": [{"type": "command", "command": $cmd}]}]
    end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

  # Add PostToolUse hook with Bash matcher (idempotent)
  jq --arg cmd "$HOOK_CMD" '
    .hooks //= {} |
    .hooks.PostToolUse //= [] |
    if (.hooks.PostToolUse | map(select(.hooks[]?.command == $cmd)) | length) > 0
    then .
    else .hooks.PostToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": $cmd}]}]
    end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

deregister_hooks() {
  [ -f "$SETTINGS" ] || return 0

  jq --arg cmd "$HOOK_CMD" '
    if .hooks then
      .hooks.SessionStart //= [] |
      .hooks.SessionStart = [.hooks.SessionStart[] | select(.hooks | all(.command != $cmd))] |
      .hooks.PostToolUse //= [] |
      .hooks.PostToolUse = [.hooks.PostToolUse[] | select(.hooks | all(.command != $cmd))] |
      # Clean up empty arrays
      if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end |
      if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end |
      if (.hooks | length) == 0 then del(.hooks) else . end
    else .
    end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

# --- Install ---

do_install() {
  check_prereqs

  echo "Installing claude-snapshot..."

  # Copy hook script
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$REPO_DIR/snapshot.sh" "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "  Copied snapshot hook to $HOOK_PATH"

  # Write repo location marker
  echo "$REPO_DIR" > "$MARKER"
  echo "  Repo path saved to $MARKER"

  # Register hooks in settings.json
  register_hooks
  echo "  Hooks registered in settings.json"

  # Init git repo if needed
  if [ ! -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" init
    git -C "$REPO_DIR" checkout -b main 2>/dev/null || true
    echo "  Initialized git repo"
  fi

  # Run first snapshot
  echo "  Running first snapshot..."
  bash "$HOOK_PATH" < /dev/null 2>/dev/null || true

  echo ""
  echo "Done! Your Claude Code config will auto-snapshot to:"
  echo "  $REPO_DIR"
  echo ""
  echo "Restart Claude Code to activate the hooks."
}

# --- Restore ---

do_restore() {
  check_prereqs

  echo "Restoring config from repo..."

  # Config files
  if [ -d "$REPO_DIR/config" ]; then
    for f in "$REPO_DIR"/config/*.json "$REPO_DIR"/config/*.md; do
      [ -f "$f" ] && cp "$f" "$CLAUDE_DIR/"
    done
    # Plugin metadata
    if [ -d "$REPO_DIR/config/plugins" ]; then
      mkdir -p "$CLAUDE_DIR/plugins"
      cp "$REPO_DIR"/config/plugins/*.json "$CLAUDE_DIR/plugins/" 2>/dev/null || true
    fi
    echo "  Restored config files"
  fi

  # Hooks
  if [ -d "$REPO_DIR/hooks" ] && ls "$REPO_DIR"/hooks/*.sh >/dev/null 2>&1; then
    mkdir -p "$CLAUDE_DIR/hooks"
    cp "$REPO_DIR"/hooks/*.sh "$CLAUDE_DIR/hooks/"
    chmod +x "$CLAUDE_DIR"/hooks/*.sh
    echo "  Restored hooks"
  fi

  # Commands
  if [ -d "$REPO_DIR/commands" ] && ls "$REPO_DIR"/commands/*.md >/dev/null 2>&1; then
    mkdir -p "$CLAUDE_DIR/commands"
    cp "$REPO_DIR"/commands/*.md "$CLAUDE_DIR/commands/"
    echo "  Restored commands"
  fi

  # Scripts
  if [ -d "$REPO_DIR/scripts" ] && ls "$REPO_DIR"/scripts/*.sh >/dev/null 2>&1; then
    mkdir -p "$CLAUDE_DIR/scripts"
    cp "$REPO_DIR"/scripts/*.sh "$CLAUDE_DIR/scripts/"
    chmod +x "$CLAUDE_DIR"/scripts/*.sh
    echo "  Restored scripts"
  fi

  # Agents
  if [ -d "$REPO_DIR/agents" ]; then
    mkdir -p "$CLAUDE_DIR/agents"
    rsync -a "$REPO_DIR/agents/" "$CLAUDE_DIR/agents/"
    echo "  Restored agents"
  fi

  # Re-register hooks
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$REPO_DIR/snapshot.sh" "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "$REPO_DIR" > "$MARKER"
  register_hooks
  echo "  Re-registered snapshot hooks"

  echo ""
  echo "Done! Config restored. Restart Claude Code to pick up changes."
}

# --- Uninstall ---

do_uninstall() {
  echo "Uninstalling claude-snapshot..."

  # Deregister hooks
  if [ -f "$SETTINGS" ]; then
    deregister_hooks
    echo "  Removed hooks from settings.json"
  fi

  # Remove hook file
  [ -f "$HOOK_PATH" ] && rm "$HOOK_PATH" && echo "  Deleted $HOOK_PATH"

  # Remove marker
  [ -f "$MARKER" ] && rm "$MARKER" && echo "  Deleted $MARKER"

  # Remove backup if exists
  [ -f "$SETTINGS.pre-snapshot-backup" ] && rm "$SETTINGS.pre-snapshot-backup"

  echo ""
  echo "Done! Your config repo is still at: $REPO_DIR"
}

# --- Main ---

case "${1:-}" in
  --restore)  do_restore ;;
  --uninstall) do_uninstall ;;
  --help|-h)
    echo "Usage: ./setup.sh [--restore|--uninstall|--help]"
    echo ""
    echo "  (no args)     Install: register hooks, run first snapshot"
    echo "  --restore     Restore config from this repo to ~/.claude/"
    echo "  --uninstall   Remove hooks and clean up"
    ;;
  "") do_install ;;
  *) die "Unknown option: $1. Use --help for usage." ;;
esac
