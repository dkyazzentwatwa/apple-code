#!/usr/bin/env bash
set -euo pipefail

PROFILE=".build/arm64-apple-macosx/debug/codecov/default.profdata"
TEST_BIN=".build/arm64-apple-macosx/debug/apple-codePackageTests.xctest/Contents/MacOS/apple-codePackageTests"
CORE_IGNORE_REGEX='Sources/AppleCode/(REPLLoop\.swift|main\.swift|InputComposer\.swift|TUIRenderer\.swift|TUIUtils\.swift|ModelClient\.swift|Apple.*\.swift|WebFallback\.swift)|Sources/AppleCode/Tools/(AgentBrowserTool|CalendarTool|CreatePDFTool|MailTool|MessagesTool|NotesTool|RemindersTool|WebFetchTool|WebSearchTool)\.swift|\.build/|Tests/'

swift test --enable-code-coverage

if [[ ! -f "$PROFILE" ]]; then
  echo "Coverage profile not found: $PROFILE" >&2
  exit 1
fi
if [[ ! -x "$TEST_BIN" ]]; then
  echo "Coverage test binary not found: $TEST_BIN" >&2
  exit 1
fi

echo ""
echo "== Full Coverage =="
FULL_REPORT="$(xcrun llvm-cov report -instr-profile "$PROFILE" "$TEST_BIN")"
printf '%s\n' "$FULL_REPORT"
FULL_LINE="$(printf '%s\n' "$FULL_REPORT" | awk '/^TOTAL/{print $10}')"

echo ""
echo "== Core Coverage (80% gate) =="
CORE_REPORT="$(xcrun llvm-cov report -instr-profile "$PROFILE" "$TEST_BIN" -ignore-filename-regex "$CORE_IGNORE_REGEX")"
printf '%s\n' "$CORE_REPORT"
CORE_LINE="$(printf '%s\n' "$CORE_REPORT" | awk '/^TOTAL/{print $10}')"

FULL_NUM="${FULL_LINE%%%}"
CORE_NUM="${CORE_LINE%%%}"

echo ""
echo "Full line coverage: ${FULL_NUM}%"
echo "Core line coverage: ${CORE_NUM}%"

awk -v core="$CORE_NUM" 'BEGIN { if (core < 80.0) { exit 1 } }' || {
  echo "Core line coverage gate failed: ${CORE_NUM}% < 80%" >&2
  exit 1
}

echo "Coverage gate passed (core >= 80%)."
