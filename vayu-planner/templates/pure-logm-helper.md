# Template — Pure Helper in `LogM`

The default shape for a helper that needs to emit structured logs but does **not** need Flow effects. Writer-over-DList monad; compiler-enforced purity; unit-testable without a Flow harness.

## When to reach for `LogM`

Write the helper in `Vayu.Utils.LogM` when it needs **none** of:
- DB queries
- HTTP calls
- Redis / cache reads
- Config / feature-flag reads
- Request context (shopUrl, sessionId, requestId injection beyond what's already in args)
- The clock (no `getCurrentTime`, no delays)
- `throw` / `logAndThrowErr*` (LogM has no error-throw primitive)

If any of those are required, stay in `Flow` and use `Vayu.Product.Logger.withProductAPILogging` / `withFunctionLogging`. See the `product-function` template.

## Shape

```haskell
module Vayu.Product.Cart.DiscountSplit (applyDiscounts) where

import Data.Aeson ((.=))
import qualified Vayu.Utils.LogM as LogM
import qualified Vayu.Generated.Types.Common.Cart as Cart

-- Pure + logged. Takes everything it needs as plain values; returns LogM.
applyDiscounts
  :: Cart.Cart
  -> [Discount]
  -> LogM.LogM Cart.Cart
applyDiscounts cart discounts =
  LogM.withFunctionCallLogging
    "applyDiscounts"
    [ "cartId"    .= Cart.cartId cart
    , "discounts" .= length discounts
    ]
    $ do
      let (applied, rejected) = splitByEligibility cart discounts
      LogM.logInfo "applyDiscounts"
        [ "applied" .= length applied, "rejected" .= length rejected ]
      when (null applied && not (null rejected)) $
        LogM.logFailure "applyDiscounts" "all discounts rejected"
      pure (applyAll cart applied)
```

## Primitives (all `LogM`, all pure — mirror Flow-side names)

| LogM op | Signature |
|---------|-----------|
| `logInfo` | `Text -> [Pair] -> LogM ()` |
| `logErrorDetails` | `Text -> [Pair] -> LogM ()` |
| `logFailure` | `Text -> Text -> LogM ()` |
| `logException` | `Text -> Text -> LogM ()` |
| `logFunctionCalled` | `Text -> [Pair] -> LogM ()` |
| `logFunctionCallResult` | `ToJSON a => Text -> a -> LogM a` |
| `withFunctionCallLogging` | `ToJSON a => Text -> [Pair] -> LogM a -> LogM a` |

Same names, same semantics as `Vayu.Services.Logger.Logger`. Import qualified as `LogM` to avoid clashing with the Flow-side module.

## Runners

| Runner | Signature | Use |
|--------|-----------|-----|
| `runLogMPure` | `LogM a -> (a, [LogEntry])` | Tests — returns the result plus the ordered entry list. No Flow setup required. |
| `runLogM` | `LogM a -> FlowMonad.Flow a` | Production — replays every entry through `Logger.logEvent`, so context enrichment (requestId, sessionId, shop context, serial numbering, transport dispatch) applies exactly as it would for native Flow-side logging. |

## Flow-boundary usage

```haskell
-- In a Flow caller (Product / Services / handler):
handler cart discounts = do
  cart'   <- LogM.runLogM (applyDiscounts cart discounts)  -- logs flush HERE
  persist cart'
```

`runLogM` is the **only** lift point. Everything above it in the call stack stays pure.

## Composition — chain LogM with `>>=`, not with `runLogM`

```haskell
-- Correct: two LogM helpers compose purely, single Flow boundary
pipeline :: Cart.Cart -> LogM.LogM Cart.Cart
pipeline cart =
  applyDiscounts cart []           -- LogM Cart
    >>= normaliseLineItems         -- Cart -> LogM Cart
    >>= recomputeTotals            -- Cart -> LogM Cart

-- In Flow:
result <- LogM.runLogM (pipeline cart)

-- WRONG — never lift mid-chain; you lose accumulated entries' ordering and
-- force the caller into Flow for no reason.
result <- do
  c1 <- LogM.runLogM (applyDiscounts cart [])
  c2 <- LogM.runLogM (normaliseLineItems c1)
  LogM.runLogM (recomputeTotals c2)
```

## What's absent (by design)

- No `logDebug` / `logWarning` — the Flow-side Logger has neither; LogM stays symmetric.
- No clock / time primitives — reading time is a Flow effect. Take `LocalTime` as a parameter if the helper needs it.
- No DB / HTTP / Redis / config primitives — those are Flow-only.
- No throw / `logAndThrowErr*` — return `Either e a` or `Maybe a` from `LogM`; the Flow caller decides how to surface the failure.
- No `MonadIO` / `MonadTrans` / `MonadFlow` instance — attempting any Flow operation inside LogM is a **type error**, which is the whole point.

## Testing — zero Flow harness

```haskell
-- test/Product/Cart/DiscountSplitSpec.hs
import Test.Hspec
import qualified Vayu.Utils.LogM as LogM
import Vayu.Product.Cart.DiscountSplit (applyDiscounts)

spec :: Spec
spec = describe "applyDiscounts" $ do
  it "applies eligible discounts and logs the split" $ do
    let (cart', entries) = LogM.runLogMPure (applyDiscounts sampleCart sampleDiscounts)
    Cart.totalAmount cart' `shouldBe` expectedTotal
    length entries `shouldBe` 4   -- function-called, info, function-result, + optional failure

  it "emits a failure entry when nothing is eligible" $ do
    let (_, entries) = LogM.runLogMPure (applyDiscounts sampleCart [])
    any isFailureEntry entries `shouldBe` True
```

No container stack, no DB, no Flow runtime. Just values in, values + log entries out.

## Migration pattern — Flow-only helper → LogM

```haskell
-- Before: lived in Flow purely to call Logger.logInfo
rightToMaybeWithLogs
  :: (ToJSON e) => Text -> Either e r -> FlowMonad.Flow (Maybe r)

-- After: same shape, pure, caller lifts at the Flow boundary
rightToMaybeLogged
  :: (ToJSON e) => Text -> Either e r -> LogM.LogM (Maybe r)

-- Callers change one line:
-- Flow: maybeVal <- rightToMaybeWithLogs tag eResult
--  →    maybeVal <- LogM.runLogM (rightToMaybeLogged tag eResult)
```

See real example at `src/Vayu/Utils/Extra.hs:89–91`.

## Hard rules

1. **Pick the monad consciously.** If the helper needs Flow effects, use `Flow` + `withFunctionLogging`. If it doesn't, use `LogM` + `withFunctionCallLogging`. Don't hybridise — there is no LogM-over-Flow escape hatch.
2. **Never `runLogM` inside a `LogM` chain.** Compose with `>>=` and lift once at the boundary.
3. **Take effectful data as parameters.** If the helper needs a fresh timestamp or a config value, take it in as an argument; don't drag it in via Flow.
4. **Tests use `runLogMPure`.** No `withFlowRuntime`, no test containers, no mocks.

## References

- Module: `src/Vayu/Utils/LogM.hs`
- Design: `plans/pure-logging/00-overview.md`, `plans/pure-logging/01-usage.md`
- Real usage: `src/Vayu/Product/Cart/Discount.hs` (`applyBundleDiscounts`, a pure helper with logging); `src/Vayu/Product/Checkout/Orchestrator.hs` (Flow caller using `runLogM` at the boundary); `test/LogMSpec.hs` (composition + assertion pattern)
