# Phase 03 — Define Interfaces (Typeclasses, Laws, Instances)

**Goal:** write the *contracts* between layers before you write the bodies.

## Classes carry laws

A typeclass without laws is a trait system with extra steps. Every class you define should ship with the invariants its instances must preserve, written in Haddock or a comment. Examples:

- `Functor`: `fmap id = id`, `fmap (g . f) = fmap g . fmap f`
- `Monad`: left identity, right identity, associativity
- Your class: `findById id >>= \x -> save x = pure ()` (round-trip), `findById id` is idempotent, etc.

If you can't write a law, question whether the abstraction earns its keep. Sometimes the honest answer is "this is just a record of functions" — use a record, not a class.

## When to use a typeclass vs. a record-of-functions

| | Typeclass | Record |
|--|-----------|--------|
| One canonical implementation per type | ✓ | overkill |
| Users need to write their own instances | ✓ | ✗ |
| Runtime-swappable (feature flag, testing) | awkward | ✓ |
| Dictionary needs to be parameterised at runtime | ✗ | ✓ |
| Carries laws | ✓ | you lose compiler help |

Rule of thumb: if you'd ever want two instances for the same type, it's a record.

## Deriving — what and how

- `deriving stock (Eq, Show, Generic)` — for plain data types
- `deriving newtype (ToJSON, FromJSON, ...)` — when wrapping, reuse the inner's instances
- `deriving anyclass (ToJSON, FromJSON)` via `Generic` — generic-based derivation
- `deriving via` — most powerful: derive via a representation type (e.g. `deriving FromJSON via (SnakeCase User)`)
- `DerivingStrategies` extension — makes this explicit so nobody wonders which one fired

**Be explicit.** `deriving stock` vs `deriving newtype` vs `deriving anyclass` are semantically different, and the default changes with GHC versions. Always pick.

## Instance design

- **Orphan instances are a smell.** If you find yourself writing one, either the type or the class should move modules.
- **No `OVERLAPPING` / `OVERLAPPABLE` / `INCOHERENT` pragmas** unless you're building a library where they're load-bearing — they break reasoning.
- Keep instance method bodies small; push logic into top-level functions and let the instance call them. Easier to test, easier to reuse.

## Signatures first, bodies later

For every function this change introduces, write the signature with the most general type that still expresses intent. Too-general signatures (`a -> m a`) hide meaning; too-specific ones (`CustomerId -> IO Customer`) prevent testing. Sweet spot:

```haskell
findActiveOrders
  :: (MonadDB m, MonadTime m)
  => CustomerId
  -> m [Order]
```

If the body turns out to need a capability you didn't list, add it to the signature — don't reach into a global.

## What to output

- Typeclass definitions with law comments (or a justification for not having laws)
- Signatures for every new top-level function
- A list of instances you'll derive and via what strategy
- A list of instances you'll hand-write and why

## Next phase

`implement` — fill in the bodies.
