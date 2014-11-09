-- |
-- Stability: experimental
--
-- This module provides access to Hspec's internals.  It is less stable than
-- other parts of the API.  For most users "Test.Hspec" is more suitable!
module Test.Hspec.Core (

-- * A type class for examples
  Example (..)
, Params (..)
, ActionWith
, Progress
, ProgressCallback
, Result (..)

-- * A writer monad for constructing specs
, SpecM
, runSpecM
, fromSpecList

-- * Internal representation of a spec tree
, SpecTree
, Tree (..)
, Item (..)
, Location (..)
, LocationAccuracy(..)
, mapSpecTree
, mapSpecItem
, mapSpecItem_
, modifyParams
, specGroup
, specItem

-- * Deprecated functions
, describe
, it
) where

import           Test.Hspec.Core.Spec hiding (describe, it)


{-# DEPRECATED describe "use `specGroup` instead" #-}
describe :: String -> [SpecTree a] -> SpecTree a
describe = specGroup

{-# DEPRECATED it "use `specItem` instead" #-}
it :: Example a => String -> a -> SpecTree (Arg a)
it = specItem