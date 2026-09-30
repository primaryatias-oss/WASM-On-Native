#!/usr/bin/env bash
# Build the C guest -> build/guests/c.wasm
# Needs: clang with the wasm32 target and wasm-ld (Ubuntu: `apt install clang lld`).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
mkdir -p "$OUT"

"${CLANG:-clang}" --target=wasm32 -O2 -nostdlib \
    -Wl,--no-entry \
    -o "$OUT/c.wasm" \
    "$ROOT/guests/c/guest.c"

echo "built $OUT/c.wasm"
