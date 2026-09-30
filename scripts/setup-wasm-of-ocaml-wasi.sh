#!/usr/bin/env bash
# Install a wasm_of_ocaml that has the WASI target into the current opam switch.
#
# The WASI target is NOT in a wasm_of_ocaml release yet: it is the open pull request
# https://github.com/ocsigen/js_of_ocaml/pull/1831 . Until it is merged and released we
# build that pull request from source and pin it in opam. Once it ships, replace this
# script with `opam install wasm_of_ocaml-compiler`.
#
# Needs: opam with an initialised switch (OCaml 4.14 or 5.x), git, and a C toolchain.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if command -v wasm_of_ocaml >/dev/null 2>&1 && wasm_of_ocaml --help 2>&1 | grep -qi wasi; then
    echo "wasm_of_ocaml with WASI support already installed"
    exit 0
fi

# wasm_of_ocaml post-processes with binaryen (wasm-opt); distro packages are often too old.
BINARYEN_VERSION="${BINARYEN_VERSION:-123}"
if ! command -v wasm-opt >/dev/null 2>&1; then
    case "$(host_os)-$(host_arch)" in
        linux-x86_64)  bsuffix=x86_64-linux ;;
        linux-aarch64) bsuffix=aarch64-linux ;;
        macos-x86_64)  bsuffix=x86_64-macos ;;
        macos-aarch64) bsuffix=arm64-macos ;;
    esac
    mkdir -p "$ROOT/vendor" "$BUILD/download"
    curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-${bsuffix}.tar.gz" \
        -o "$BUILD/download/binaryen.tar.gz"
    rm -rf "$ROOT/vendor/binaryen"
    mkdir -p "$ROOT/vendor/binaryen"
    tar -xf "$BUILD/download/binaryen.tar.gz" -C "$ROOT/vendor/binaryen" --strip-components=1
    echo "binaryen installed in vendor/binaryen; add vendor/binaryen/bin to PATH"
    export PATH="$ROOT/vendor/binaryen/bin:$PATH"
fi

SRC="$BUILD/src/js_of_ocaml"
rm -rf "$SRC"
mkdir -p "$BUILD/src"
git clone https://github.com/ocsigen/js_of_ocaml "$SRC"
git -C "$SRC" fetch origin pull/1831/head:wasi-pr
git -C "$SRC" checkout wasi-pr

opam pin add -y "git+file://$SRC#wasi-pr"

echo "wasm_of_ocaml (WASI prototype) installed: $(command -v wasm_of_ocaml)"
