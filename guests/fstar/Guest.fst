(* Guest written in F*, extracted to C with KaRaMeL and compiled to WebAssembly.

   Contract shared by every guest in this repo (see README, "The guest contract"):
     add a b  -> a + b (wrapping)
     fib n    -> n-th Fibonacci number (wrapping)

   The code is ordinary F*: F* checks that the subtraction in `fib_go` cannot
   underflow (the `else` branch knows n <> 0) and that the recursion terminates
   (`decreases`). KaRaMeL then turns it into C with uint32_t arithmetic. *)
module Guest

module U32 = FStar.UInt32

val add: U32.t -> U32.t -> Tot U32.t
let add a b = U32.add_mod a b

val fib_go: n:U32.t -> a:U32.t -> b:U32.t -> Tot U32.t (decreases (U32.v n))
let rec fib_go n a b =
  if U32.eq n 0ul
  then a
  else fib_go (U32.sub n 1ul) b (U32.add_mod a b)

val fib: U32.t -> Tot U32.t
let fib n = fib_go n 0ul 1ul
