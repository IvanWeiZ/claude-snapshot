#!/bin/bash
# claude-snapshot: Auto-snapshot ~/.claude/ config to git
# Triggered by: SessionStart, PostToolUse:Bash (plugin install/uninstall only)
# https://github.com/IvanWeiZ/claude-snapshot

CLAUDE_DIR="$HOME/.claude"
REPO=$(cat "$CLAUDE_DIR/.snapshot-repo" 2>/dev/null)
[ -d "$REPO/.git" ] || exit 0

# PostToolUse filter: only trigger on plugin install/uninstall
COMMAND=$(jq -r '.tool_input.command // ""' 2>/dev/null)
if [ -n "$COMMAND" ]; then
  echo "$COMMAND" | grep -qE 'claude plugin.*(install|uninstall)' || exit 0
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
  [ -f "$CLAUDE_DIR/plugins/$f" ] && cp "$CLAUDE_DIR/plugins/$f" "$REPO/config/plugins/"
done

# Hooks
[ -d "$CLAUDE_DIR/hooks" ] && {
  mkdir -p "$REPO/hooks"
  rsync -a --delete --include='*.sh' --exclude='*' "$CLAUDE_DIR/hooks/" "$REPO/hooks/" 2>/dev/null
}

# Commands
[ -d "$CLAUDE_DIR/commands" ] && {
  mkdir -p "$REPO/commands"
  rsync -a --delete --include='*.md' --exclude='*' "$CLAUDE_DIR/commands/" "$REPO/commands/" 2>/dev/null
}

# Scripts
[ -d "$CLAUDE_DIR/scripts" ] && {
  mkdir -p "$REPO/scripts"
  rsync -a --delete --include='*.sh' --exclude='*' "$CLAUDE_DIR/scripts/" "$REPO/scripts/" 2>/dev/null
}

# Skills
[ -d "$CLAUDE_DIR/skills" ] && rsync -aL "$CLAUDE_DIR/skills/" "$REPO/skills/" 2>/dev/null
[ -d "$HOME/.agents/skills" ] && rsync -aL "$HOME/.agents/skills/" "$REPO/skills/" 2>/dev/null

# Agents
[ -d "$CLAUDE_DIR/agents" ] && {
  mkdir -p "$REPO/agents"
  rsync -a --delete "$CLAUDE_DIR/agents/" "$REPO/agents/" 2>/dev/null
}

# Memory (portable path extraction — no hardcoded username)
for memdir in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$memdir" ] || continue
  raw=$(basename "$(dirname "$memdir")")
  # Extract last meaningful segment as project name
  # -Users-alice-Documents-projects-foo → foo
  project=$(echo "$raw" | rev | cut -d'-' -f1 | rev)
  [ -z "$project" ] && project="unknown"
  mkdir -p "$REPO/memory/$project"
  rsync -a "$memdir/" "$REPO/memory/$project/" 2>/dev/null
done

# --- Commit if changed ---
cd "$REPO"
git add -A

if ! git diff --cached --quiet 2>/dev/null; then
  CHANGES=$(git diff --cached --stat | tail -1)
  MSG="auto: sync config ($CHANGES)"
  if [ -n "$COMMAND" ]; then
    PLUGIN=$(echo "$COMMAND" | grep -oE '[a-z_-]+@[a-z_-]+' | head -1)
    ACTION=$(echo "$COMMAND" | grep -oE 'install|uninstall' | head -1)
    [ -n "$ACTION" ] && MSG="auto: ${ACTION} ${PLUGIN} ($CHANGES)"
  fi
  git commit -m "$MSG" --no-verify 2>/dev/null
fi

exit 0
