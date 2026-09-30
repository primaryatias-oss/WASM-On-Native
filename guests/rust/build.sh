#!/usr/bin/env bash
# Build the Rust guest -> build/guests/rust.wasm
# Needs: rustup with the wasm32-unknown-unknown target (`rustup target add wasm32-unknown-unknown`).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
mkdir -p "$OUT"

cd "$ROOT/guests/rust"
cargo build --release --target wasm32-unknown-unknown --target-dir "$ROOT/build/cargo-guest"
cp "$ROOT/build/cargo-guest/wasm32-unknown-unknown/release/guest.wasm" "$OUT/rust.wasm"

echo "built $OUT/rust.wasm"
