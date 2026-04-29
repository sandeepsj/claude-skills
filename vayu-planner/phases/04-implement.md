# Phase 04 — Implement (Vayu)

**Goal:** fill in the bodies, honouring both generic Haskell rules and Vayu's layered-architecture + logging discipline.

## Layered architecture — which file does this go in?

```
Generated/API.hs → Routes/Core.hs → Product/<Domain>/<Feature>.hs
                                  → Services/Internal/<Domain>/*.hs (single-domain logic + Generated queries)
                                  → Services/External/<Integration>/*.hs (outbound HTTP)
```

| Layer | Path | Allowed | Forbidden |
|-------|------|---------|-----------|
| Generated | `src/Vayu/Generated/` | READ ONLY — regenerate via YAML + `pnpm run generate:api:backend` | Any edit |
| Routes/Core | `src/Vayu/Routes/Core.hs` | Extract headers, call Product, return | Business logic, logging |
| Product | `src/Vayu/Product/<Domain>/` | Cross-domain orchestration; import Services/Internal, other Product modules, `Storage.Redis` | Import `Generated.Queries`, `Generated.Types.Storage`, `Storage.Queries` directly |
| Services/Internal | `src/Vayu/Services/Internal/<Domain>/` | Single-domain business logic; Generated queries; Storage queries | Cross-domain orchestration — move to Product |
| Services/External | `src/Vayu/Services/External/<Integration>/` | Outbound HTTP via Generated network-calls | DB access |
| Types | `src/Vayu/Types/` | Hand-written types not covered by Generated | Business logic |
| Utils | `src/Vayu/Utils/` | Generic helpers | Domain-specific code |

**If this function links two domains (Cart + Customer, Shipping + Payment), it's Product.** Single-domain logic belongs in Services/Internal. If you find Product code that reads DB directly, fix it — the correct move is a Services/Internal function.

## Non-negotiable Haskell rules

1. **No partial functions** — `fromJust`, `head`, `tail`, `last`, `init`, `!!`, `read`. Use pattern match, `listToMaybe`, `lastMaybe`, `readMaybe`, `fromMaybe`, `Data.Map.lookup`.
2. **No `undefined` / `error`** in shipped code. Return `Either` / `Maybe`.
3. **Exhaustive case matches.** No `-fno-warn-incomplete-patterns` pragmas. Either list every constructor or use a wildcard that returns a safe default (like `_ -> pure Nothing`) — and the default must be *demonstrably safe*, not just convenient.
4. **No orphan / overlapping / incoherent instances.**
5. **All case matches on enums from YAML MUST be exhaustive.** When a new enum value is added, the compiler must force you to handle it. Missing cases crash the pod at runtime.

## Logging discipline

### Product layer — MUST use wrappers

```haskell
-- API-facing (handler entry point from Core.hs):
ProductLogger.withProductAPILogging "createSession" Logger.POST url ["body" .= req] $ do
  ...

-- Internal helper still in Flow:
ProductLogger.withFunctionLogging "buildResponse" ["customerId" .= cid] $ do
  ...
```

**Never** write the legacy two-liner (`logProductAPIRequest` + `logProductAPIResponse`) — that's the pre-refactor pattern. **Never** scatter `logInfo` calls inside a wrapped body — the wrapper does input/output logging automatically.

### Pure helpers — prefer `LogM`

If the helper needs no Flow effects (phase 2's decision tree), write it in `LogM`:

```haskell
import qualified Vayu.Utils.LogM as LogM

applyBundleDiscounts :: Cart -> [Discount] -> LogM.LogM Cart
applyBundleDiscounts cart discounts =
  LogM.withFunctionCallLogging "applyBundleDiscounts" ["cartId" .= cartId cart] $ do
    ...
```

Flow callers lift once: `result <- LogM.runLogM (applyBundleDiscounts cart ds)`.

See `pure-logm-helper` template for full details.

## Operator-style composition

For 1–2 step monadic chains, operators read better than `do`:

```haskell
-- Prefer
findCustomer cid >>= maybe (pure []) fetchOrders

-- Not
do mCustomer <- findCustomer cid
   case mCustomer of
     Nothing -> pure []
     Just c  -> fetchOrders c
```

Reserve `do` for flows with **3+ reused bindings** or **nested case analysis**.

Key operators (see `operators` quick-ref for the full set):
- `>>=`, `=<<` — bind
- `>>`, `*>`, `<*` — sequence with discard
- `<$>`, `<&>` — fmap (right-to-left vs left-to-right)
- `<*>` — applicative apply
- `>=>`, `<=<` — Kleisli compose

Vayu-specific helpers from `Vayu.Utils.Maybe` (225+ feature-flag extractors + operators live in `Utils.Breeze`):
- `>>=?` — bind if Just, stop on Nothing
- `>>=??` — similar over `Maybe (Either e a)`
- `>.` — transform the value, discarding the wrapping monad's effect
- `>$` — replace
- `?.`, `??.` — fmap through `Maybe`

Before writing a helper, grep `Vayu.Utils.*` — there are 400+ functions. See `plan/16-utils-reference.md`.

## Common conversions

- **Storage ↔ Common**: `Types.Storage.X` (DB shape) to `Types.Common.X` (API shape) via `fromGenType` / `toGenType`. Always convert Storage → Common before returning from an API handler.
- **Servant handler parameters**: path captures → query params → request body → headers (in declaration order). All headers are `Maybe Text` even if marked required — validate in the handler.

## Naming

- Functions: `verbNoun` or `nounVerb`, consistent within a module.
- Types: `PascalCase`.
- Modules match filesystem path.
- Don't abbreviate unless conventional (`env`, `cfg`, `ctx` ok; `cust`, `ord` not).

## What to output

- Working code for every signature from phase 3.
- Each Product function wrapped in a logger or written in `LogM`.
- Zero new partials. Exhaustive cases everywhere.
- Any new helper — checked against `Vayu.Utils.*` first.

## Next phase

`test` — prove it.
