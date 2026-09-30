#!/usr/bin/env bash
# Build the Haskell guest -> build/guests/haskell.wasm
#
# Needs GHC's WebAssembly backend (`wasm32-wasi-ghc`). Install it with
# scripts/setup-ghc-wasm.sh, or put your own on PATH. If it is not on PATH this script
# sources vendor/ghc-wasm/env (from the setup script) or ~/.ghc-wasm/env (from ghc-wasm-meta's
# bootstrap.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
mkdir -p "$OUT"

if ! command -v wasm32-wasi-ghc >/dev/null 2>&1; then
    for env in "$ROOT/vendor/ghc-wasm/env" "$HOME/.ghc-wasm/env"; do
        # shellcheck disable=SC1090
        [ -f "$env" ] && { source "$env"; break; }
    done
fi

# GHC writes the object file of a C source next to that source whatever -outputdir says, so
# compile a copy that lives in the build directory and keep guests/haskell/ clean.
WORK="$ROOT/build/ghc-guest"
rm -rf "$WORK"
mkdir -p "$WORK"
cp "$ROOT/guests/haskell/Guest.hs" "$ROOT/guests/haskell/boot.c" "$WORK/"

# -no-hs-main                 : no Haskell `main` entry point, we only want the exports
# -optl-mexec-model=reactor   : WASI reactor (exports _initialize, no _start)
# -optl-Wl,--export=NAME      : keep NAME alive through the linker's dead-code elimination
# boot.c                      : starts the Haskell runtime (hs_init) from a constructor, so
#                               `_initialize` is the only setup call a host has to make
cd "$WORK"
wasm32-wasi-ghc -O2 \
    -no-hs-main \
    -optl-mexec-model=reactor \
    -optl-Wl,--export=add \
    -optl-Wl,--export=fib \
    -o "$OUT/haskell.wasm" \
    Guest.hs boot.c

echo "built $OUT/haskell.wasm"
