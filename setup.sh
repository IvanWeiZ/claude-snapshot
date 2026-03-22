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
HOOK_CMD="bash $CLAUDE_DIR/hooks/$HOOK_FILE"

# --- Helpers ---

die() { echo "Error: $1" >&2; exit 1; }

check_prereqs() {
  for cmd in git rsync jq; do
    command -v "$cmd" >/dev/null || die "$cmd is required but not installed"
  done
  [ -d "$CLAUDE_DIR" ] || die "$CLAUDE_DIR not found. Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
}

install_hook() {
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$REPO_DIR/snapshot.sh" "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "$REPO_DIR" > "$MARKER"
  register_hooks
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

  install_hook
  echo "  Hook installed and registered in settings.json"

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

  install_hook
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

# --- Status ---

do_status() {
  echo "claude-snapshot status"
  echo ""

  # Hook installed?
  if [ -f "$HOOK_PATH" ]; then
    echo "  Hook:   $HOOK_PATH (installed)"
  else
    echo "  Hook:   not installed"
  fi

  # Marker / repo path
  if [ -f "$MARKER" ]; then
    SAVED_REPO=$(cat "$MARKER")
    if [ -d "$SAVED_REPO/.git" ]; then
      COMMIT_COUNT=$(git -C "$SAVED_REPO" rev-list --count HEAD 2>/dev/null || echo "0")
      LAST_COMMIT=$(git -C "$SAVED_REPO" log -1 --format="%ar" 2>/dev/null || echo "never")
      echo "  Repo:   $SAVED_REPO ($COMMIT_COUNT commits, last: $LAST_COMMIT)"
    else
      echo "  Repo:   $SAVED_REPO (not a git repo)"
    fi
  else
    echo "  Repo:   not configured"
  fi

  # Hooks registered in settings.json?
  if [ -f "$SETTINGS" ] && jq -e ".hooks.SessionStart[]? | select(.hooks[]?.command == \"$HOOK_CMD\")" "$SETTINGS" > /dev/null 2>&1; then
    echo "  Hooks:  registered in settings.json"
  else
    echo "  Hooks:  not registered in settings.json"
  fi

  # Auto-push?
  if [ "${CLAUDE_SNAPSHOT_PUSH:-0}" = "1" ]; then
    echo "  Push:   enabled (CLAUDE_SNAPSHOT_PUSH=1)"
  else
    echo "  Push:   disabled (set CLAUDE_SNAPSHOT_PUSH=1 to enable)"
  fi

  # What's tracked
  echo ""
  echo "  Tracking:"
  for category in config hooks commands scripts agents skills memory; do
    DIR="$REPO_DIR/$category"
    if [ -d "$DIR" ]; then
      COUNT=$(find "$DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
      echo "    $category/ ($COUNT files)"
    fi
  done
}

# --- Diff ---

do_diff() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    die "No git repo at $REPO_DIR. Run ./setup.sh first."
  fi

  # Record HEAD before snapshot, then compare
  BEFORE=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "none")

  # Run snapshot to capture current live config
  if [ -f "$HOOK_PATH" ]; then
    bash "$HOOK_PATH" < /dev/null 2>/dev/null || true
  fi

  AFTER=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "none")

  if [ "$BEFORE" != "$AFTER" ]; then
    echo "Changes captured in new snapshot:"
    echo ""
    git -C "$REPO_DIR" log -1 --stat --format="" 2>/dev/null
  else
    echo "No changes since last snapshot."
  fi
}

# --- Log ---

do_log() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    die "No git repo at $REPO_DIR. Run ./setup.sh first."
  fi

  local count="${1:-10}"
  git -C "$REPO_DIR" log --oneline --format="%C(dim)%ar%C(reset)  %s" -n "$count" 2>/dev/null || echo "No commits yet."
}

# --- Main ---

case "${1:-}" in
  --restore)   do_restore ;;
  --uninstall) do_uninstall ;;
  --status)    do_status ;;
  --diff)      do_diff ;;
  --log)       do_log "${2:-}" ;;
  --help|-h)
    echo "Usage: ./setup.sh [OPTION]"
    echo ""
    echo "  (no args)     Install: register hooks, run first snapshot"
    echo "  --restore     Restore config from this repo to ~/.claude/"
    echo "  --uninstall   Remove hooks and clean up"
    echo "  --status      Show snapshot health and what's tracked"
    echo "  --diff        Show changes since last snapshot"
    echo "  --log [N]     Show last N snapshots (default: 10)"
    ;;
  "") do_install ;;
  *) die "Unknown option: $1. Use --help for usage." ;;
esac
