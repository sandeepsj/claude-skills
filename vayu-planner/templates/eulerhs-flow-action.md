# Template — EulerHS Flow Action (Services/Internal)

A single-domain Flow action. Lives under `src/Vayu/Services/Internal/<Domain>/`. Can import Generated queries; cannot call Product.

## Shape

```haskell
module Vayu.Services.Internal.Customer.Customer
  ( findCustomerByEmail
  , upsertCustomer
  ) where

import EulerHS.Prelude
import qualified FlowMonad
import qualified Vayu.Generated.Queries.Customer as CustomerQ
import qualified Vayu.Generated.Types.Storage.Customer as StorageCustomer
import qualified Vayu.Generated.Types.Common.Customer as CommonCustomer
import qualified Vayu.Types.Common.Error as Err
import Vayu.Utils.Maybe ((>>=?), (>.), (?.))

findCustomerByEmail
  :: Text              -- shopUrl
  -> Text              -- email
  -> FlowMonad.Flow (Maybe CommonCustomer.Customer)
findCustomerByEmail shopUrl email =
  CustomerQ.findByEmail shopUrl email
    >>=? \storageC -> pure (Just (CommonCustomer.fromGenType storageC))
```

## Rules for this layer

- Single domain only. If you need two domains, the orchestration belongs in Product.
- Convert `Storage.X` → `Common.X` before returning anything public.
- Never `fromJust` / `head` / `!!`. Use `>>=?`, `>.`, `listToMaybe`, pattern match.
- Return `Maybe` for "might not exist", `Either Err.Error` for "failed with reason".
- No logging calls in this layer — logging lives at the Product boundary.
- Exhaustive case matches on enums (e.g. `PaymentStatus`). No `_ -> defaultValue` unless documented.

## Error handling

```haskell
import qualified Vayu.Types.Common.Error as Err

activateCustomer
  :: Text
  -> CommonCustomer.CustomerId
  -> FlowMonad.Flow (Either Err.Error CommonCustomer.Customer)
activateCustomer shopUrl cid =
  CustomerQ.findById shopUrl cid >>= \case
    Nothing -> pure (Left (Err.NotFound ("customer:" <> unCustomerId cid)))
    Just sc | isBanned sc -> pure (Left Err.Forbidden)
            | otherwise   -> CustomerQ.updateActive shopUrl cid True
                                >> pure (Right (CommonCustomer.fromGenType sc))
```

Prefer explicit `case` when branching on validation; operator chains when linearly transforming.

## Regeneration reminders

- If this module references a new query, add it to `doc/DBQueries.yaml` and run `pnpm run generate:db:backend` before expecting it to compile.
- If the input/output types change shape, update `doc/schemas/` and run `pnpm run generate:api:backend`.
- Never hand-edit anything under `src/Vayu/Generated/`.
