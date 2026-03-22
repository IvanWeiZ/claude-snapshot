#!/bin/bash
# Tests: --status, --diff, --log, --help
source "$(dirname "$0")/helpers.sh"

echo "=== Command Tests ==="

setup_sandbox
install_snapshot

# --- Status ---
echo "Test: --status"
STATUS=$(bash "$REPO/setup.sh" --status 2>&1)
echo "$STATUS" | grep -q "installed" && pass "Shows hook installed" || fail "Missing hook status"
echo "$STATUS" | grep -q "commits" && pass "Shows commit count" || fail "Missing commit count"
echo "$STATUS" | grep -q "registered" && pass "Shows hooks registered" || fail "Missing registration"
echo "$STATUS" | grep -q "Tracking" && pass "Shows tracking categories" || fail "Missing tracking"
echo "$STATUS" | grep -q "Push" && pass "Shows push status" || fail "Missing push status"

# --- Status after uninstall ---
echo ""
echo "Test: --status after uninstall"
bash "$REPO/setup.sh" --uninstall > /dev/null 2>&1
STATUS=$(bash "$REPO/setup.sh" --status 2>&1)
echo "$STATUS" | grep -q "not installed" && pass "Shows hook not installed" || fail "Still shows installed"
bash "$REPO/setup.sh" > /dev/null 2>&1

# --- Diff: no changes ---
echo ""
echo "Test: --diff no changes"
DIFF=$(bash "$REPO/setup.sh" --diff 2>&1)
echo "$DIFF" | grep -q "No changes" && pass "Reports no changes" || fail "Didn't report no changes"

# --- Diff: with changes ---
echo ""
echo "Test: --diff with changes"
echo "# diff-line" >> "$CLAUDE_DIR/CLAUDE.md"
DIFF=$(bash "$REPO/setup.sh" --diff 2>&1)
echo "$DIFF" | grep -qi "change" && pass "Shows changes" || fail "Didn't show changes"

# --- Log ---
echo ""
echo "Test: --log"
LOG=$(bash "$REPO/setup.sh" --log 2>&1)
echo "$LOG" | grep -q "auto:" && pass "Shows commit messages" || fail "Missing commits"

# --- Log with count ---
echo ""
echo "Test: --log with count"
LOG_1=$(bash "$REPO/setup.sh" --log 1 2>&1)
LINE_COUNT=$(echo "$LOG_1" | wc -l | tr -d ' ')
[ "$LINE_COUNT" -le 2 ] && pass "Respects count arg" || fail "Count arg broken ($LINE_COUNT lines)"

# --- Help ---
echo ""
echo "Test: --help"
HELP=$(bash "$REPO/setup.sh" --help 2>&1)
for cmd in restore uninstall status diff log; do
  echo "$HELP" | grep -q "$cmd" && pass "--help mentions $cmd" || fail "--help missing $cmd"
done

# --- Unknown option ---
echo ""
echo "Test: Unknown option"
OUTPUT=$(bash "$REPO/setup.sh" --garbage 2>&1) || true
echo "$OUTPUT" | grep -qi "unknown\|error" && pass "Rejects unknown option" || fail "No error for unknown option"

results
