# Guest written in Nim, compiled to WebAssembly through C + wasi-sdk's clang.
#
# Contract shared by every guest in this repo (see README, "The guest contract"):
#   add(a, b: int32): int32   a + b (wrapping)
#   fib(n: int32): int32      n-th Fibonacci number (wrapping)
#
# Arithmetic is done on uint32 because unsigned Nim arithmetic wraps, whereas
# int32 arithmetic would raise OverflowDefect when overflow checks are on.

proc add*(a, b: int32): int32 {.exportc: "add", cdecl.} =
  cast[int32](cast[uint32](a) + cast[uint32](b))

proc fib*(n: int32): int32 {.exportc: "fib", cdecl.} =
  var a: uint32 = 0
  var b: uint32 = 1
  var i: int32 = 0
  while i < n:
    let t = a + b
    a = b
    b = t
    inc i
  result = cast[int32](a)
