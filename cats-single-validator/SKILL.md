---
name: cats-single-validator
description: Run ONE CATS thing locally — a behavioral validator, the fuzzers for one OpenAPI path, or a single cats-runner test ID — bypassing the ~40-minute full suite. Brings up Vayu + Redis automatically and reuses them. Use when iterating on a new behavioral validator, triaging a single failing test ID from a CI report, or fuzzing one specific API path without re-running the entire CATS run. Vayu-repo-specific (assumes the runner finds scripts/cats/helper/validateBehavior.js etc.).
allowed-tools: Bash, Read, Grep, Glob
---

# Run a single CATS thing locally

`./scripts/run-single.sh` (bundled with this skill) is a generic one-command
runner that exercises **one** piece of the CATS suite — a behavioral validator,
the fuzzers for one OpenAPI path, or a single cats-runner test ID — bypassing
the ~40-minute full suite. Brings up Vayu + Redis if not already running; the
next invocation reuses them.

## When to use

- A behavioral validator added in your PR fails on CI and you don't want to
  burn 40 min per Jenkins iteration.
- You're authoring a new validator and want a tight local loop.
- You only want to fuzz one specific API path (`--paths=…` under the hood).
- You want to rerun a single failing test ID from a CI report.

## Three modes

```bash
./scripts/run-single.sh validator <name-substring>
./scripts/run-single.sh path      <openapi-path>
./scripts/run-single.sh test      <numeric-id-or-TestNNNN>
```

| Mode | Filter | What it does |
|---|---|---|
| `validator` | case-insensitive substring of `validation.name` from `scripts/cats/helper/validations/index.js` | Runs `validateBehavior.js` with `VALIDATION_FILTER` set. Calls the validator's `setup()` first if defined (so the validator can mint state — token, POST, capture file — for a fresh local run). |
| `path` | OpenAPI path string from `doc/cats/Api.yaml` | Starts `cats-server` proxy on :6475 if needed, runs `cats-runner.jar --paths=<path>`. All fuzzers run against that one path only. |
| `test` | Numeric test ID (or `Test6669`) | Same as `path` but uses `--tests=<id>`. Useful for triaging a single CI failure. |

## Examples

```bash
# A behavioral validator (BZ-3054 LogM-emission example):
./scripts/run-single.sh validator breeze

# All fuzzers against one endpoint:
./scripts/run-single.sh path /btoa/bulk/reward

# A specific failing test ID from a CI report:
./scripts/run-single.sh test 6669
```

Optional pnpm wrapper if added to package.json:
`"cats:single": "./scripts/cats/run-single.sh"` then
`pnpm run cats:single -- validator breeze` (the runner strips a leading `--`).

## How `validator` mode wires the state

`validateBehavior.js` awaits each validation's optional `setup()` before
calling `validate()`. A `setup()` is **idempotent** — it should no-op if the
capture file it produces already exists (the CI case, where
`captureEndpoints.js` ran earlier). Locally the capture is usually absent,
so `setup()` does the full state-bring-up (mint token, POST endpoint, write
capture file, sleep for the async DB-log flush).

To add a setup hook for a new validator, export an `async setup()` from the
same module that exports `validate`. The runner picks it up automatically;
no change to `run-single.sh` needed.

## Required env (defaults work out of the box for a typical Vayu dev env)

| Env | Default | When to override |
|---|---|---|
| `VAYU_BASE_URL` | `http://localhost:9100` | Vayu running on a non-default port |
| `SUPER_USER_KEY` | `ABC` (from `.env`) | Local override |
| `LOG_EMISSION_SHOP_ID` | `d2cstore-beta-1` | Your local DB doesn't have that shop. Set to a `shop.id` row that exists locally AND has a `BREEZE_WALLET` shopIntegration. `arch-store-shopify` works on most dev DBs. |
| `DATABASENAME` / `HOST` / `PORT` / `USER` / `PASSWORD` | `newvayu` / `localhost` / `5432` / `$USER` / `""` | Different local postgres |

## Bring-up details

The script will:

1. Ensure Redis on `:6379` (`redis-server --daemonize yes`).
2. Ensure Vayu on `:9100` (`npx dotenv -- '$STACK_PATH exec vayu-exe'`).
   Waits up to 90s for the heartbeat. Reuses an existing instance.
3. For `path` / `test` modes only: ensure `cats-server` proxy on `:6475`
   (`node scripts/cats/server/catsServer.js`).

It does NOT tear anything down between invocations — your second run uses
the already-running services, so iteration after the first run is ~3
seconds. Kill manually when you're done:

```bash
pkill -9 -f vayu-exe
redis-cli -p 6379 shutdown nosave 2>/dev/null
npx kill-port 6475   # cats-server proxy if you used path/test mode
```

## Adding a new validator-only run

If your new behavioral validator needs state (token, POST, capture), add an
`async setup()` to the same file as `validate()`. The runner picks it up
automatically. Pattern:

```js
export async function setup() {
  const captureFile = path.join(__dirname, '..', 'captures', '<your-capture>.json');
  if (fs.existsSync(captureFile)) return;   // idempotent — CI path

  // Mint token, POST endpoint, write capture, sleep for any async flush.
  // Bail quietly if Vayu isn't reachable so validate() can surface the failure.
}
```

## Limitations

- Vayu-repo-specific paths. The script assumes CWD is the Vayu repo root and
  finds `scripts/cats/helper/validateBehavior.js`, `scripts/cats-runner.jar`,
  `scripts/cats/server/catsServer.js`.
- `path` and `test` modes still require the `cats-server` proxy (mock layer
  for downstream APIs). First start of the proxy takes ~5s.
- Vayu compile time isn't covered here — if you changed Haskell code,
  rebuild via `pnpm build` first (the runner doesn't rebuild).
- The full CATS pipeline runs through `init-test.sh` which also handles
  docker-compose, hydrate, etc. This skill targets the local-dev loop, not
  a containerized rerun of the full CI flow.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `vayu failed to start in 90s` | Check `/tmp/vayu-single.log`. Common: stale Redis, port 9100 in use. |
| `Failed to query cats Postgres log table` | The diagnostic message includes `code` / `address` / `port`. ECONNREFUSED → wrong DATABASEHOST/PORT. `relation "log" does not exist` → your local DB pre-dates the `Log` schema add; rerun the DDL or use a fresh DB. |
| `FunctionCalled value.shopId expected …` | Your local DB has a different shop than the default. Set `LOG_EMISSION_SHOP_ID` to a shop you have hydrated. |
| Validator output shows 2 matching validators | Substring matched more than one — narrow the filter (e.g. `breeze-wallet` instead of `breeze`). |

## Related

- `vayu-build` / `vayu-test` — hspec / build skills. Faster iteration when
  the change is Haskell-only and doesn't need the wire path.
- BZ-3054 added the `VALIDATION_FILTER` env + per-validator `setup()` hook
  in `validateBehavior.js` specifically to enable this skill's loop.
