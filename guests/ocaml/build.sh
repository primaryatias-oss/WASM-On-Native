#!/usr/bin/env bash
# Build the OCaml guest -> build/guests/ocaml.wasm
#
# Needs wasm_of_ocaml >= 6.4.0 (the first release with the WASI target; run
# scripts/setup-wasm-of-ocaml.sh, which also provides Binaryen).
# Set WASM_OF_OCAML to use a different binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# The opam switch is often not on PATH (a CI step after setup-ocaml, or a shell where
# `eval $(opam env)` was never run): run this same script inside `opam exec` then.
if ! command -v ocamlc >/dev/null 2>&1 && command -v opam >/dev/null 2>&1 && [ -z "${IN_OPAM_EXEC:-}" ]; then
    IN_OPAM_EXEC=1 exec opam exec -- bash "$0" "$@"
fi

OUT="$ROOT/build/guests"
WORK="$ROOT/build/ocaml-guest"
WOO="${WASM_OF_OCAML:-wasm_of_ocaml}"
# binaryen (wasm-opt) may have been unpacked by the setup script
export PATH="$ROOT/vendor/binaryen/bin:$PATH"
mkdir -p "$OUT" "$WORK"

# 1. OCaml source -> OCaml bytecode. ocamlc writes guest.cmi/guest.cmo next to its input, so
#    compile a copy that lives in the build directory and keep guests/ocaml/ clean.
cp "$ROOT/guests/ocaml/guest.ml" "$WORK/guest.ml"
(cd "$WORK" && ocamlc -g -o guest.byte guest.ml)

# 2. bytecode -> wasm (WasmGC + exnref exceptions + tail calls) with WASI imports.
#    Produces guest.js (Node wrapper) and guest.assets/code.wasm (the module we want).
"$WOO" --enable wasi "$WORK/guest.byte" -o "$WORK/guest.js"

cp "$WORK/guest.assets/code.wasm" "$OUT/ocaml.wasm"
echo "built $OUT/ocaml.wasm"
