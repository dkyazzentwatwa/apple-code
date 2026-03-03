#!/usr/bin/env bash
set -euo pipefail

PROFILE=""
TEST_BIN=""
CORE_IGNORE_REGEX='Sources/AppleCode/(REPLLoop\.swift|main\.swift|InputComposer\.swift|TUIRenderer\.swift|TUIUtils\.swift|ModelClient\.swift|Apple.*\.swift|WebFallback\.swift)|Sources/AppleCode/Tools/(AgentBrowserTool|CalendarTool|CreatePDFTool|MailTool|MessagesTool|NotesTool|RemindersTool|WebFetchTool|WebSearchTool)\.swift|\.build/|Tests/'

swift test --enable-code-coverage

PROFILE="$(find .build -type f -path '*/debug/codecov/default.profdata' | head -n 1 || true)"
TEST_BIN="$(find .build -type f -path '*/debug/apple-codePackageTests.xctest/Contents/MacOS/apple-codePackageTests' | head -n 1 || true)"

if [[ ! -f "$PROFILE" ]]; then
  echo "Coverage profile not found under .build (expected */debug/codecov/default.profdata)" >&2
  exit 1
fi
if [[ ! -x "$TEST_BIN" ]]; then
  echo "Coverage test binary not found under .build (expected */debug/apple-codePackageTests.xctest/...)" >&2
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
