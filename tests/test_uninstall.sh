#!/bin/bash
# Tests: --uninstall flow
source "$(dirname "$0")/helpers.sh"

echo "=== Uninstall Tests ==="

setup_sandbox
install_snapshot

# --- Clean uninstall ---
echo "Test: Uninstall removes hooks cleanly"
bash "$REPO/setup.sh" --uninstall > /dev/null 2>&1

[ ! -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ] && pass "Hook file removed" || fail "Hook file still exists"
[ ! -f "$CLAUDE_DIR/.snapshot-repo" ] && pass "Marker file removed" || fail "Marker still exists"
! jq -e '.hooks.SessionStart' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1 && pass "SessionStart hook removed" || fail "SessionStart still in settings"
! jq -e '.hooks.PostToolUse' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1 && pass "PostToolUse hook removed" || fail "PostToolUse still in settings"

# --- Repo preserved ---
echo ""
echo "Test: Config repo preserved after uninstall"
[ -d "$REPO/.git" ] && pass "Repo still exists" || fail "Repo deleted"
COMMIT_COUNT=$(git -C "$REPO" rev-list --count HEAD 2>/dev/null)
[ "$COMMIT_COUNT" -gt 0 ] && pass "Commits preserved ($COMMIT_COUNT)" || fail "Commits lost"

# --- Other hooks preserved ---
echo ""
echo "Test: Other hooks not affected by uninstall"
setup_sandbox
cat > "$CLAUDE_DIR/settings.json" << 'JSONEOF'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo keep-me"}]}]}}
JSONEOF
install_snapshot

# Verify both exist before uninstall
TOTAL_BEFORE=$(jq '.hooks.SessionStart | length' "$CLAUDE_DIR/settings.json")
bash "$REPO/setup.sh" --uninstall > /dev/null 2>&1
REMAINING=$(jq '.hooks.SessionStart | length' "$CLAUDE_DIR/settings.json")
[ "$REMAINING" = "1" ] && pass "Other hooks preserved" || fail "Other hooks affected (remaining=$REMAINING, was=$TOTAL_BEFORE)"

# Check it's the right one
KEPT=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$CLAUDE_DIR/settings.json")
[ "$KEPT" = "echo keep-me" ] && pass "Correct hook preserved" || fail "Wrong hook kept: $KEPT"

# --- Double uninstall is safe ---
echo ""
echo "Test: Double uninstall is safe"
EXIT_CODE=0
bash "$REPO/setup.sh" --uninstall > /dev/null 2>&1 || EXIT_CODE=$?
[ "$EXIT_CODE" = "0" ] && pass "Double uninstall doesn't error" || fail "Double uninstall failed"

results
