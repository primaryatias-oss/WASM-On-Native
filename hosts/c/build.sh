#!/usr/bin/env bash
# Build the C host -> build/hosts/c-host
# Needs: a C compiler and the Wasmtime C API (run scripts/setup-wasmtime.sh).
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
mkdir -p "$HOST_DIR"

"${CC:-cc}" -std=c11 -O2 -Wall \
    -I "$WASMTIME_C_API/include" \
    -o "$HOST_DIR/c-host" \
    "$ROOT/hosts/c/host.c" \
    -L "$WASMTIME_C_API/lib" -lwasmtime -Wl,-rpath,"$WASMTIME_C_API/lib" \
    -lpthread -ldl -lm

echo "built $HOST_DIR/c-host"
