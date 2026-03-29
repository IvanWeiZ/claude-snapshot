#!/bin/bash
# claude-snapshot: Auto-snapshot ~/.claude/ config to git
# Triggered by: SessionStart, PostToolUse:Bash (plugin install/uninstall only)
# https://github.com/IvanWeiZ/claude-snapshot

CLAUDE_DIR="$HOME/.claude"
REPO=$(cat "$CLAUDE_DIR/.snapshot-repo" 2>/dev/null)
[ -d "$REPO/.git" ] || exit 0

# PostToolUse filter: skip jq fork when no stdin (SessionStart path)
COMMAND="" ACTION="" PLUGIN=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null)
  if [ -n "$INPUT" ]; then
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    if [ -n "$COMMAND" ]; then
      echo "$COMMAND" | grep -qE 'claude plugin.*(install|uninstall)' || exit 0
      ACTION=$(echo "$COMMAND" | grep -oE 'install|uninstall' | head -1)
      PLUGIN=$(echo "$COMMAND" | grep -oE '[a-z_-]+@[a-z_-]+' | head -1)
    fi
  fi
fi

# --- Auto-sync: pull repo → local for missing files (SessionStart only) ---
if [ -z "$COMMAND" ]; then
  # Skills: fill in any files that exist in repo but not locally
  [ -d "$REPO/skills" ] && rsync -a --ignore-existing "$REPO/skills/" "$CLAUDE_DIR/skills/" 2>/dev/null
  # Commands
  [ -d "$REPO/commands" ] && rsync -a --ignore-existing --include='*.md' --exclude='*' "$REPO/commands/" "$CLAUDE_DIR/commands/" 2>/dev/null
  # Hooks
  [ -d "$REPO/hooks" ] && rsync -a --ignore-existing --include='*.sh' --exclude='*' "$REPO/hooks/" "$CLAUDE_DIR/hooks/" 2>/dev/null
  # Agents
  [ -d "$REPO/agents" ] && rsync -a --ignore-existing "$REPO/agents/" "$CLAUDE_DIR/agents/" 2>/dev/null
fi

# --- Snapshot ---

# Config files (settings + all .md files in root)
mkdir -p "$REPO/config"
for f in settings.json settings.local.json keybindings.json; do
  [ -f "$CLAUDE_DIR/$f" ] && cp "$CLAUDE_DIR/$f" "$REPO/config/"
done
for f in "$CLAUDE_DIR"/*.md; do
  [ -f "$f" ] && cp "$f" "$REPO/config/"
done

# Plugin metadata
mkdir -p "$REPO/config/plugins"
for f in installed_plugins.json known_marketplaces.json blocklist.json; do
  [ -f "$CLAUDE_DIR/plugins/$f" ] || continue
  if [ "$f" = "known_marketplaces.json" ] && command -v jq &>/dev/null; then
    jq 'del(.[].lastUpdated)' "$CLAUDE_DIR/plugins/$f" > "$REPO/config/plugins/$f"
  elif [ "$f" = "blocklist.json" ] && command -v jq &>/dev/null; then
    jq 'del(.fetchedAt)' "$CLAUDE_DIR/plugins/$f" > "$REPO/config/plugins/$f"
  else
    cp "$CLAUDE_DIR/plugins/$f" "$REPO/config/plugins/"
  fi
done

# Hooks (NO --delete: never remove repo files when local is missing)
[ -d "$CLAUDE_DIR/hooks" ] && {
  mkdir -p "$REPO/hooks"
  rsync -a --include='*.sh' --exclude='*' "$CLAUDE_DIR/hooks/" "$REPO/hooks/" 2>/dev/null
}

# Commands (NO --delete: never remove repo files when local is missing)
[ -d "$CLAUDE_DIR/commands" ] && {
  mkdir -p "$REPO/commands"
  rsync -a --include='*.md' --exclude='*' "$CLAUDE_DIR/commands/" "$REPO/commands/" 2>/dev/null
}

# Scripts (NO --delete: never remove repo files when local is missing)
[ -d "$CLAUDE_DIR/scripts" ] && {
  mkdir -p "$REPO/scripts"
  rsync -a --include='*.sh' --exclude='*' "$CLAUDE_DIR/scripts/" "$REPO/scripts/" 2>/dev/null
}

# Skills (merged from two sources, no --delete since both write to same dest)
# Exclude nested settings.local.json (local permission files, not portable)
[ -d "$CLAUDE_DIR/skills" ] && rsync -aL --exclude='settings.local.json' "$CLAUDE_DIR/skills/" "$REPO/skills/" 2>/dev/null
[ -d "$HOME/.agents/skills" ] && rsync -aL --exclude='settings.local.json' "$HOME/.agents/skills/" "$REPO/skills/" 2>/dev/null

# Agents (NO --delete: never remove repo files when local is missing)
[ -d "$CLAUDE_DIR/agents" ] && {
  mkdir -p "$REPO/agents"
  rsync -a "$CLAUDE_DIR/agents/" "$REPO/agents/" 2>/dev/null
}

# Memory (portable path extraction)
for memdir in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$memdir" ] || continue
  raw=$(basename "$(dirname "$memdir")")
  # -Users-alice-Documents-projects-foo → foo
  project=$(echo "$raw" | rev | cut -d'-' -f1 | rev)
  [ -z "$project" ] && project="unknown"
  mkdir -p "$REPO/memory/$project"
  rsync -a "$memdir/" "$REPO/memory/$project/" 2>/dev/null
done

# --- Secret detection (single grep pass, warn only) ---
for f in "$REPO"/config/settings.json "$REPO"/config/settings.local.json; do
  [ -f "$f" ] || continue
  if grep -qEi '"(api[_-]?key|secret[_-]?key|token|password|credential)"|(sk-ant-|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{30,}|AKIA[A-Z0-9]{16})' "$f" 2>/dev/null; then
    echo "[claude-snapshot] Warning: $(basename "$f") may contain secrets. Review before pushing." >&2
  fi
done

# --- Commit if changed ---
cd "$REPO"
git add -A

if ! git diff --cached --quiet 2>/dev/null; then
  # Build meaningful commit message from changed files
  CHANGED_FILES=$(git diff --cached --name-only)
  PARTS=()
  echo "$CHANGED_FILES" | grep -q '^config/settings' && PARTS+=("settings") || true
  echo "$CHANGED_FILES" | grep -q '^config/CLAUDE' && PARTS+=("CLAUDE.md") || true
  echo "$CHANGED_FILES" | grep -q '^commands/' && PARTS+=("commands") || true
  echo "$CHANGED_FILES" | grep -q '^skills/' && PARTS+=("skills") || true
  echo "$CHANGED_FILES" | grep -q '^hooks/' && PARTS+=("hooks") || true
  echo "$CHANGED_FILES" | grep -q '^agents/' && PARTS+=("agents") || true
  echo "$CHANGED_FILES" | grep -q '^memory/' && PARTS+=("memory") || true
  echo "$CHANGED_FILES" | grep -q '^config/plugins/installed' && PARTS+=("plugins") || true
  echo "$CHANGED_FILES" | grep -q '^scripts/' && PARTS+=("scripts") || true

  if [ -n "$ACTION" ]; then
    MSG="auto: ${ACTION} ${PLUGIN}"
  elif [ ${#PARTS[@]} -gt 0 ]; then
    MSG="auto: update $(IFS=', '; echo "${PARTS[*]}")"
  else
    MSG="auto: sync config"
  fi
  git commit -m "$MSG" --no-verify 2>/dev/null

  # Auto-push if enabled
  if [ "${CLAUDE_SNAPSHOT_PUSH:-0}" = "1" ] && git remote get-url origin &>/dev/null; then
    git push --quiet 2>/dev/null || true
  fi
fi

exit 0
