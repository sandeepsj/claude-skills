# Quick Reference — Safe List Operations

## The banned partials

These crash on empty / malformed input. Never use in application code.

| Banned | Replacement |
|--------|-------------|
| `head xs` | `listToMaybe xs` or pattern match |
| `tail xs` | `drop 1 xs` or pattern match |
| `last xs` | `lastMaybe xs` (from `safe` or hand-rolled) |
| `init xs` | `safeInit` or pattern match |
| `xs !! n` | `listToMaybe (drop n xs)` or use `Data.Vector.!?` / `Map.lookup` |
| `read s` | `readMaybe s` from `Text.Read` |
| `fromJust m` | `fromMaybe dflt m`, `maybe dflt f m`, or pattern match |
| `error "msg"` | return `Either` / `Maybe` |
| `undefined` | no substitute — design your types better |

## Safer idioms

```haskell
import Data.Maybe (listToMaybe, fromMaybe, mapMaybe)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import Text.Read (readMaybe)

-- First element
firstElem :: [a] -> Maybe a
firstElem = listToMaybe

-- Last element
lastElem :: [a] -> Maybe a
lastElem []       = Nothing
lastElem [x]      = Just x
lastElem (_ : xs) = lastElem xs

-- Parse an Int safely
parseCount :: String -> Maybe Int
parseCount = readMaybe

-- Pull a value or default
nameOrAnon :: Maybe Text -> Text
nameOrAnon = fromMaybe "anonymous"

-- Collect the Justs
firstNames :: [Maybe Text] -> [Text]
firstNames = mapMaybe id
```

## When you really need "at least one"

Use `NonEmpty` in the type, not a runtime check.

```haskell
-- Wrong
average :: [Double] -> Double
average xs = sum xs / fromIntegral (length xs)   -- div-by-zero on []

-- Right
average :: NonEmpty Double -> Double
average xs = sum xs / fromIntegral (NE.length xs)
```

Callers must construct a `NonEmpty` (via `NE.nonEmpty :: [a] -> Maybe (NonEmpty a)` or `x :| xs`), so empties are caught at construction, not in the average.

## Pattern matching is free totality

```haskell
-- Compiles but partial
firstTwo (x : y : _) = (x, y)

-- With -Wall, the above warns. Make it total:
firstTwo :: [a] -> Maybe (a, a)
firstTwo (x : y : _) = Just (x, y)
firstTwo _           = Nothing
```

Always handle the other branches. If "the other branches can't happen", the type is wrong.

## Maps and indexed access

```haskell
import qualified Data.Map.Strict as Map

-- Never
unsafeLookup k = m Map.! k

-- Always
Map.lookup k m :: Maybe v
```

`Vector`:
```haskell
import qualified Data.Vector as V
V.!?  :: Vector a -> Int -> Maybe a   -- safe
V.!   :: Vector a -> Int -> a         -- partial, avoid
```

## Vayu helpers — use these before rolling your own

`Vayu.Utils.Maybe` and `Vayu.Utils.Extra` already cover the common cases:

| Helper | Module | Equivalent |
|--------|--------|-----------|
| `maybeHead` | `Vayu.Utils.Maybe` | `listToMaybe` |
| `lastMaybe` | `Vayu.Utils.Extra` | safe `last` |
| `generateNanoID` | `Vayu.Utils.Extra` | UUID generation |
| `encodeText` / `decodeText` | `Vayu.Utils.Aeson` | JSON via Text |
| `safeFromJson` | `Vayu.Utils.Aeson` | `Data.Aeson.decode` + error return |
| `ist` (timezone constant) | `Vayu.Utils.DateTime` | Don't build your own IST `TimeZone` |
| Country / province / pincode lookups | `Vayu.Utils.Extra` | Table lookups already exist |

**Before writing any list/option helper**, check `plan/16-utils-reference.md` for the full 400+ function index. The duplicate-helper rule (`check-utils-before-writing`) exists because duplicates have happened often.
