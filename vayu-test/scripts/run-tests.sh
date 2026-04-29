#!/usr/bin/env bash
# Runs the Vayu hspec suite via the canonical dotenv + stack exec wrapper.
# Summarises failures. Full raw output lives at /tmp/vayu-test.log.
#
# Usage:
#   run-tests.sh                         # full suite
#   run-tests.sh --match "Cart"          # filter by spec description
#   run-tests.sh --failed                # rerun only previously-failed (hspec --rerun)
#   run-tests.sh -- --seed 12345         # pass anything after `--` directly to hspec
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOG="/tmp/vayu-test.log"

HSPEC_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --match)   HSPEC_ARGS+=(--match "$2"); shift 2 ;;
    --failed)  HSPEC_ARGS+=(--rerun --rerun-all-on-success); shift ;;
    --)        shift; HSPEC_ARGS+=("$@"); break ;;
    *)         HSPEC_ARGS+=("$1"); shift ;;
  esac
done

cd "$REPO_ROOT"
: > "$LOG"

# shellcheck disable=SC2016
CMD=( npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec' -- "${HSPEC_ARGS[@]}" )
printf 'Running: %s\n' "${CMD[*]}" | tee -a "$LOG"
"${CMD[@]}" 2>&1 | tee -a "$LOG"
STATUS="${PIPESTATUS[0]}"

# Extract a compact failure summary from hspec output.
# hspec prints failed specs in a "Failures:" section.
awk '
  /^Failures:[[:space:]]*$/ { in_fail = 1; next }
  /^Randomized with seed/   { in_fail = 0 }
  /^Finished in/            { in_fail = 0 }
  in_fail && /^  [0-9]+\)/  { print }
  in_fail && /^[[:space:]]+(expected|but got|uncaught exception|in spec|To rerun)/ { print }
' "$LOG" > /tmp/vayu-test.failures

# Totals from the "N examples, M failures, K pending" line
SUMMARY=$(grep -E '^[0-9]+ examples?,' "$LOG" | tail -1 || true)

if [[ -s /tmp/vayu-test.failures ]]; then
  echo ""
  echo "=== Failure details ==="
  cat /tmp/vayu-test.failures
fi

echo ""
echo "Summary: ${SUMMARY:-no summary line found}  (full log: $LOG)"

exit "$STATUS"
