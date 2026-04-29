# Template — Product Orchestration Function

Product links multiple domains together. Lives under `src/Vayu/Product/<Domain>/`. MUST use the logger wrappers from `Vayu.Product.Logger`.

## API-facing function (called from `Routes/Core.hs`)

```haskell
module Vayu.Product.Customer.Session (createSession) where

import Data.Aeson ((.=))
import EulerHS.Prelude
import qualified FlowMonad
import qualified Vayu.Generated.Types.Common.Customer as GenTypes
import qualified Vayu.Product.Logger as ProductLogger
import qualified Vayu.Services.Internal.Customer.Customer as CustomerSvc
import qualified Vayu.Services.External.NotificationService.NotificationService as NotifSvc
import qualified Vayu.Services.Logger.Logger as Logger

createSession
  :: GenTypes.CreateCustomerSessionRequest
  -> Text             -- shopUrl
  -> Maybe Text       -- auth
  -> Maybe Text       -- reqId
  -> FlowMonad.Flow GenTypes.CreateCustomerSessionResponse
createSession reqBody shopUrl _auth mReqId =
  ProductLogger.withProductAPILogging
    "createSession"
    Logger.POST
    "/customer/session"
    [ "reqBody" .= reqBody, "shopUrl" .= shopUrl ]
    $ do
      customer <- CustomerSvc.findOrCreateCustomer shopUrl reqBody
      NotifSvc.sendWelcomeIfNew shopUrl customer
      buildResponse customer mReqId
```

## Internal helper (called from other Product modules)

```haskell
buildResponse
  :: GenTypes.Customer
  -> Maybe Text
  -> FlowMonad.Flow GenTypes.CreateCustomerSessionResponse
buildResponse customer mReqId =
  ProductLogger.withFunctionLogging
    "buildResponse"
    [ "customerId" .= GenTypes.customerId customer ]
    $ do
      token <- generateSessionToken customer
      pure $ GenTypes.CreateCustomerSessionResponse
        { sessionToken = token
        , customer     = customer
        , requestId    = mReqId
        }
```

## Hard rules

- **Always** use `withProductAPILogging` or `withFunctionLogging` **when the body is genuinely Flow-bound** (touches DB, HTTP, Redis, config, clock, or throw). Do NOT scatter `logInfo` calls inside the body — the wrapper handles input/output logging automatically.
- **If the helper needs no Flow effects**, write it in `LogM` instead of `Flow` — see the `pure-logm-helper` template. Flow wrappers stay reserved for genuinely Flow-bound code; LogM is the default for pure helpers that happen to need logs.
- **Never** write the legacy two-liner `logProductAPIRequest` + `logProductAPIResponse` — that's the pre-refactor pattern.
- **Do not import** from `Vayu.Generated.Queries.*`, `Vayu.Generated.Types.Storage.*`, or `Vayu.Storage.Queries.*`. Route DB access through a `Services/Internal` module.
- **May import** from `Vayu.Storage.Redis` directly — Redis is generic cache access.
- **May import** other `Vayu.Product.*` modules — cross-domain orchestration is the whole point of this layer.
- If this function stops involving more than one domain, move it down into `Services/Internal`.

## Cross-domain composition

```haskell
placeOrder req shopUrl =
  ProductLogger.withProductAPILogging "placeOrder" Logger.POST "/orders" ["req" .= req] $ do
    cart     <- CartProduct.lockCart (cartId req) shopUrl
    customer <- CustomerSvc.requireCustomer shopUrl (customerId req)
    shipment <- ShippingProduct.quote cart (address req)
    payment  <- PaymentProduct.charge customer (amount req)
    OrderSvc.persist (toOrder cart customer shipment payment)
```

Each domain call lives in its own module. Product stitches them.
