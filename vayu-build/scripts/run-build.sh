#!/usr/bin/env bash
# Runs `pnpm build` in the Vayu repo root and prints a structured list of
# GHC errors/warnings. Full raw output lives at /tmp/vayu-build.log.
#
# Usage: run-build.sh
# Output format (one diagnostic per line):
#   ERROR src/Vayu/Product/Cart/X.hs:42:7 Variable not in scope: foo
#   WARN  src/Vayu/Product/Cart/X.hs:15:1 The import of 'Data.Map' is redundant
#
# Exit code: 0 on success, 1 on any error diagnostic, 2 on build harness failure.
set -uo pipefail

# Resolve the Vayu repo root from the script's own location:
#   <repo>/.claude/skills/vayu-build/scripts/run-build.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOG="/tmp/vayu-build.log"

cd "$REPO_ROOT"
: > "$LOG"

# Run the build and stream output to log while also capturing it
pnpm build 2>&1 | tee "$LOG"
BUILD_STATUS="${PIPESTATUS[0]}"

# Parse GHC diagnostics out of the log.
# GHC format: "<file>:<line>:<col>: error: <msg>" or "warning:" variants.
# Messages often span multiple lines — we take only the first line of each block.
awk '
  /^[^ ].*\.hs:[0-9]+:[0-9]+: (error|warning):/ {
    if (matched) { print out; out = ""; matched = 0 }
    # Split "path:line:col: severity: rest"
    split($0, a, ": ")
    # Reconstruct file:line:col (everything before the first ": severity:")
    pos = index($0, ": error:")
    sev = "ERROR"
    if (pos == 0) { pos = index($0, ": warning:"); sev = "WARN " }
    loc = substr($0, 1, pos - 1)
    rest = substr($0, pos + length(sev == "ERROR" ? ": error:" : ": warning:"))
    gsub(/^[[:space:]]+/, "", rest)
    out = sev " " loc " " rest
    matched = 1
    next
  }
  matched && /^[[:space:]]/ {
    # Continuation line — append up to ~80 chars of the first continuation
    gsub(/^[[:space:]]+/, "", $0)
    if (length(out) < 160 && length($0) > 0 && continued < 1) {
      out = out " | " $0
      continued = 1
    }
    next
  }
  matched {
    print out
    out = ""
    matched = 0
    continued = 0
  }
  END { if (matched) print out }
' "$LOG" > /tmp/vayu-build.parsed

ERRORS=$(grep -c '^ERROR' /tmp/vayu-build.parsed 2>/dev/null || true)
WARNS=$(grep -c  '^WARN ' /tmp/vayu-build.parsed 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNS=${WARNS:-0}

if [[ -s /tmp/vayu-build.parsed ]]; then
  cat /tmp/vayu-build.parsed
  echo ""
fi

echo "Summary: ${ERRORS} errors, ${WARNS} warnings  (full log: $LOG)"

if [[ "$BUILD_STATUS" -ne 0 && "$ERRORS" -eq 0 ]]; then
  echo "Build harness failed (exit=$BUILD_STATUS) but no GHC diagnostics extracted — check $LOG." >&2
  exit 2
fi

if [[ "$ERRORS" -gt 0 ]]; then
  exit 1
fi

exit 0
