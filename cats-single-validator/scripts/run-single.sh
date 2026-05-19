#!/usr/bin/env bash
# Run ONE CATS thing — a behavioral validator, an OpenAPI path's fuzzers, or a
# specific cats-runner test ID. Skips the ~40-min full suite.
#
# Usage:
#   ./scripts/cats/run-single.sh validator <name-substring>
#   ./scripts/cats/run-single.sh path      <openapi-path>
#   ./scripts/cats/run-single.sh test      <numeric-id-or-TestNNNN>
#
# Examples:
#   ./scripts/cats/run-single.sh validator breeze
#   ./scripts/cats/run-single.sh path /btoa/bulk/reward
#   ./scripts/cats/run-single.sh test 6669
#
# pnpm wrapper: `pnpm run cats:single -- <kind> <filter>`
#
# Brings up Redis + Vayu (and cats-server proxy for path/test) if not already
# running. Reuses them on subsequent invocations.

set -euo pipefail

# pnpm sometimes forwards a literal '--' before the actual args; strip it.
[ "${1:-}" = "--" ] && shift

KIND="${1:-}"
FILTER="${2:-}"
VAYU_LOG=/tmp/vayu-single.log
CATS_SERVER_LOG=/tmp/cats-server-single.log

usage() {
  cat <<EOF
Usage: $0 <kind> <filter>
  kind:    validator | path | test
  filter:
    validator  - case-insensitive substring of validation.name
    path       - OpenAPI path (e.g. /btoa/bulk/reward)
    test       - numeric ID (e.g. 6669) or full ID (e.g. Test6669)

Examples:
  $0 validator breeze
  $0 path /btoa/bulk/reward
  $0 test 6669

Optional env:
  VAYU_BASE_URL          (default: http://localhost:9100)
  LOG_EMISSION_SHOP_ID   (default: d2cstore-beta-1; set to a shop that exists
                          in your local DB if the default doesn't)
EOF
  exit 1
}

[ -z "$KIND" ] || [ -z "$FILTER" ] && usage

# --- bring-up ---
ensure_redis() {
  if ! redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "[bringup] starting redis on :6379..."
    redis-server --daemonize yes --port 6379 >/dev/null
  fi
}

ensure_vayu() {
  if curl -sf http://localhost:9100/heartbeat >/dev/null 2>&1; then
    return
  fi
  echo "[bringup] starting Vayu (npx dotenv -- stack exec vayu-exe)..."
  npx dotenv -- bash -c '$STACK_PATH exec vayu-exe' > "$VAYU_LOG" 2>&1 &
  for i in $(seq 1 90); do
    if curl -sf http://localhost:9100/heartbeat >/dev/null 2>&1; then
      echo "[bringup] vayu ready (${i}s)"
      return
    fi
    sleep 1
  done
  echo "[bringup] vayu failed to start in 90s. Tail of $VAYU_LOG:"
  tail -20 "$VAYU_LOG"
  exit 1
}

ensure_cats_server() {
  if nc -z localhost 6475 2>/dev/null; then
    return
  fi
  echo "[bringup] starting cats-server proxy on :6475..."
  npx dotenv -- bash -c 'NODE_NO_WARNINGS=1 node scripts/cats/server/catsServer.js' > "$CATS_SERVER_LOG" 2>&1 &
  for i in $(seq 1 30); do
    nc -z localhost 6475 2>/dev/null && { echo "[bringup] cats-server ready (${i}s)"; return; }
    sleep 1
  done
  echo "[bringup] cats-server failed to start. Tail of $CATS_SERVER_LOG:"
  tail -20 "$CATS_SERVER_LOG"
  exit 1
}

case "$KIND" in
  validator)
    ensure_redis
    ensure_vayu
    echo "[validator] filter='$FILTER'"
    DATABASENAME="${DATABASENAME:-newvayu}" \
    DATABASEHOST="${DATABASEHOST:-localhost}" \
    DATABASEPORT="${DATABASEPORT:-5432}" \
    DATABASEUSER="${DATABASEUSER:-$USER}" \
    DATABASEPASSWORD="${DATABASEPASSWORD:-}" \
    VALIDATION_FILTER="$FILTER" \
      node scripts/cats/helper/validateBehavior.js
    ;;
  path)
    ensure_redis
    ensure_vayu
    ensure_cats_server
    echo "[path] running cats-runner for path='$FILTER'..."
    java -jar scripts/cats-runner.jar \
      --server=http://localhost:6475 \
      --contract=./doc/merged.yaml \
      --refData=doc/cats/refData.yml \
      --paths="$FILTER" \
      --maxRequestsPerMinute=12000
    ;;
  test)
    ensure_redis
    ensure_vayu
    ensure_cats_server
    TEST_ID="${FILTER#Test}"
    echo "[test] running cats-runner for test='$TEST_ID'..."
    java -jar scripts/cats-runner.jar \
      --server=http://localhost:6475 \
      --contract=./doc/merged.yaml \
      --refData=doc/cats/refData.yml \
      --tests="$TEST_ID" \
      --maxRequestsPerMinute=12000
    ;;
  *)
    echo "Unknown kind: '$KIND'"
    usage
    ;;
esac
