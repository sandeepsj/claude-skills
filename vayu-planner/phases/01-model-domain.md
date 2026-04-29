# Phase 01 — Model the Domain in Types

**Goal:** encode the problem in data types so that illegal states are unrepresentable, not merely unchecked.

## The core move

Every field you add is a contract. Every `Maybe` is a deferred decision. Every `String` is an invitation for bad data. The job of this phase is to push as much correctness into types as the compiler can verify.

## Tools of the trade

### ADTs — sum + product
Sum types model *"is one of"*, product types model *"is all of"*. When in doubt between a boolean flag + field, and two constructors — prefer two constructors. The compiler will force exhaustive matching.

```haskell
-- Worse: impossible combinations compile
data Order = Order { status :: OrderStatus, shippedAt :: Maybe UTCTime, cancelledReason :: Maybe Text }

-- Better: each state carries exactly what it needs
data Order
  = Pending   PendingOrder
  | Shipped   ShippedOrder
  | Cancelled CancelledOrder
```

### Newtypes for domain meaning
A `CustomerId` and an `OrderId` are both `Text` at runtime, but they must not be interchangeable at compile time. Wrap them.

```haskell
newtype CustomerId = CustomerId { unCustomerId :: Text } deriving (Eq, Ord, Show)
```

Add **smart constructors** when validity is non-trivial: export the type but not the data constructor, and offer `mkEmail :: Text -> Either ValidationError Email`.

### Phantom types for state machines
Encode "this order has been paid for" in a type parameter the compiler tracks. See the `phantom-types-state-machine` template.

### Refined types (optional)
`refined`, `liquid-haskell`, or hand-rolled invariants via smart constructors. Worth it for invariants that would cost real money if violated (amount ≥ 0, email format, non-empty list).

### Non-empty lists
If a function requires "at least one", use `Data.List.NonEmpty`, not `[a]` + a runtime check.

## The `Maybe` discipline

A `Maybe` in a record field is a claim: *this is genuinely absent sometimes and the caller must deal with it*. If it's absent because "we didn't look it up yet", that's a different type:

```haskell
-- Wrong: collapses "not fetched" and "genuinely null"
data User = User { email :: Maybe Text }

-- Right: distinguishes
data FetchedUser  = FetchedUser  { email :: Email }
data PartialUser  = PartialUser  { emailLookupPending :: () }
```

## Scaling — how this holds up as the codebase grows

- Types are a communication channel; they travel across PRs better than docs do.
- When a new constructor is added to an enum, every exhaustive `case` surfaces as a warning — that's the point. **Do not add wildcard catch-alls (`_ -> ...`)** just to silence the warning; that defeats the mechanism.
- Keep domain types in modules separate from transport/storage representations. Map at the boundary.

## What to output

- Concrete Haskell type declarations for every noun in the problem
- Smart constructors (signatures at least) for anything with validity constraints
- A 1-line justification for each `Maybe` ("absent when user hasn't set shipping address yet")
- A 1-line justification for each type parameter / phantom

## Next phase

`choose-effects` — decide how side effects are expressed.
