#!/usr/bin/env bash
# Build the Haskell guest -> build/guests/haskell.wasm
# Needs: GHC's wasm backend. Install it with ghc-wasm-meta, then `source ~/.ghc-wasm/env`
# (CI does this; see .github/workflows/matrix.yml).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
mkdir -p "$OUT"

if ! command -v wasm32-wasi-ghc >/dev/null 2>&1 && [ -f "$HOME/.ghc-wasm/env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.ghc-wasm/env"
fi

WORK="$ROOT/build/ghc-guest"
mkdir -p "$WORK"

# -no-hs-main                 : no Haskell `main` entry point, we only want the exports
# -optl-mexec-model=reactor   : WASI reactor (exports _initialize, no _start)
# -optl-Wl,--export=NAME      : keep NAME alive through the linker's dead-code elimination
wasm32-wasi-ghc -O2 \
    -no-hs-main \
    -optl-mexec-model=reactor \
    -optl-Wl,--export=add \
    -optl-Wl,--export=fib \
    -outputdir "$WORK" \
    -o "$OUT/haskell.wasm" \
    "$ROOT/guests/haskell/Guest.hs"

echo "built $OUT/haskell.wasm"
