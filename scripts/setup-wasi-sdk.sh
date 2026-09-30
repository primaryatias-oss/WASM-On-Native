#!/usr/bin/env bash
# Download wasi-sdk (clang + wasi-libc sysroot for wasm32-wasi) into vendor/wasi-sdk.
# Needed by the Nim and F* guests, which go through C.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [ -x "$WASI_SDK_PATH/bin/clang" ]; then
    echo "wasi-sdk already present in $WASI_SDK_PATH"
    exit 0
fi

case "$(host_os)-$(host_arch)" in
    linux-x86_64)  suffix=x86_64-linux ;;
    linux-aarch64) suffix=arm64-linux ;;
    macos-x86_64)  suffix=x86_64-macos ;;
    macos-aarch64) suffix=arm64-macos ;;
esac

name="wasi-sdk-${WASI_SDK_VERSION}.0-${suffix}"
url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/${name}.tar.gz"

mkdir -p "$ROOT/vendor" "$BUILD/download"
echo "downloading $url"
curl -fsSL "$url" -o "$BUILD/download/$name.tar.gz"

rm -rf "$WASI_SDK_PATH" "$BUILD/download/$name"
tar -xf "$BUILD/download/$name.tar.gz" -C "$BUILD/download"
mv "$BUILD/download/$name" "$WASI_SDK_PATH"

echo "wasi-sdk ${WASI_SDK_VERSION} installed in $WASI_SDK_PATH"
