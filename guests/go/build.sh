#!/usr/bin/env bash
# Build the Go guest -> build/guests/go.wasm
# Needs: Go >= 1.24 (for //go:wasmexport). No third-party modules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
mkdir -p "$OUT"

cd "$ROOT/guests/go"
GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o "$OUT/go.wasm" .

echo "built $OUT/go.wasm"
