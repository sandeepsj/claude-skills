#!/usr/bin/env bash
# Greps a Vayu diff for golden-rule violations.
#
# Usage:
#   review-diff.sh                        # staged changes vs HEAD
#   review-diff.sh --branch beta          # current HEAD vs 'beta'
#   review-diff.sh --files a.hs b.hs      # specific files (entire content)
#
# Exit code: non-zero if any ERROR-severity rule fires.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

MODE="staged"
BASE=""
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) MODE="branch"; BASE="$2"; shift 2 ;;
    --files)  MODE="files"; shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES+=("$1"); shift; done ;;
    --staged) MODE="staged"; shift ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

DIFF_FILE=$(mktemp)
FILES_CHANGED=$(mktemp)
trap 'rm -f "$DIFF_FILE" "$FILES_CHANGED"' EXIT

case "$MODE" in
  staged)
    git diff --cached > "$DIFF_FILE"
    git diff --cached --name-only > "$FILES_CHANGED"
    ;;
  branch)
    git diff "$BASE"...HEAD > "$DIFF_FILE"
    git diff "$BASE"...HEAD --name-only > "$FILES_CHANGED"
    ;;
  files)
    : > "$DIFF_FILE"
    : > "$FILES_CHANGED"
    for f in "${FILES[@]}"; do
      printf '%s\n' "$f" >> "$FILES_CHANGED"
      printf '+++ b/%s\n' "$f" >> "$DIFF_FILE"
      sed 's/^/+/' "$f" >> "$DIFF_FILE"
    done
    ;;
esac

ADDED_LINES=$(grep '^+' "$DIFF_FILE" | grep -v '^+++')

ANY_ERROR=0
section() { printf '\n── %s ──\n' "$1"; }
ok()      { printf '  ok\n'; }
fail()    { printf '  %s\n' "$1"; ANY_ERROR=1; }
warn()    { printf '  ! %s\n' "$1"; }

section "no-edit-generated (ERROR)"
if grep -qE '^[+-]{3} [ab]/src/Vayu/Generated/' "$DIFF_FILE"; then
  fail "Diff touches src/Vayu/Generated/. Never edit by hand; change YAML + regenerate."
else ok; fi

section "no-partial-functions (ERROR)"
HITS=$(printf '%s\n' "$ADDED_LINES" | grep -nE '\b(fromJust|head|tail|last|init|read|error|undefined)\b' || true)
HITS=$(printf '%s\n' "$HITS" | grep -vE '\b(read(File|LBS|Show|able|s))\b' || true)
if [[ -n "$HITS" ]]; then
  printf '%s\n' "$HITS" | head -20 | sed 's/^/    /'
  fail "Banned partial function(s) in added lines."
else ok; fi

section "no-warn-suppression (ERROR)"
if grep -qE '(-fno-warn-incomplete|-Wno-incomplete)' "$DIFF_FILE"; then
  grep -nE '(-fno-warn-incomplete|-Wno-incomplete)' "$DIFF_FILE" | sed 's/^/    /'
  fail "Incomplete-pattern warning suppression detected. Fix the match, don't silence."
else ok; fi

section "product-does-not-touch-generated-queries (ERROR)"
PRODUCT_FILES=$(grep 'src/Vayu/Product/' "$FILES_CHANGED" || true)
if [[ -n "$PRODUCT_FILES" ]]; then
  VIOLATIONS=""
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    m=$(grep -nE '^import.*(Vayu\.Generated\.Queries|Vayu\.Generated\.Types\.Storage|Vayu\.Storage\.Queries)' "$f" || true)
    [[ -n "$m" ]] && VIOLATIONS+="$f:$m"$'\n'
  done <<< "$PRODUCT_FILES"
  if [[ -n "$VIOLATIONS" ]]; then
    printf '%s' "$VIOLATIONS" | sed 's/^/    /'
    fail "Product layer importing Generated.Queries / Storage. Route through Services/Internal."
  else ok; fi
else ok; fi

section "operationId-kebab-case (ERROR)"
HITS=$(grep -nE '^\+.*operationId:\s*[A-Z]|^\+.*operationId:.*[a-z][A-Z]|^\+.*operationId:.*_' "$DIFF_FILE" || true)
if [[ -n "$HITS" ]]; then
  printf '%s\n' "$HITS" | sed 's/^/    /'
  fail "operationId must be kebab-case (create-my-feature)."
else ok; fi

section "x-enum-required (ERROR)"
# Look for added enum schemas without x-enum true — simplified heuristic:
# any added `enum:` under a `type: string` block should have `x-enum: true` nearby.
ENUM_BLOCKS=$(awk '/^\+.*type:\s*string/ {near=1; line=NR} near && /^\+.*enum:/ {print line":"NR; near=0}' "$DIFF_FILE" || true)
if [[ -n "$ENUM_BLOCKS" ]]; then
  if ! grep -qE '^\+.*x-enum:\s*true' "$DIFF_FILE"; then
    warn "New enum schema detected but no 'x-enum: true' in diff. Verify manually."
  else ok; fi
else ok; fi

section "register-new-table-in-BreezeDB (ERROR)"
DBQUERIES_CHANGED=$(grep -c '^doc/DBQueries.yaml$' "$FILES_CHANGED" 2>/dev/null || true)
BREEZEDB_CHANGED=$(grep -c '^src/Vayu/Types/Storage/BreezeDB.hs$' "$FILES_CHANGED" 2>/dev/null || true)
DBQUERIES_CHANGED=${DBQUERIES_CHANGED:-0}
BREEZEDB_CHANGED=${BREEZEDB_CHANGED:-0}
if [[ "$DBQUERIES_CHANGED" -gt 0 && "$BREEZEDB_CHANGED" -eq 0 ]]; then
  fail "doc/DBQueries.yaml changed but src/Vayu/Types/Storage/BreezeDB.hs did not. Register the entity."
else ok; fi

section "prefer-logm-for-pure-helpers (WARN)"
if grep -qE '^\+.*:: .*Flow ' "$DIFF_FILE"; then
  warn "New Flow-typed functions added. For helpers with no DB/HTTP/Redis/config/clock/throw, consider LogM (see pure-logm-helper template)."
else ok; fi

section "scattered-logInfo (WARN)"
HITS=$(grep -nE '^\+.*Logger\.logInfo' "$DIFF_FILE" | grep -v 'Vayu.Utils.LogM' || true)
if [[ -n "$HITS" ]]; then
  printf '%s\n' "$HITS" | head -10 | sed 's/^/    /'
  warn "Ad-hoc Logger.logInfo calls. Prefer withProductAPILogging / withFunctionLogging wrappers."
else ok; fi

section "legacy-logger-pair (ERROR)"
if grep -qE '^\+.*(logProductAPIRequest|logProductAPIResponse)' "$DIFF_FILE"; then
  grep -nE '^\+.*(logProductAPIRequest|logProductAPIResponse)' "$DIFF_FILE" | sed 's/^/    /'
  fail "Legacy two-liner logger pattern. Use withProductAPILogging instead."
else ok; fi

printf '\n'
if [[ "$ANY_ERROR" -eq 1 ]]; then
  echo "Review: FAIL — address the error-level items above before committing."
  exit 1
else
  echo "Review: PASS (warnings may still need a look)"
  exit 0
fi
