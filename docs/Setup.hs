module Main (main) where

import Distribution.Extra.Doctest (defaultMainWithDoctests)

main :: IO ()
main = defaultMainWithDoctests "streamly-docs-doctests"
