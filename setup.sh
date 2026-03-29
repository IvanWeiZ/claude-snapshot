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

  # Config files (skip plugin metadata — plugins are reinstalled below)
  if [ -d "$REPO_DIR/config" ]; then
    for f in "$REPO_DIR"/config/*.json "$REPO_DIR"/config/*.md; do
      [ -f "$f" ] && cp "$f" "$CLAUDE_DIR/"
    done
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

  # Skills (recursive — includes nested .claude/skills/ dirs)
  if [ -d "$REPO_DIR/skills" ]; then
    mkdir -p "$CLAUDE_DIR/skills"
    rsync -a "$REPO_DIR/skills/" "$CLAUDE_DIR/skills/"
    echo "  Restored skills"
  fi

  # Agents
  if [ -d "$REPO_DIR/agents" ]; then
    mkdir -p "$CLAUDE_DIR/agents"
    rsync -a "$REPO_DIR/agents/" "$CLAUDE_DIR/agents/"
    echo "  Restored agents"
  fi

  # Memory (reverse the portable path mapping from snapshot.sh)
  if [ -d "$REPO_DIR/memory" ]; then
    for memdir in "$REPO_DIR"/memory/*/; do
      [ -d "$memdir" ] || continue
      project=$(basename "$memdir")
      # Find the matching project dir in ~/.claude/projects/
      target=$(find "$CLAUDE_DIR/projects" -maxdepth 1 -type d -name "*-$project" 2>/dev/null | head -1)
      if [ -n "$target" ]; then
        mkdir -p "$target/memory"
        rsync -a "$memdir" "$target/memory/"
      fi
    done
    echo "  Restored memory"
  fi

  install_hook
  echo "  Re-registered snapshot hooks"

  # Reinstall plugins if metadata exists
  PLUGINS_META="$REPO_DIR/config/plugins/installed_plugins.json"
  MARKETS_META="$REPO_DIR/config/plugins/known_marketplaces.json"
  if [ -f "$PLUGINS_META" ] && command -v claude >/dev/null 2>&1; then
    echo ""
    echo "  Reinstalling plugins..."

    # Add marketplaces first
    if [ -f "$MARKETS_META" ]; then
      for repo in $(jq -r '.[] | .source.repo // empty' "$MARKETS_META" 2>/dev/null); do
        echo "    Marketplace: $repo"
        claude plugin marketplace add "$repo" 2>/dev/null || true
      done
    fi

    # Install each plugin
    for plugin in $(jq -r '.plugins | keys[]' "$PLUGINS_META" 2>/dev/null); do
      echo "    Installing: $plugin"
      claude plugin install "$plugin" 2>/dev/null || echo "    (failed or already installed)"
    done
    echo "  Plugins restored"
  elif [ -f "$PLUGINS_META" ]; then
    echo ""
    echo "  Note: 'claude' CLI not found. Install plugins manually:"
    for plugin in $(jq -r '.plugins | keys[]' "$PLUGINS_META" 2>/dev/null); do
      echo "    claude plugin install $plugin"
    done
  fi

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

# --- Sync (pull missing files from repo to local) ---

do_sync() {
  check_prereqs

  echo "Syncing repo → local ~/.claude/ ..."

  # Skills
  if [ -d "$REPO_DIR/skills" ]; then
    mkdir -p "$CLAUDE_DIR/skills"
    rsync -a "$REPO_DIR/skills/" "$CLAUDE_DIR/skills/"
    echo "  Synced skills/"
  fi

  # Commands
  if [ -d "$REPO_DIR/commands" ]; then
    mkdir -p "$CLAUDE_DIR/commands"
    rsync -a --include='*.md' --exclude='*' "$REPO_DIR/commands/" "$CLAUDE_DIR/commands/"
    echo "  Synced commands/"
  fi

  # Hooks
  if [ -d "$REPO_DIR/hooks" ]; then
    mkdir -p "$CLAUDE_DIR/hooks"
    rsync -a --include='*.sh' --exclude='*' "$REPO_DIR/hooks/" "$CLAUDE_DIR/hooks/"
    chmod +x "$CLAUDE_DIR"/hooks/*.sh 2>/dev/null
    echo "  Synced hooks/"
  fi

  # Agents
  if [ -d "$REPO_DIR/agents" ]; then
    mkdir -p "$CLAUDE_DIR/agents"
    rsync -a "$REPO_DIR/agents/" "$CLAUDE_DIR/agents/"
    echo "  Synced agents/"
  fi

  # Config files
  if [ -d "$REPO_DIR/config" ]; then
    for f in "$REPO_DIR"/config/*.md; do
      [ -f "$f" ] && cp "$f" "$CLAUDE_DIR/"
    done
    echo "  Synced config/"
  fi

  echo ""
  echo "Done. Local ~/.claude/ is in sync with repo."
}

case "${1:-}" in
  --restore)   do_restore ;;
  --sync)      do_sync ;;
  --uninstall) do_uninstall ;;
  --status)    do_status ;;
  --diff)      do_diff ;;
  --log)       do_log "${2:-}" ;;
  --help|-h)
    echo "Usage: ./setup.sh [OPTION]"
    echo ""
    echo "  (no args)     Install: register hooks, run first snapshot"
    echo "  --restore     Restore config from this repo to ~/.claude/"
    echo "  --sync        Pull missing files from repo to local (non-destructive)"
    echo "  --uninstall   Remove hooks and clean up"
    echo "  --status      Show snapshot health and what's tracked"
    echo "  --diff        Show changes since last snapshot"
    echo "  --log [N]     Show last N snapshots (default: 10)"
    ;;
  "") do_install ;;
  *) die "Unknown option: $1. Use --help for usage." ;;
esac
