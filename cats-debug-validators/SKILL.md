---
name: cats-debug-validators
description: Debug a failing CATS behavioral validator in the Vayu repo. Identifies which Vayu code-path gate short-circuited (isFallbackUpdateUsed, shouldAlwaysAskAddress, shouldEnableDefaultFlipkartIngestion, VERIFIED_ONLY state filter, validateIngestedUserEmail) and where Flipkart-extracted UserInfo actually lands (prefillData, NOT tokenData or customer.*). Includes the JSON field-naming gotcha (dropPrefix strips all leading underscores), the LocalTime date-format gotcha, and the canonical iteration loop. Use when a CATS validator passes 4xx/5xx-style HTTP checks but the assertions on response body or DB state are wrong, especially when /otp/verify "succeeds" but downstream side effects are missing.
allowed-tools: Bash, Read, Grep, Glob
---

# Debugging CATS behavioral validators

How to find out why a CATS behavioral validator in the Vayu repo is failing. Distilled from the BZ-1217 debug cycle (8 iterations across `pnpm run test:cats:functional` runs).

## When to use this skill

- A behavioral validator fails on `body.tokenData.*` or `customer.*` assertions while the HTTP call returns 200.
- `/otp/verify` returns success but a downstream side effect (Flipkart address ingestion, customer name/email update) is missing.
- A mock fixture under `scripts/cats/payloads/` "should" produce expected behavior but doesn't.
- A field in a mock JSON file is silently dropped during Vayu's Aeson decode.

## The three log surfaces, ranked by usefulness

| Source | What it tells you | How to enable |
|---|---|---|
| **Vayu's DB log table** | Every `Logger.logFunctionCalled`/`logInfo`/`logFailure` call inside Vayu, with session ID. **Most useful.** Lets you trace one /otp/verify request end-to-end. | Add `export LOG_TRANSPORTERS=CONSOLE,DATABASE` to `scripts/cats/helper/env.sh` for the debug run; remove when done. Read via `queryDB('SELECT … FROM public.log …')` from a validator. |
| **CATS proxy log** | Every inbound HTTP request the proxy received, plus the rewrite path it took. Useful for "did Vayu's outbound Flipkart call reach the mock?". | Always on. File: `scripts/cats/output/cats-server.log`. |
| **Vayu stdout** | What CONSOLE transporter prints. Same content as the DB log table but in raw text. | Always on. Lives in the macOS Terminal window osascript opens (or in CI container logs). To capture to a file in non-CI, edit `init-test.sh:1001/1009` to add `\| tee /tmp/vayu-cats.log` to the `stack run` command for the run, revert after. |

**Default to the DB log table.** It's the same data Vayu would emit to Loki in prod, structured, queryable by session ID. Don't reach for `tee` unless DB logging is unreachable.

## Enable DB logging (temporary)

Add to `scripts/cats/helper/env.sh`:
```bash
export LOG_TRANSPORTERS=CONSOLE,DATABASE
```

The DATABASE transporter writes to `public.log` in `catsdb` (host port 5433). Vayu creates the table on startup via BreezeDB migrations.

**Remove after debugging** — the DB write per log line slows the run measurably, and noisy log volume in CI is wasteful.

## Reading the log from a validator

Inside any validator that has `queryDB` available (see `flipkart-ingest-common.js`):

```js
const rows = await queryDB(
  `SELECT timestamp, level, label, payload
     FROM public.log
    WHERE "sessionId" = $1
      AND label IN ('flipkartIngestionFlow','fetchUserDataFromShop','extractUserDetails')
    ORDER BY timestamp`,
  [sessionId]
);
rows.forEach((r) => console.log(`${r.label}: ${JSON.stringify(r.payload).slice(0, 400)}`));
```

If you don't have the session ID, grep by request path or label first to find one.

## Common gates that silently short-circuit /otp/verify → Flipkart ingestion

Each of these returns "success" at the HTTP layer but skips the ingestion path. Look for these specifically:

| Gate | File:line | Symptom |
|---|---|---|
| `isFallbackUpdateUsed=True` | `Identity/Main.hs:450` | Skip `updateIngestedCustomer` → no `fetchUserDataFromShop` → no Flipkart call. Triggered when platform login returns no credentials AND `isMultiPassEnabledForShop=True`. |
| `shouldAlwaysAskAddress=True` | `Identity/Main.hs:448`, `FlowMonad.hs:1130` | Same effect. Triggered when customer is in the `alwaysAskAddressForCustomerIds` config list. |
| `shouldEnableDefaultFlipkartIngestion=False` | `Ingestion/Utils.hs:31` | `fetchUserDataFromShop` runs but `flipkartIngestionFlow` doesn't. Requires `ENABLE_DEFAULT_FLIPKART_ADDRESS_INGESTION=True` AND shop config `disableDefaultFlipkartIngestion ≠ True`. |
| `userIngestionFlag=False` | `Product/Utils.hs#saveCustomerDetails` | Reads `shop.config.ingestUserDetails`. Defaults True. |
| `state ≠ "VERIFIED"` on Flipkart login response | `Flipkart/Main.hs:216` | When `addressSelectionLogic = VERIFIED_ONLY` (default for `default-integration` fkConfigName), only login items with `state = "VERIFIED"` pass through. Returns `Right []` — no addresses fetched. |
| `validateIngestedUserEmail` strips email | `Product/Utils.hs:334` | If the email's domain has no DNS MX record (e.g. `example.com`), Vayu strips it before writing to customer. Doesn't affect `prefillData`, but does affect `customer.emailAddress` writes for new users. |

## Where Flipkart-extracted UserInfo actually lands

`FlipkartUtils.extractUserInfo` output → `BreezeIngestedCustomer.{_first_name,_last_name,_email}` → consumed by:

1. **`prefillData` in `/otp/verify` response** (Customer/Main.hs:815). This is the **canonical observable** — has the synthesis output as `{name, email}`. Don't expect anything else.
2. **`saveCustomerDetails` → `saveUserDetailsForNewUser` → updates customer.name/emailAddress** — but only via `ingestWithPlatformOnly` (non-Flipkart-tenant path). For Flipkart-tenant shops, `flipkartIngestionFlow` sets `_userDetails = Nothing` (TODO comment on line 815). So **don't expect customer.name/emailAddress to be updated** by Flipkart ingestion.

**Implication for validators**: assert on `body.prefillData.name` and `body.prefillData.email` — NOT on `body.tokenData.name` (that's from the pre-ingestion customer row) and NOT on `customer.name`/`customer.emailAddress` (not written for Flipkart tenants).

## JSON field naming for Flipkart mock fixtures

Vayu's generated Haskell types use the `dropPrefix` field-label modifier (`src/Vayu/Types/FieldModifiers.hs`). It strips ALL leading underscores: `_id` → `id`, `__type` → `type`, `_primary_email` → `primary_email`.

So mock JSON keys must match the **stripped** form. The trap: YAML schema shows `_type` (single underscore for the reserved-word convention), Haskell record field is `__type` (double), JSON key must be `type` (zero).

| YAML schema | Haskell field | JSON key |
|---|---|---|
| `_type` | `__type` | `type` |
| `id` | `_id` | `id` |
| `first_name` | `_first_name` | `first_name` |

If a mock field is silently absent from the parsed Haskell record (visible as Nothing in the logged response), it's almost certainly a key-name mismatch.

## Date-time format for `format: date-time` fields

Haskell parses `LocalTime` from `"YYYY-MM-DD HH:MM:SS"` (space-separated, no Z, no offset).

ISO 8601 with `Z` (`"2026-05-01T10:00:00Z"`) fails with `could not parse date: endOfInput`.
ISO 8601 with `+00:00` (`"2026-05-01T10:00:00+00:00"`) also fails.

Use `"2026-05-01 10:00:00"` for `format: date-time` fields in mock JSON.

## Iterating fast

- `pnpm run test:cats:functional` is the right loop (~2 min). Avoid `:commit` (~40 min) while debugging.
- Always `podman compose down -v --remove-orphans` between runs so the postgres container reloads `hydrate-database.sql`. Stale DB state silently breaks dedup assertions.
- After Haskell source edits, `touch src/Vayu/.../Foo.hs` before re-running if `stack build --fast` doesn't appear to pick up changes (rare, but possible with incremental detection).
- When you change a mock fixture (`scripts/cats/payloads/flipkart-mock-table.json`), no rebuild needed — `common.js`'s `handleFlipkartMock` re-reads it per request.
