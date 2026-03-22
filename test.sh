#!/bin/bash
# Tests for claude-snapshot (setup.sh + snapshot.sh)
# Runs entirely in a sandbox — never touches real ~/.claude/
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Override HOME so everything targets the sandbox
export HOME="$SANDBOX"
CLAUDE_DIR="$SANDBOX/.claude"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# --- Setup sandbox ---
setup_sandbox() {
  rm -rf "$SANDBOX"/*
  mkdir -p "$CLAUDE_DIR"/{hooks,commands,scripts,plugins,agents/engineering,projects/-sandbox-myproject/memory,skills/my-skill}

  # Config files
  echo '{}' > "$CLAUDE_DIR/settings.json"
  echo "# My Instructions" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{"test": true}' > "$CLAUDE_DIR/settings.local.json"

  # Plugin metadata
  echo '[]' > "$CLAUDE_DIR/plugins/installed_plugins.json"
  echo '[]' > "$CLAUDE_DIR/plugins/known_marketplaces.json"

  # Sample hook, command, script
  echo '#!/bin/bash' > "$CLAUDE_DIR/hooks/my-hook.sh"
  chmod +x "$CLAUDE_DIR/hooks/my-hook.sh"
  echo "# My command" > "$CLAUDE_DIR/commands/my-cmd.md"
  echo '#!/bin/bash' > "$CLAUDE_DIR/scripts/my-script.sh"
  chmod +x "$CLAUDE_DIR/scripts/my-script.sh"

  # Agent
  echo "# My Agent" > "$CLAUDE_DIR/agents/engineering/coder.md"

  # Skill
  echo "# My Skill" > "$CLAUDE_DIR/skills/my-skill/README.md"

  # Memory
  echo "# Memory note" > "$CLAUDE_DIR/projects/-sandbox-myproject/memory/note.md"

  # Clone the repo to a sandbox location
  REPO="$SANDBOX/claude-snapshot"
  mkdir -p "$REPO"
  cp "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/snapshot.sh" "$REPO/"
  chmod +x "$REPO/setup.sh" "$REPO/snapshot.sh"
}

echo "=== claude-snapshot tests ==="
echo "Sandbox: $SANDBOX"
echo ""

# --- Test 1: Setup installs correctly ---
echo "Test 1: setup.sh install"
setup_sandbox
cd "$REPO"
bash "$REPO/setup.sh" > /dev/null 2>&1

# Check hook file copied
if [ -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ]; then
  pass "Hook file installed"
else
  fail "Hook file not found at $CLAUDE_DIR/hooks/claude-snapshot.sh"
fi

# Check marker file
if [ -f "$CLAUDE_DIR/.snapshot-repo" ] && [ "$(cat "$CLAUDE_DIR/.snapshot-repo")" = "$REPO" ]; then
  pass "Marker file created with correct path"
else
  fail "Marker file missing or wrong"
fi

# Check hooks registered in settings.json
if jq -e '.hooks.SessionStart' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1; then
  pass "SessionStart hook registered"
else
  fail "SessionStart hook not in settings.json"
fi

if jq -e '.hooks.PostToolUse' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1; then
  pass "PostToolUse hook registered"
else
  fail "PostToolUse hook not in settings.json"
fi

# Check first snapshot committed
if [ -d "$REPO/.git" ] && git -C "$REPO" log --oneline -1 > /dev/null 2>&1; then
  pass "First snapshot committed"
else
  fail "No git commit after setup"
fi

# --- Test 2: Snapshot captures all categories ---
echo ""
echo "Test 2: Snapshot captures all categories"

# Check config
if [ -f "$REPO/config/CLAUDE.md" ] && [ -f "$REPO/config/settings.json" ]; then
  pass "Config files captured"
else
  fail "Config files missing"
fi

# Check hooks
if [ -f "$REPO/hooks/my-hook.sh" ]; then
  pass "Hooks captured"
else
  fail "Hooks not captured"
fi

# Check commands
if [ -f "$REPO/commands/my-cmd.md" ]; then
  pass "Commands captured"
else
  fail "Commands not captured"
fi

# Check scripts
if [ -f "$REPO/scripts/my-script.sh" ]; then
  pass "Scripts captured"
else
  fail "Scripts not captured"
fi

# Check agents
if [ -f "$REPO/agents/engineering/coder.md" ]; then
  pass "Agents captured"
else
  fail "Agents not captured"
fi

# Check skills
if [ -f "$REPO/skills/my-skill/README.md" ]; then
  pass "Skills captured"
else
  fail "Skills not captured"
fi

# Check memory
if [ -f "$REPO/memory/myproject/note.md" ]; then
  pass "Memory captured with correct project name"
else
  fail "Memory not captured (looking for memory/myproject/note.md)"
fi

# Check plugin metadata
if [ -f "$REPO/config/plugins/installed_plugins.json" ]; then
  pass "Plugin metadata captured"
else
  fail "Plugin metadata not captured"
fi

# --- Test 3: Snapshot detects changes ---
echo ""
echo "Test 3: Snapshot detects config changes"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo "# added line" >> "$CLAUDE_DIR/CLAUDE.md"
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
if [ "$BEFORE" != "$AFTER" ]; then
  pass "New commit after config change"
else
  fail "No commit after config change"
fi

# --- Test 4: No changes = no commit ---
echo ""
echo "Test 4: Idempotency — no changes, no commit"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
if [ "$BEFORE" = "$AFTER" ]; then
  pass "No commit when nothing changed"
else
  fail "Empty commit created"
fi

# --- Test 5: PostToolUse filter ---
echo ""
echo "Test 5: PostToolUse only triggers on plugin commands"

# Plugin command should trigger
echo "# plugin-test" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo '{"tool_input":{"command":"claude plugin install test@test"}}' | bash "$REPO/snapshot.sh" 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
if [ "$BEFORE" != "$AFTER" ]; then
  pass "Plugin install triggers commit"
else
  fail "Plugin install did not trigger commit"
fi

# Non-plugin command should NOT trigger
echo "# non-plugin-test" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo '{"tool_input":{"command":"ls -la"}}' | bash "$REPO/snapshot.sh" 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
if [ "$BEFORE" = "$AFTER" ]; then
  pass "Non-plugin command ignored"
else
  fail "Non-plugin command triggered commit"
fi
# Clean up the uncommitted change
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null

# --- Test 6: Idempotent setup (no duplicate hooks) ---
echo ""
echo "Test 6: Running setup twice doesn't duplicate hooks"
bash "$REPO/setup.sh" > /dev/null 2>&1
SESSION_COUNT=$(jq '.hooks.SessionStart | length' "$CLAUDE_DIR/settings.json")
POSTTOOL_COUNT=$(jq '.hooks.PostToolUse | length' "$CLAUDE_DIR/settings.json")
if [ "$SESSION_COUNT" = "1" ] && [ "$POSTTOOL_COUNT" = "1" ]; then
  pass "No duplicate hook entries"
else
  fail "Duplicate hooks: SessionStart=$SESSION_COUNT PostToolUse=$POSTTOOL_COUNT"
fi

# --- Test 7: Restore flow ---
echo ""
echo "Test 7: Restore from repo to empty ~/.claude/"

# Save current repo state, wipe claude dir, restore
REPO_BACKUP="$SANDBOX/repo-backup"
cp -r "$REPO" "$REPO_BACKUP"
rm -rf "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR"
echo '{}' > "$CLAUDE_DIR/settings.json"

bash "$REPO/setup.sh" --restore > /dev/null 2>&1

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  pass "Config restored"
else
  fail "Config not restored"
fi

if [ -f "$CLAUDE_DIR/hooks/my-hook.sh" ]; then
  pass "Hooks restored"
else
  fail "Hooks not restored"
fi

if [ -f "$CLAUDE_DIR/commands/my-cmd.md" ]; then
  pass "Commands restored"
else
  fail "Commands not restored"
fi

if [ -f "$CLAUDE_DIR/agents/engineering/coder.md" ]; then
  pass "Agents restored"
else
  fail "Agents not restored"
fi

if [ -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ]; then
  pass "Snapshot hook re-registered after restore"
else
  fail "Snapshot hook not re-registered"
fi

# --- Test 8: Uninstall ---
echo ""
echo "Test 8: Uninstall removes hooks cleanly"
bash "$REPO/setup.sh" --uninstall > /dev/null 2>&1

if [ ! -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ]; then
  pass "Hook file removed"
else
  fail "Hook file still exists"
fi

if [ ! -f "$CLAUDE_DIR/.snapshot-repo" ]; then
  pass "Marker file removed"
else
  fail "Marker file still exists"
fi

# Check hooks removed from settings.json
if ! jq -e '.hooks.SessionStart' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1; then
  pass "SessionStart hook removed from settings.json"
else
  fail "SessionStart hook still in settings.json"
fi

# Repo still exists
if [ -d "$REPO/.git" ]; then
  pass "Config repo preserved after uninstall"
else
  fail "Config repo was deleted"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
