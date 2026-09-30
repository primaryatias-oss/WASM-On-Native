#!/usr/bin/env bash
# Build the Rust host -> build/hosts/rust-host
# Needs: Rust >= 1.96 (the wasmtime 49 crate requires it) and network access to crates.io.
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
mkdir -p "$HOST_DIR"

cd "$ROOT/hosts/rust"
cargo build --release --target-dir "$BUILD/cargo-host"
cp "$BUILD/cargo-host/release/rust-host" "$HOST_DIR/rust-host"

echo "built $HOST_DIR/rust-host"
