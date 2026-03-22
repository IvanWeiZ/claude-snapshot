#!/bin/bash
# Test runner for claude-snapshot
# Runs all tests in tests/ directory, each in its own sandbox
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

echo "=== claude-snapshot test suite ==="
echo ""

for test_file in "$SCRIPT_DIR"/tests/test_*.sh; do
  [ -f "$test_file" ] || continue
  SUITE_NAME=$(basename "$test_file" .sh | sed 's/test_//')

  echo "--- $SUITE_NAME ---"
  OUTPUT=$(bash "$test_file" 2>&1)
  EXIT_CODE=$?

  # Print output
  echo "$OUTPUT" | grep -E "^\s+(PASS|FAIL):" || true

  # Extract counts
  SUITE_PASS=$(echo "$OUTPUT" | grep -c "PASS:" || true)
  SUITE_FAIL=$(echo "$OUTPUT" | grep -c "FAIL:" || true)
  TOTAL_PASS=$((TOTAL_PASS + SUITE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + SUITE_FAIL))

  if [ "$EXIT_CODE" -ne 0 ]; then
    FAILED_SUITES+=("$SUITE_NAME")
  fi
  echo ""
done

echo "=== Results: $TOTAL_PASS passed, $TOTAL_FAIL failed ==="

if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
  echo "Failed suites: ${FAILED_SUITES[*]}"
  exit 1
fi

exit 0
