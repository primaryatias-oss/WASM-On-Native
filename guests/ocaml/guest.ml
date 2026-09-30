(* Guest written in OCaml, compiled to WebAssembly with wasm_of_ocaml's WASI target.

   Unlike the other guests this one is a WASI *command* (it has _start): the
   wasm_of_ocaml WASI backend produces whole programs, not libraries. The program
   evaluates the shared contract itself, prints the results and exits non-zero on
   a mismatch. Hosts run it and treat "exit status 0" as success.

   Contract (see README, "The guest contract"):
     add a b  -> a + b (wrapping)
     fib n    -> n-th Fibonacci number (wrapping)

   Int32 is used explicitly so the semantics are identical in every OCaml backend. *)

let add (a : int32) (b : int32) : int32 = Int32.add a b

let fib (n : int32) : int32 =
  let rec go k a b =
    if Int32.equal k 0l then a else go (Int32.pred k) b (Int32.add a b)
  in
  go n 0l 1l

let () =
  let s = add 20l 22l and f = fib 10l in
  Printf.printf "ocaml guest: add(20,22)=%ld fib(10)=%ld\n%!" s f;
  if not (Int32.equal s 42l && Int32.equal f 55l) then exit 1
