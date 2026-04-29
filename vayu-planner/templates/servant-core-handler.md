# Template — Servant Core Handler (Routes/Core.hs)

Handler for an endpoint defined in `doc/paths/` and registered in `doc/Api.yaml`. The function name must match the kebab-case `operationId` converted to camelCase.

## Shape

```haskell
-- Matches operationId: create-customer-session
createCustomerSession
  :: GenTypes.CreateCustomerSessionRequest    -- request body
  -> Maybe Text                               -- X-Shop-Url header (always Maybe Text)
  -> Maybe Text                               -- Authorization header
  -> Maybe Text                               -- X-Request-Id header
  -> FlowHandler GenTypes.CreateCustomerSessionResponse
createCustomerSession reqBody mShopUrl mAuth mReqId = do
  shopUrl <- requireHeader "X-Shop-Url" mShopUrl
  Product.Customer.Session.createSession reqBody shopUrl mAuth mReqId
```

## Rules

- **Parameter order must match the Servant route type**: path captures, then query params, then request body, then headers in declaration order.
- **All headers are `Maybe Text`** in the handler, even if marked required — Servant leaves header validation to the handler.
- **No logging here** — logging wraps the Product call.
- **No business logic here** — the handler's job is to extract headers, call into Product, and return. If you find yourself composing Services calls here, move them to Product.
- **No `fromJust` on headers** — use a helper like `requireHeader` that returns a proper error, or pattern-match on `Maybe` and throw the appropriate 4xx.

## Error propagation

```haskell
requireHeader :: Text -> Maybe Text -> FlowHandler Text
requireHeader name = \case
  Just v  -> pure v
  Nothing -> throwError (Servant.err400 { errBody = encodeText ("Missing header: " <> name) })
```

Domain errors from Product should be translated to HTTP errors in ONE place — either here at the handler boundary, or via a middleware. Not both.

## When a new handler is added

1. Define schema + path in `doc/schemas/` and `doc/paths/`.
2. Reference the path in `doc/Api.yaml` (position matters — Servant tries routes top-down).
3. `pnpm run generate:api:backend`.
4. Implement the handler in `Core.hs` with exact name matching the kebab-case `operationId`.
5. Delegate to `Vayu.Product.<Domain>.<Feature>.<function>`.
