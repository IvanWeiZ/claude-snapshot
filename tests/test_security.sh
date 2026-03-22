#!/bin/bash
# Tests: Secret detection, auto-push
source "$(dirname "$0")/helpers.sh"

echo "=== Security & Push Tests ==="

setup_sandbox
install_snapshot

# --- Secret detection: API key pattern ---
echo "Test: Detects API key patterns"
echo '{"api_key": "sk-ant-1234567890abcdef"}' > "$CLAUDE_DIR/settings.json"
bash "$REPO/setup.sh" > /dev/null 2>&1
bash "$REPO/snapshot.sh" < /dev/null 2>"$SANDBOX/stderr.txt" || true
grep -q "Warning.*secrets" "$SANDBOX/stderr.txt" 2>/dev/null && pass "Warns about API key" || fail "No warning for API key"

# --- Secret detection: GitHub token ---
echo ""
echo "Test: Detects GitHub token"
echo '{"token": "ghp_abcdefghijklmnopqrstuvwxyz1234567890"}' > "$CLAUDE_DIR/settings.json"
bash "$REPO/setup.sh" > /dev/null 2>&1
bash "$REPO/snapshot.sh" < /dev/null 2>"$SANDBOX/stderr2.txt" || true
grep -q "Warning.*secrets" "$SANDBOX/stderr2.txt" 2>/dev/null && pass "Warns about GitHub token" || fail "No warning for GitHub token"

# --- Secret detection: AWS key ---
echo ""
echo "Test: Detects AWS key"
echo '{"key": "AKIAIOSFODNN7EXAMPLE"}' > "$CLAUDE_DIR/settings.json"
bash "$REPO/setup.sh" > /dev/null 2>&1
bash "$REPO/snapshot.sh" < /dev/null 2>"$SANDBOX/stderr3.txt" || true
grep -q "Warning.*secrets" "$SANDBOX/stderr3.txt" 2>/dev/null && pass "Warns about AWS key" || fail "No warning for AWS key"

# --- No false positive ---
echo ""
echo "Test: No false positive on clean config"
echo '{"permissions": {"allow": ["Bash(*)"]}}' > "$CLAUDE_DIR/settings.json"
bash "$REPO/setup.sh" > /dev/null 2>&1
bash "$REPO/snapshot.sh" < /dev/null 2>"$SANDBOX/stderr_clean.txt" || true
! grep -q "Warning.*secrets" "$SANDBOX/stderr_clean.txt" 2>/dev/null && pass "No false positive" || fail "False positive on clean file"

# --- Auto-push: disabled by default ---
echo ""
echo "Test: Auto-push disabled by default"
setup_sandbox
install_snapshot

REMOTE="$SANDBOX/remote.git"
git init --bare "$REMOTE" > /dev/null 2>&1
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
git -C "$REPO" remote add origin "$REMOTE" 2>/dev/null || git -C "$REPO" remote set-url origin "$REMOTE"
git -C "$REPO" push -u origin main > /dev/null 2>&1

echo "# no-push" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REMOTE" rev-parse HEAD 2>/dev/null)
unset CLAUDE_SNAPSHOT_PUSH
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REMOTE" rev-parse HEAD 2>/dev/null)
[ "$BEFORE" = "$AFTER" ] && pass "No push by default" || fail "Pushed without opt-in"

# --- Auto-push: enabled ---
echo ""
echo "Test: Auto-push with CLAUDE_SNAPSHOT_PUSH=1"
echo "# push-test" >> "$CLAUDE_DIR/CLAUDE.md"
BEFORE=$(git -C "$REMOTE" rev-parse HEAD 2>/dev/null)
export CLAUDE_SNAPSHOT_PUSH=1
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null
AFTER=$(git -C "$REMOTE" rev-parse HEAD 2>/dev/null)
unset CLAUDE_SNAPSHOT_PUSH
[ "$BEFORE" != "$AFTER" ] && pass "Push works with opt-in" || fail "Push didn't work"

# --- Auto-push: no remote = no error ---
echo ""
echo "Test: Auto-push graceful without remote"
setup_sandbox
install_snapshot
echo "# no-remote" >> "$CLAUDE_DIR/CLAUDE.md"
export CLAUDE_SNAPSHOT_PUSH=1
EXIT_CODE=0
bash "$REPO/snapshot.sh" < /dev/null 2>/dev/null || EXIT_CODE=$?
unset CLAUDE_SNAPSHOT_PUSH
[ "$EXIT_CODE" = "0" ] && pass "No error without remote" || fail "Error without remote"

results
