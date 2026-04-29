# Template — Tagless-Final Service

Use when a capability needs multiple interpreters (prod, test, staging) and you want the business logic not to name the runtime.

## The class

```haskell
-- Service/Customer/Class.hs
module Service.Customer.Class
  ( MonadCustomer (..)
  ) where

import Domain.Customer (Customer, CustomerId)

class Monad m => MonadCustomer m where
  findCustomer :: CustomerId -> m (Maybe Customer)
  saveCustomer :: Customer   -> m ()
  listActive   :: m [Customer]
```

**Laws** (document in Haddock):
- `saveCustomer c >> findCustomer (customerId c) = saveCustomer c >> pure (Just c)`
- `findCustomer` is idempotent within a transaction

## The production instance

```haskell
-- Service/Customer/DB.hs
module Service.Customer.DB () where

import Service.Customer.Class
import qualified Storage.Queries.Customer as Q

instance MonadCustomer AppM where
  findCustomer = Q.findById
  saveCustomer = Q.upsert
  listActive   = Q.listWhereActive
```

(`AppM` is your app's monad — `ReaderT AppEnv IO`, a Flow alias, whatever.)

## The test instance

```haskell
-- test/Service/Customer/InMemory.hs
newtype InMemoryCustomerT m a = InMemoryCustomerT
  { runInMemoryCustomerT :: StateT (Map CustomerId Customer) m a }
  deriving (Functor, Applicative, Monad, MonadState (Map CustomerId Customer))

instance Monad m => MonadCustomer (InMemoryCustomerT m) where
  findCustomer cid = gets (Map.lookup cid)
  saveCustomer c   = modify (Map.insert (customerId c) c)
  listActive       = gets (filter isActive . Map.elems)
```

Now business logic depending on `MonadCustomer` runs unchanged against either.

## Business logic uses the capability

```haskell
greetIfNew :: (MonadCustomer m, MonadLogger m) => CustomerId -> m ()
greetIfNew cid =
  findCustomer cid >>= \case
    Just c | isNew c -> logInfo "greet" ["cid" .= cid] *> sendWelcome c
    _                -> pure ()
```

## When this is overkill

- If there will only ever be one implementation, use a record of functions or just call the functions directly.
- If the "mock" is just returning constants, inlining the constant in tests is shorter than wiring up an instance.

## When to reach for it

- External services you want to fake in tests without a network.
- Database access where you want a fast in-memory store for unit tests.
- Anything behind a feature flag where both behaviours need to coexist cleanly.
