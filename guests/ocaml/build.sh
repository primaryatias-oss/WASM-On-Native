#!/usr/bin/env bash
# Build the OCaml guest -> build/guests/ocaml.wasm
#
# Needs a wasm_of_ocaml that has the WASI target. As of this writing that target is
# an open pull request (ocsigen/js_of_ocaml#1831), not a release, so
# scripts/setup-wasm-of-ocaml-wasi.sh builds it from source and pins it in opam.
# Set WASM_OF_OCAML to use a different binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
WORK="$ROOT/build/ocaml-guest"
WOO="${WASM_OF_OCAML:-wasm_of_ocaml}"
# binaryen (wasm-opt) may have been unpacked by the setup script
export PATH="$ROOT/vendor/binaryen/bin:$PATH"
mkdir -p "$OUT" "$WORK"

# 1. OCaml source -> OCaml bytecode
ocamlfind ocamlc -g -o "$WORK/guest.byte" "$ROOT/guests/ocaml/guest.ml"

# 2. bytecode -> wasm (WasmGC + exnref exceptions + tail calls) with WASI imports.
#    Produces guest.js (Node wrapper) and guest.assets/code.wasm (the module we want).
"$WOO" --enable wasi "$WORK/guest.byte" -o "$WORK/guest.js"

cp "$WORK/guest.assets/code.wasm" "$OUT/ocaml.wasm"
echo "built $OUT/ocaml.wasm"
