#!/usr/bin/env bash
# Build the Nim guest -> build/guests/nim.wasm
# Needs: Nim >= 2.0 and wasi-sdk (run scripts/setup-wasi-sdk.sh, or set WASI_SDK_PATH).
#
# Nim generates C; we point Nim at wasi-sdk's clang so that C is compiled for
# wasm32-wasip1. `-mexec-model=reactor` makes a library-style module (exports
# _initialize instead of _start).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
WASI_SDK="${WASI_SDK_PATH:-$ROOT/vendor/wasi-sdk}"
mkdir -p "$OUT"

FLAGS="--target=wasm32-wasip1 --sysroot=$WASI_SDK/share/wasi-sysroot"

nim c \
    --cpu:wasm32 --os:linux --cc:clang \
    --mm:arc --threads:off -d:release -d:useMalloc -d:noSignalHandler --noMain:on \
    --clang.exe:"$WASI_SDK/bin/clang" \
    --clang.linkerexe:"$WASI_SDK/bin/clang" \
    --passC:"$FLAGS" \
    --passL:"$FLAGS -mexec-model=reactor -Wl,--export=add -Wl,--export=fib" \
    --nimcache:"$ROOT/build/nimcache-guest" \
    -o:"$OUT/nim.wasm" \
    "$ROOT/guests/nim/guest.nim"

echo "built $OUT/nim.wasm"
