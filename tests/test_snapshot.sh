#!/bin/bash
# Tests: snapshot.sh capture, change detection, PostToolUse filtering
source "$(dirname "$0")/helpers.sh"

echo "=== Snapshot Tests ==="

setup_sandbox
install_snapshot

# --- Captures all categories ---
echo "Test: Captures all categories"
[ -f "$REPO/config/CLAUDE.md" ] && [ -f "$REPO/config/settings.json" ] && pass "Config files" || fail "Config files missing"
[ -f "$REPO/config/settings.local.json" ] && pass "settings.local.json" || fail "settings.local.json missing"
[ -f "$REPO/hooks/my-hook.sh" ] && pass "Hooks" || fail "Hooks missing"
[ -f "$REPO/commands/my-cmd.md" ] && pass "Commands" || fail "Commands missing"
[ -f "$REPO/scripts/my-script.sh" ] && pass "Scripts" || fail "Scripts missing"
[ -f "$REPO/agents/engineering/coder.md" ] && pass "Agents" || fail "Agents missing"
[ -f "$REPO/skills/my-skill/README.md" ] && pass "Skills" || fail "Skills missing"
[ -f "$REPO/memory/myproject/note.md" ] && pass "Memory with project name" || fail "Memory missing"
[ -f "$REPO/config/plugins/installed_plugins.json" ] && pass "Plugin metadata" || fail "Plugin metadata missing"

# --- Detects changes ---
echo ""
echo "Test: Detects config changes"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo "# new line" >> "$CLAUDE_DIR/CLAUDE.md"
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" != "$AFTER" ] && pass "New commit after change" || fail "No commit after change"

# --- Idempotent (no changes = no commit) ---
echo ""
echo "Test: No changes = no commit"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" = "$AFTER" ] && pass "No empty commit" || fail "Empty commit created"

# --- PostToolUse: plugin install triggers ---
echo ""
echo "Test: PostToolUse plugin install triggers"
echo "# pt-test" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo '{"tool_input":{"command":"claude plugin install test@test"}}' | bash "$REPO/snapshot.sh" 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" != "$AFTER" ] && pass "Plugin install triggers commit" || fail "Plugin install didn't trigger"

# --- PostToolUse: plugin uninstall triggers ---
echo ""
echo "Test: PostToolUse plugin uninstall triggers"
echo "# pt-uninstall" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo '{"tool_input":{"command":"claude plugin uninstall test@test"}}' | bash "$REPO/snapshot.sh" 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" != "$AFTER" ] && pass "Plugin uninstall triggers commit" || fail "Plugin uninstall didn't trigger"

# --- PostToolUse: non-plugin command ignored ---
echo ""
echo "Test: Non-plugin commands ignored"
echo "# ignored" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
echo '{"tool_input":{"command":"ls -la"}}' | bash "$REPO/snapshot.sh" 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" = "$AFTER" ] && pass "Non-plugin command ignored" || fail "Non-plugin triggered commit"

# Clean up uncommitted change
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null

# --- Commit message format ---
echo ""
echo "Test: Commit message format"
echo "# msg-test" >> "$CLAUDE_DIR/CLAUDE.md"
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
LAST_MSG=$(git -C "$REPO" log -1 --format="%s")
echo "$LAST_MSG" | grep -q "^auto: " && pass "Default commit message format" || fail "Bad message: $LAST_MSG"

echo "# plugin-msg" >> "$CLAUDE_DIR/CLAUDE.md"
echo '{"tool_input":{"command":"claude plugin install foo@bar"}}' | bash "$REPO/snapshot.sh" 2>/dev/null
LAST_MSG=$(git -C "$REPO" log -1 --format="%s")
echo "$LAST_MSG" | grep -q "auto: install foo@bar" && pass "Plugin commit message format" || fail "Bad plugin message: $LAST_MSG"

# --- New file detection ---
echo ""
echo "Test: Detects new files"
echo "# New command" > "$CLAUDE_DIR/commands/new-cmd.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" != "$AFTER" ] && [ -f "$REPO/commands/new-cmd.md" ] && pass "New file captured" || fail "New file not captured"

# --- Deleted file detection ---
echo ""
echo "Test: Detects deleted files"
rm "$CLAUDE_DIR/commands/new-cmd.md"
BEFORE=$(git -C "$REPO" rev-parse HEAD)
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REPO" rev-parse HEAD)
[ "$BEFORE" != "$AFTER" ] && [ ! -f "$REPO/commands/new-cmd.md" ] && pass "Deleted file removed from repo" || fail "Deleted file still in repo"

# --- Multiple .md files in root ---
echo ""
echo "Test: Captures all .md files from root"
echo "# Custom doc" > "$CLAUDE_DIR/CUSTOM.md"
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
[ -f "$REPO/config/CUSTOM.md" ] && pass "Custom .md file captured" || fail "Custom .md not captured"

# --- Missing repo marker ---
echo ""
echo "Test: Exits cleanly if marker missing"
rm -f "$CLAUDE_DIR/.snapshot-repo"
EXIT_CODE=0
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null || EXIT_CODE=$?
[ "$EXIT_CODE" = "0" ] && pass "Clean exit without marker" || fail "Non-zero exit without marker"

results
