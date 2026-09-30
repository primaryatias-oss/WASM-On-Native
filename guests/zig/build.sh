#!/usr/bin/env bash
# Build the Zig guest -> build/guests/zig.wasm
# Needs: Zig 0.16 (tested with 0.16.0).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
mkdir -p "$OUT"

cd "$ROOT/guests/zig"
# -fno-entry : it is a library-style module, no _start
# -rdynamic  : keep/export every `export fn`
zig build-exe guest.zig \
    -target wasm32-freestanding \
    -O ReleaseSmall \
    -fno-entry -rdynamic \
    -femit-bin="$OUT/zig.wasm"

echo "built $OUT/zig.wasm"
