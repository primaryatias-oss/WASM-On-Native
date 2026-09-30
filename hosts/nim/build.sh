#!/usr/bin/env bash
# Build the Nim host -> build/hosts/nim-host
# Needs: Nim 2.2 (tested with 2.2.x), a C compiler and the Wasmtime C API (run scripts/setup-wasmtime.sh).
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
mkdir -p "$HOST_DIR"

nim c -d:release --mm:arc \
    --passC:"-I$WASMTIME_C_API/include" \
    --passL:"-L$WASMTIME_C_API/lib -lwasmtime -Wl,-rpath,$WASMTIME_C_API/lib -lpthread -ldl -lm" \
    --nimcache:"$BUILD/nimcache-host" \
    -o:"$HOST_DIR/nim-host" \
    "$ROOT/hosts/nim/host.nim"

echo "built $HOST_DIR/nim-host"
