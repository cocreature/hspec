-- |
-- Stability: experimental
--
-- This module contains formatters that can be used with
-- `Test.Hspec.Runner.hspecWith`.
module Test.Hspec.Core.Formatters (

-- * Formatters
  silent
, specdoc
, progress
, failed_examples

-- * Implementing a custom Formatter
-- |
-- A formatter is a set of actions.  Each action is evaluated when a certain
-- situation is encountered during a test run.
--
-- Actions live in the `FormatM` monad.  It provides access to the runner state
-- and primitives for appending to the generated report.
, Formatter (..)
, FailureReason (..)
, FormatM

-- ** Accessing the runner state
, getSuccessCount
, getPendingCount
, getFailCount
, getTotalCount

, FailureRecord (..)
, getFailMessages
, usedSeed

, getCPUTime
, getRealTime

-- ** Appending to the gerenated report
, write
, writeLine
, newParagraph

-- ** Dealing with colors
, withInfoColor
, withSuccessColor
, withPendingColor
, withFailColor

-- ** Helpers
, formatException
) where

import           Prelude ()
import           Test.Hspec.Compat hiding (First)

import           Data.Maybe
import           Data.List
import           Test.Hspec.Core.Util
import           Test.Hspec.Core.Spec (Location(..), LocationAccuracy(..))
import           Text.Printf
import           Control.Monad (when, unless)
import           System.IO (hPutStr, hFlush)
import           Data.Algorithm.Diff

-- We use an explicit import list for "Test.Hspec.Formatters.Internal", to make
-- sure, that we only use the public API to implement formatters.
--
-- Everything imported here has to be re-exported, so that users can implement
-- their own formatters.
import Test.Hspec.Core.Formatters.Internal (
    Formatter (..)
  , FailureReason (..)
  , FormatM

  , getSuccessCount
  , getPendingCount
  , getFailCount
  , getTotalCount

  , FailureRecord (..)
  , getFailMessages
  , usedSeed

  , getCPUTime
  , getRealTime

  , write
  , writeLine
  , newParagraph

  , withInfoColor
  , withSuccessColor
  , withPendingColor
  , withFailColor
  )

import           Test.Hspec.Core.Example (FailureReason(..))

silent :: Formatter
silent = Formatter {
  headerFormatter     = return ()
, exampleGroupStarted = \_ _ -> return ()
, exampleGroupDone    = return ()
, exampleProgress     = \_ _ _ -> return ()
, exampleSucceeded    = \_ -> return ()
, exampleFailed       = \_ _ -> return ()
, examplePending      = \_ _  -> return ()
, failedFormatter     = return ()
, footerFormatter     = return ()
}


specdoc :: Formatter
specdoc = silent {

  headerFormatter = do
    writeLine ""

, exampleGroupStarted = \nesting name -> do
    writeLine (indentationFor nesting ++ name)

, exampleProgress = \h _ p -> do
    hPutStr h (formatProgress p)
    hFlush h

, exampleSucceeded = \(nesting, requirement) -> withSuccessColor $ do
    writeLine $ indentationFor nesting ++ requirement

, exampleFailed = \(nesting, requirement) _ -> withFailColor $ do
    n <- getFailCount
    writeLine $ indentationFor nesting ++ requirement ++ " FAILED [" ++ show n ++ "]"

, examplePending = \(nesting, requirement) reason -> withPendingColor $ do
    writeLine $ indentationFor nesting ++ requirement ++ "\n     # PENDING: " ++ fromMaybe "No reason given" reason

, failedFormatter = defaultFailedFormatter

, footerFormatter = defaultFooter
} where
    indentationFor nesting = replicate (length nesting * 2) ' '
    formatProgress (current, total)
      | total == 0 = show current ++ "\r"
      | otherwise  = show current ++ "/" ++ show total ++ "\r"


progress :: Formatter
progress = silent {
  exampleSucceeded = \_   -> withSuccessColor $ write "."
, exampleFailed    = \_ _ -> withFailColor    $ write "F"
, examplePending   = \_ _ -> withPendingColor $ write "."
, failedFormatter  = defaultFailedFormatter
, footerFormatter  = defaultFooter
}


failed_examples :: Formatter
failed_examples   = silent {
  failedFormatter = defaultFailedFormatter
, footerFormatter = defaultFooter
}

defaultFailedFormatter :: FormatM ()
defaultFailedFormatter = do
  writeLine ""

  failures <- getFailMessages

  unless (null failures) $ do
    writeLine "Failures:"
    writeLine ""

    forM_ (zip [1..] failures) $ \x -> do
      formatFailure x
      writeLine ""

    when (hasBestEffortLocations failures) $ do
      withInfoColor $ writeLine "Source locations marked with \"best-effort\" are calculated heuristically and may be incorrect."
      writeLine ""

    write "Randomized with seed " >> usedSeed >>= writeLine . show
    writeLine ""
  where
    hasBestEffortLocations :: [FailureRecord] -> Bool
    hasBestEffortLocations = any p
      where
        p :: FailureRecord -> Bool
        p failure = (locationAccuracy <$> failureRecordLocation failure) == Just BestEffort

    formatFailure :: (Int, FailureRecord) -> FormatM ()
    formatFailure (n, FailureRecord mLoc path reason) = do
      forM_ mLoc $ \loc -> do
        withInfoColor $ writeLine (formatLoc loc)
      write ("  " ++ show n ++ ") ")
      writeLine (formatRequirement path)
      case reason of
        Left e -> let err = (("uncaught exception: " ++) . formatException) e in do
          forM_ (lines err) $ \x -> do
            writeLine ("       " ++ x)
        Right NoReason -> return ()
        Right (Reason err) -> do
          forM_ (lines err) $ \x -> do
            writeLine ("       " ++ x)
        Right (ExpectedButGot preface expected actual) -> do
          let foo = getGroupedDiff expected actual
          mapM_ writeLine preface

          write ("       " ++ "expected: ")
          forM_ foo $ \chunk -> case chunk of
            Both a _ -> write a
            First a -> withFailColor $ write a
            Second _ -> return ()
          writeLine ""

          write ("       " ++ "but got:  ")
          forM_ foo $ \chunk -> case chunk of
            Both a _ -> write a
            First _ -> return ()
            Second a -> withSuccessColor $ write a
          writeLine ""
      where
        err = either (("uncaught exception: " ++) . formatException) formatFailureReason reason

        formatLoc (Location file line _column accuracy) = "  " ++ file ++ ":" ++ show line ++ ":" ++ message
          where
            message = case accuracy of
              ExactLocation -> " " -- NOTE: Vim's default 'errorformat'
                                   -- requires a non-empty message.  This is
                                   -- why we use a single space as message
                                   -- here.
              BestEffort -> " (best-effort)"

formatFailureReason :: FailureReason -> String
formatFailureReason NoReason = ""
formatFailureReason (Reason reason) = reason
formatFailureReason (ExpectedButGot preface expected actual) = intercalate "\n" . maybe id (:) preface $ ["expected: " ++ expected, " but got: " ++ actual]

defaultFooter :: FormatM ()
defaultFooter = do

  writeLine =<< (++)
    <$> (printf "Finished in %1.4f seconds"
    <$> getRealTime) <*> (maybe "" (printf ", used %1.4f seconds of CPU time") <$> getCPUTime)

  fails   <- getFailCount
  pending <- getPendingCount
  total   <- getTotalCount

  let c | fails /= 0   = withFailColor
        | pending /= 0 = withPendingColor
        | otherwise    = withSuccessColor
  c $ do
    write $ pluralize total   "example"
    write (", " ++ pluralize fails "failure")
    unless (pending == 0) $
      write (", " ++ show pending ++ " pending")
  writeLine ""
