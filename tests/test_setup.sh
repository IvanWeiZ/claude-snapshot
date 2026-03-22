#!/bin/bash
# Tests: setup.sh install, idempotency, preserving existing hooks
source "$(dirname "$0")/helpers.sh"

echo "=== Setup Tests ==="

# --- Install ---
echo "Test: setup.sh install"
setup_sandbox
install_snapshot

[ -f "$CLAUDE_DIR/hooks/claude-snapshot.sh" ] && pass "Hook file installed" || fail "Hook file not found"
[ -f "$CLAUDE_DIR/.snapshot-repo" ] && [ "$(cat "$CLAUDE_DIR/.snapshot-repo")" = "$REPO" ] && pass "Marker file correct" || fail "Marker file missing or wrong"
jq -e '.hooks.SessionStart' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1 && pass "SessionStart hook registered" || fail "SessionStart hook missing"
jq -e '.hooks.PostToolUse' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1 && pass "PostToolUse hook registered" || fail "PostToolUse hook missing"
[ -d "$REPO/.git" ] && git -C "$REPO" log --oneline -1 > /dev/null 2>&1 && pass "First snapshot committed" || fail "No initial commit"

# --- Idempotency ---
echo ""
echo "Test: Running setup twice doesn't duplicate hooks"
bash "$REPO/setup.sh" > /dev/null 2>&1
SESSION_COUNT=$(jq '.hooks.SessionStart | length' "$CLAUDE_DIR/settings.json")
POSTTOOL_COUNT=$(jq '.hooks.PostToolUse | length' "$CLAUDE_DIR/settings.json")
[ "$SESSION_COUNT" = "1" ] && [ "$POSTTOOL_COUNT" = "1" ] && pass "No duplicate hook entries" || fail "Duplicates: Session=$SESSION_COUNT PostTool=$POSTTOOL_COUNT"

# --- Preserves existing hooks ---
echo ""
echo "Test: Preserves existing hooks in settings.json"
reset_claude_dir
mkdir -p "$CLAUDE_DIR/hooks"
cat > "$CLAUDE_DIR/settings.json" << 'JSONEOF'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo existing"}]}]}}
JSONEOF

FRESH_REPO="$SANDBOX/fresh-repo"
copy_project_files "$FRESH_REPO"
bash "$FRESH_REPO/setup.sh" > /dev/null 2>&1

EXISTING=$(jq '.hooks.SessionStart | map(select(.hooks[]?.command == "echo existing")) | length' "$CLAUDE_DIR/settings.json")
SNAPSHOT=$(jq '.hooks.SessionStart | map(select(.hooks[]?.command | test("claude-snapshot"))) | length' "$CLAUDE_DIR/settings.json")
[ "$EXISTING" = "1" ] && [ "$SNAPSHOT" = "1" ] && pass "Both hooks preserved" || fail "Existing=$EXISTING Snapshot=$SNAPSHOT"

# --- Backup created ---
echo ""
echo "Test: Settings backup created"
setup_sandbox
install_snapshot
[ -f "$CLAUDE_DIR/settings.json.pre-snapshot-backup" ] && pass "Backup file created" || fail "No backup file"

# --- Missing prereqs (check code path exists) ---
echo ""
echo "Test: Prereq check exists in code"
grep -q "command -v" "$REPO/setup.sh" && grep -q "required" "$REPO/setup.sh" && pass "Prereq check in code" || fail "No prereq check"

# --- Missing ~/.claude ---
echo ""
echo "Test: Fails if ~/.claude doesn't exist"
rm -rf "$CLAUDE_DIR"
OUTPUT=$(bash "$REPO/setup.sh" 2>&1) || true
echo "$OUTPUT" | grep -qi "not found\|Claude Code" && pass "Reports missing ~/.claude" || fail "No missing dir error"

results
