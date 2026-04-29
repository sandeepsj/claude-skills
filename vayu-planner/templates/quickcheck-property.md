# Template — QuickCheck / Hedgehog Property Test

## The shape of a good property

```haskell
module Domain.MoneySpec (spec) where

import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck

import Domain.Money

spec :: Spec
spec = describe "Money" $ do
  prop "addition is commutative"   prop_addCommutative
  prop "addition is associative"   prop_addAssociative
  prop "zero is a left identity"   prop_zeroIdentity
  prop "subtract . add = id"       prop_subAddInverse

prop_addCommutative :: Money -> Money -> Property
prop_addCommutative a b = a `addMoney` b === b `addMoney` a

prop_addAssociative :: Money -> Money -> Money -> Property
prop_addAssociative a b c =
  (a `addMoney` b) `addMoney` c === a `addMoney` (b `addMoney` c)

prop_zeroIdentity :: Money -> Property
prop_zeroIdentity a = zeroMoney `addMoney` a === a

prop_subAddInverse :: Money -> Money -> Property
prop_subAddInverse a b =
  (a `addMoney` b) `subMoney` b === a
```

## Arbitrary instances — stay honest

```haskell
instance Arbitrary Money where
  arbitrary = Money <$> choose (0, 1_000_000_00)   -- cents, 0 to 1M dollars
  shrink (Money n) = Money <$> shrink n
```

**Don't skip `shrink`.** Without it, failure reports show 47-line counterexamples. With it, you get the minimal one.

## Newtypes for generator intent

When a test needs "only positive ints" or "non-empty strings":

```haskell
newtype PositiveInt = PositiveInt Int deriving Show
instance Arbitrary PositiveInt where
  arbitrary = PositiveInt . getPositive <$> arbitrary

prop_divides :: PositiveInt -> Int -> Property
prop_divides (PositiveInt d) n = (n `div` d) * d + (n `mod` d) === n
```

Better than filtering inside the property with `==>`, which wastes generator runs.

## Hedgehog version

```haskell
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

prop_addCommutative :: Property
prop_addCommutative = property $ do
  a <- forAll (Gen.integral (Range.linear 0 1_000_000))
  b <- forAll (Gen.integral (Range.linear 0 1_000_000))
  Money a `addMoney` Money b === Money b `addMoney` Money a
```

Hedgehog's integrated shrinking is better than QuickCheck's; prefer it for new code.

## What to test as a property

- **Round-trip**: `decode . encode = Just`
- **Idempotence**: `normalise . normalise = normalise`
- **Algebraic law**: associativity, commutativity, distributivity
- **Invariant**: "after any sequence of ops, balance ≥ 0"
- **Equivalence to reference**: a slow obviously-correct version agrees with the optimised one

## What NOT to property-test

- Parsers with specific error messages (example tests)
- Exact numeric output where precision matters (example tests; assert within epsilon)
- Anything where "randomise the input" yields nonsense inputs for the function's domain
