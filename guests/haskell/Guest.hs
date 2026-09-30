-- Guest written in Haskell, compiled with GHC's WebAssembly backend
-- (wasm32-wasi-ghc, from https://gitlab.haskell.org/ghc/ghc-wasm-meta).
--
-- Contract shared by every guest in this repo (see README, "The guest contract"):
--   add :: CInt -> CInt -> CInt   a + b (wrapping)
--   fib :: CInt -> CInt           n-th Fibonacci number (wrapping)
--
-- CInt is a 32-bit newtype, so (+) and (-) wrap on overflow.
{-# LANGUAGE ForeignFunctionInterface #-}
module Main where

import Foreign.C.Types (CInt (..))

foreign export ccall "add" add :: CInt -> CInt -> CInt
foreign export ccall "fib" fib :: CInt -> CInt

add :: CInt -> CInt -> CInt
add a b = a + b

fib :: CInt -> CInt
fib n0 = go n0 0 1
  where
    go :: CInt -> CInt -> CInt -> CInt
    go 0 a _ = a
    go n a b = go (n - 1) b (a + b)

-- Never runs: the module is linked as a reactor (-no-hs-main), so there is no _start.
main :: IO ()
main = pure ()
