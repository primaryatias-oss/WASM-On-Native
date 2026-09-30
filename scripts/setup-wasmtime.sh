#!/usr/bin/env bash
# Download the Wasmtime C API (headers + libwasmtime) into vendor/wasmtime-c-api.
# This one package is what the C, Nim and Zig hosts link against. (The Rust host uses
# the `wasmtime` crate and the Go host uses `wasmtime-go`, which bundles the same C API.)
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [ -f "$WASMTIME_C_API/include/wasmtime.h" ]; then
    echo "Wasmtime C API already present in $WASMTIME_C_API"
    exit 0
fi

name="wasmtime-v${WASMTIME_VERSION}-$(host_arch)-$(host_os)-c-api"
url="https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/${name}.tar.xz"

mkdir -p "$ROOT/vendor" "$BUILD/download"
echo "downloading $url"
curl -fsSL "$url" -o "$BUILD/download/$name.tar.xz"

rm -rf "$WASMTIME_C_API" "$BUILD/download/$name"
tar -xf "$BUILD/download/$name.tar.xz" -C "$BUILD/download"
mv "$BUILD/download/$name" "$WASMTIME_C_API"

echo "Wasmtime C API ${WASMTIME_VERSION} installed in $WASMTIME_C_API"
