# Template — Newtype with Smart Constructor

Use when a primitive (`Text`, `Int`, etc.) has invariants that must not be violated.

## Module layout

```haskell
-- Domain/Email.hs
module Domain.Email
  ( Email            -- export type, NOT constructor
  , mkEmail
  , unEmail
  , EmailError (..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T

newtype Email = Email Text
  deriving stock (Eq, Ord, Show)

data EmailError
  = EmailEmpty
  | EmailMissingAt
  | EmailTooLong
  deriving stock (Eq, Show)

mkEmail :: Text -> Either EmailError Email
mkEmail raw
  | T.null trimmed            = Left EmailEmpty
  | not ("@" `T.isInfixOf` t) = Left EmailMissingAt
  | T.length t > 254          = Left EmailTooLong
  | otherwise                 = Right (Email t)
  where
    trimmed = T.strip raw
    t       = T.toLower trimmed

unEmail :: Email -> Text
unEmail (Email t) = t
```

## Why this shape

- **Constructor unexported.** The only way to get an `Email` is `mkEmail`, so "this is an `Email`" means "it passed validation".
- **`EmailError` is a sum type, not a `String`.** Callers can pattern-match and respond differently per case.
- **`unEmail` projects out.** No pattern matching on the constructor outside this module.
- **Normalisation in `mkEmail`.** Trim + lowercase happen once; `Eq` on `Email` is case-insensitive by construction.

## JSON instances

```haskell
instance ToJSON Email where
  toJSON = toJSON . unEmail

instance FromJSON Email where
  parseJSON = withText "Email" $ \t ->
    case mkEmail t of
      Right e  -> pure e
      Left err -> fail (show err)
```

Deriving via `deriving newtype` works only if you want the raw `Text` behaviour on both sides — usually you want the validated version, so hand-write `FromJSON`.

## Testing

```haskell
prop_emailRoundTrip :: ValidEmailText -> Property
prop_emailRoundTrip (ValidEmailText t) =
  case mkEmail t of
    Right e  -> unEmail e === T.toLower (T.strip t)
    Left err -> counterexample (show err) False
```
