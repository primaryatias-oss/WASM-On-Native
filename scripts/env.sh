#!/usr/bin/env bash
# Shared settings for all scripts. Source it: `source "$(dirname "$0")/../scripts/env.sh"`.
# Everything can be overridden from the environment.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The single WebAssembly runtime used by every native host.
WASMTIME_VERSION="${WASMTIME_VERSION:-49.0.1}"
WASMTIME_C_API="${WASMTIME_C_API:-$ROOT/vendor/wasmtime-c-api}"   # contains include/ and lib/

# C toolchain for wasm32-wasi used by the Nim and F* guests.
WASI_SDK_VERSION="${WASI_SDK_VERSION:-25}"
WASI_SDK_PATH="${WASI_SDK_PATH:-$ROOT/vendor/wasi-sdk}"

BUILD="$ROOT/build"
GUEST_DIR="$BUILD/guests"
HOST_DIR="$BUILD/hosts"

# The two sets from the task description.
NATIVE_LANGUAGES=(c nim go rust zig)
WASM_LANGUAGES=("${NATIVE_LANGUAGES[@]}" ocaml haskell fstar)

# Values every guest must produce (the guest contract, see README).
EXPECT_ADD=42   # add(20, 22)
EXPECT_FIB=55   # fib(10)

host_os() {
    case "$(uname -s)" in
        Linux)  echo linux ;;
        Darwin) echo macos ;;
        *) echo "unsupported OS: $(uname -s)" >&2; return 1 ;;
    esac
}

host_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo x86_64 ;;
        arm64|aarch64) echo aarch64 ;;
        *) echo "unsupported CPU: $(uname -m)" >&2; return 1 ;;
    esac
}
