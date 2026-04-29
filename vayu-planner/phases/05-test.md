# Phase 05 — Test (Vayu)

**Goal:** prove the implementation, in the style Vayu's test infrastructure supports.

## Run the suite

Always through the canonical wrapper:

```bash
npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec'
```

**Not** `stack test` — bypasses dotenv, loses env vars for DB/Redis/external endpoints. The `vayu-test` skill wraps this with a failure summariser; prefer that in practice.

Filter a run:

```bash
npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec' -- --match "Cart"
```

## LogM unit tests — no Flow harness needed

```haskell
import qualified Vayu.Utils.LogM as LogM
import Test.Hspec

spec :: Spec
spec = describe "applyBundleDiscounts" $ do
  it "applies eligible discounts and logs the split" $ do
    let (cart', entries) = LogM.runLogMPure (applyBundleDiscounts sampleCart sampleDiscounts)
    Cart.totalAmount cart' `shouldBe` expectedTotal
    length entries `shouldBe` 4    -- fn-called, info, fn-result, + optional failure
```

`runLogMPure :: LogM a -> (a, [LogEntry])`. Zero Flow setup, no containers, no mocks. If the helper was written in `LogM` (phase 2 default), this is the whole testing story.

## Properties where they fit

HSpec + QuickCheck:

```haskell
import Test.QuickCheck
import Test.Hspec.QuickCheck

prop "round-trips through encode/decode" $
  \x -> decodeText (encodeText x) === Just (x :: Cart)
```

Good Vayu things to property-test:
- `fromGenType . toGenType == id` for Common ↔ Storage conversions
- `decode . encode == Just` for JSON wire formats
- Pure helpers written in `LogM` — the `runLogMPure` result is a pure function of inputs, so properties compose naturally
- Canonicalisation / normalisation helpers — idempotence

Don't property-test things that are genuinely example-shaped (a specific error message, an API response structure).

## Integration tests via CATS

Real DB / Redis / external HTTP → CATS container stack. Do **not** mock these dependencies. Mocked integration tests that pass while prod crashes are worse than no tests.

- Full CATS reference: `plans/cats/reference_cats_testing.md`
- Flipkart-specific flow example: `plans/cats/reference_cats_flipkart_ingestion.md`

CATS contract tests run outside the hspec suite — they're the "does this endpoint agree with the spec" pass. If you're adding a new endpoint (see `vayu-codegen`), you likely also want a CATS case.

## Test organisation

- `test/` mirrors `src/Vayu/` structure.
- One `<Module>Spec.hs` per module you're testing.
- Fixtures in `test/fixtures/` — not multi-line string literals scattered across specs.

## Test the hard things

- **Boundary conditions** — empty, single, max size, unicode, timezone edges
- **Error paths** — does it actually return the error you think it does?
- **Serialisation edges** — nulls, missing fields, extra fields, key casing
- **Migrations** — old data still parses
- **Concurrency** — if it can race, it will race in prod

Skip:
- Tests that re-implement the function (tautology)
- Tests of derived `Show`/`Eq` trivialities
- Tests that pin down incidental implementation (breaks on harmless refactors)

## What to output

- Test file(s) for every new module / function in this change
- At least one property per non-trivial pure function, where a property makes sense
- LogM tests use `runLogMPure`, not a Flow harness
- For new endpoints: note whether a CATS contract case is also needed

## Hand-off

For actually executing the suite and reading failures, use the `vayu-test` skill. This phase is about *what* to test; `vayu-test` is about *running* it.

## Next phase

`verify` — does the full tree build, run, and satisfy the pre-commit checklist.
