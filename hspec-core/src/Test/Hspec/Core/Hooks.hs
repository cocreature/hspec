-- | Stability: provisional
module Test.Hspec.Core.Hooks (
  before
, before_
, beforeWith
, beforeAll
, beforeAll_
, after
, after_
, afterAll
, afterAll_
, around
, around_
, aroundWith
) where

import           Control.Exception (finally)
import           Control.Concurrent.MVar

import           Test.Hspec.Core.Spec

-- | Run a custom action before every spec item.
before :: IO a -> SpecWith a -> Spec
before action = around (action >>=)

-- | Run a custom action before every spec item.
before_ :: IO () -> SpecWith a -> SpecWith a
before_ action = around_ (action >>)

-- | Run a custom action before every spec item.
beforeWith :: (b -> IO a) -> SpecWith a -> SpecWith b
beforeWith action = aroundWith $ \e x -> action x >>= e

-- | Run a custom action before the first spec item.
beforeAll :: IO a -> SpecWith a -> Spec
beforeAll action spec = do
  mvar <- runIO (newMVar Nothing)
  before (memoize mvar action) spec

-- | Run a custom action before the first spec item.
beforeAll_ :: IO () -> SpecWith a -> SpecWith a
beforeAll_ action spec = do
  mvar <- runIO (newMVar Nothing)
  before_ (memoize mvar action) spec

memoize :: MVar (Maybe a) -> IO a -> IO a
memoize mvar action = modifyMVar mvar $ \ma -> case ma of
  Just a -> return (ma, a)
  Nothing -> do
    a <- action
    return (Just a, a)

-- | Run a custom action after every spec item.
after :: ActionWith a -> SpecWith a -> SpecWith a
after action = aroundWith $ \e x -> e x `finally` action x

-- | Run a custom action after every spec item.
after_ :: IO () -> SpecWith a -> SpecWith a
after_ action = after $ \_ -> action

-- | Run a custom action before and/or after every spec item.
around :: (ActionWith a -> IO ()) -> SpecWith a -> Spec
around action = aroundWith $ \e () -> action e

-- | Run a custom action after the last spec item.
afterAll :: ActionWith a -> SpecWith a -> SpecWith a
afterAll action spec = runIO (runSpecM spec) >>= fromSpecList . return . NodeWithCleanup action

-- | Run a custom action after the last spec item.
afterAll_ :: IO () -> SpecWith a -> SpecWith a
afterAll_ action = afterAll (\_ -> action)

-- | Run a custom action before and/or after every spec item.
around_ :: (IO () -> IO ()) -> SpecWith a -> SpecWith a
around_ action = aroundWith $ \e a -> action (e a)

-- | Run a custom action before and/or after every spec item.
aroundWith :: (ActionWith a -> ActionWith b) -> SpecWith a -> SpecWith b
aroundWith action = mapAround (. action)

mapAround :: ((ActionWith b -> IO ()) -> ActionWith a -> IO ()) -> SpecWith a -> SpecWith b
mapAround f = mapSpecItem (untangle f) $ \i@Item{itemExample = e} -> i{itemExample = (. f) . e}

untangle  :: ((ActionWith b -> IO ()) -> ActionWith a -> IO ()) -> ActionWith a -> ActionWith b
untangle f g = \b -> f ($ b) g
