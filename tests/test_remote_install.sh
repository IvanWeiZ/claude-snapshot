#!/bin/bash
# Tests: Remote installer simulation
source "$(dirname "$0")/helpers.sh"

echo "=== Remote Install Tests ==="

# --- Simulated remote install ---
echo "Test: Remote install flow"
reset_claude_dir
mkdir -p "$CLAUDE_DIR"/{hooks,plugins}
echo "# Test" > "$CLAUDE_DIR/CLAUDE.md"
echo '[]' > "$CLAUDE_DIR/plugins/installed_plugins.json"

INSTALL_DIR="$SANDBOX/claude-snapshot-remote"
copy_project_files "$INSTALL_DIR"
bash "$INSTALL_DIR/setup.sh" > /dev/null 2>&1

[ -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ] && pass "Hook installed" || fail "Hook not installed"
[ "$(cat "$CLAUDE_DIR/.snapshot-repo")" = "$INSTALL_DIR" ] && pass "Marker points to install dir" || fail "Marker wrong"
[ -d "$INSTALL_DIR/.git" ] && git -C "$INSTALL_DIR" log --oneline -1 > /dev/null 2>&1 && pass "First snapshot committed" || fail "No initial commit"

# --- Remote install to custom dir ---
echo ""
echo "Test: Install to custom directory"
reset_claude_dir
mkdir -p "$CLAUDE_DIR"/{hooks,plugins}
echo "# Custom dir test" > "$CLAUDE_DIR/CLAUDE.md"

CUSTOM_DIR="$SANDBOX/my-custom-config"
copy_project_files "$CUSTOM_DIR"
bash "$CUSTOM_DIR/setup.sh" > /dev/null 2>&1

[ "$(cat "$CLAUDE_DIR/.snapshot-repo")" = "$CUSTOM_DIR" ] && pass "Custom dir works" || fail "Custom dir marker wrong"
[ -f "$CUSTOM_DIR/config/CLAUDE.md" ] && pass "Snapshot to custom dir" || fail "Snapshot missing in custom dir"

results
