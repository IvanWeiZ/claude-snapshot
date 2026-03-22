#!/bin/bash
# Tests: --restore flow
source "$(dirname "$0")/helpers.sh"

echo "=== Restore Tests ==="

setup_sandbox
install_snapshot

# --- Full restore to empty ~/.claude/ ---
echo "Test: Full restore to empty ~/.claude/"
reset_claude_dir

bash "$REPO/setup.sh" --restore > /dev/null 2>&1

[ -f "$CLAUDE_DIR/CLAUDE.md" ] && pass "Config restored" || fail "Config not restored"
[ -f "$CLAUDE_DIR/settings.local.json" ] && pass "settings.local.json restored" || fail "settings.local.json missing"
[ -f "$CLAUDE_DIR/hooks/my-hook.sh" ] && pass "Hooks restored" || fail "Hooks not restored"
[ -f "$CLAUDE_DIR/commands/my-cmd.md" ] && pass "Commands restored" || fail "Commands not restored"
[ -f "$CLAUDE_DIR/scripts/my-script.sh" ] && pass "Scripts restored" || fail "Scripts not restored"
[ -f "$CLAUDE_DIR/agents/engineering/coder.md" ] && pass "Agents restored" || fail "Agents not restored"

# --- Snapshot hook re-registered ---
echo ""
echo "Test: Snapshot hook re-registered after restore"
[ -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ] && pass "Snapshot hook re-installed" || fail "Snapshot hook missing"
[ -f "$CLAUDE_DIR/.snapshot-repo" ] && pass "Marker re-created" || fail "Marker missing"
jq -e '.hooks.SessionStart' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1 && pass "Hooks re-registered" || fail "Hooks not re-registered"

# --- Plugin restore: attempts install or shows instructions ---
echo ""
echo "Test: Plugin restore shows instructions when CLI missing"
reset_claude_dir
# Hide claude CLI to force instruction-only path (no network calls)
RESTORE_OUTPUT=$(PATH="/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v jq)"):$(dirname "$(command -v rsync)"):$(dirname "$(command -v git)")" bash "$REPO/setup.sh" --restore 2>&1)
echo "$RESTORE_OUTPUT" | grep -q "test-plugin@test-market" && pass "Plugin install instructions shown" || fail "No plugin mention in restore output"

# --- Restore with no config dir (graceful) ---
echo ""
echo "Test: Restore handles missing categories gracefully"
rm -rf "$REPO/commands" "$REPO/scripts" "$REPO/agents"
reset_claude_dir
EXIT_CODE=0
bash "$REPO/setup.sh" --restore > /dev/null 2>&1 || EXIT_CODE=$?
[ "$EXIT_CODE" = "0" ] && pass "Restore succeeds with missing categories" || fail "Restore failed with missing categories"

results
