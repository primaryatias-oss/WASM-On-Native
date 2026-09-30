#!/usr/bin/env bash
# Build the Zig host -> build/hosts/zig-host
# Needs: Zig (0.15+ / 0.16) and the Wasmtime C API (run scripts/setup-wasmtime.sh).
#
# The Wasmtime C headers are turned into a Zig module with `zig translate-c`, which works the
# same way across Zig versions (unlike @cImport, whose build integration has been changing).
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
WORK="$BUILD/zig-host"
mkdir -p "$HOST_DIR" "$WORK"

cp "$ROOT/hosts/zig/host.zig" "$WORK/host.zig"
zig translate-c -lc -I "$WASMTIME_C_API/include" "$ROOT/hosts/zig/c.h" > "$WORK/c.zig"

cd "$WORK"
zig build-exe host.zig \
    -O ReleaseSafe -lc \
    -L "$WASMTIME_C_API/lib" -lwasmtime -rpath "$WASMTIME_C_API/lib" \
    -femit-bin="$HOST_DIR/zig-host"

echo "built $HOST_DIR/zig-host"
