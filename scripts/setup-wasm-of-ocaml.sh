#!/usr/bin/env bash
# Install wasm_of_ocaml with the WASI target into the current opam switch, for the OCaml guest.
#
# The WASI target (`wasm_of_ocaml --enable wasi`) shipped in wasm_of_ocaml 6.4.0. It needs
# Binaryen >= 119 (wasm-opt, wasm-merge); distro packages are usually older, so this script
# unpacks an official Binaryen release into vendor/binaryen when the one on PATH is too old.
#
# Needs: opam with an initialised switch (OCaml 4.14 to 5.5), curl, tar.
set -euo pipefail
source "$(dirname "$0")/env.sh"

MIN_BINARYEN=119
BINARYEN_VERSION="${BINARYEN_VERSION:-123}"

binaryen_version() {
    "$1" --version 2>/dev/null | sed -n 's/^wasm-opt version \([0-9][0-9]*\).*/\1/p'
}

have=""
if command -v wasm-opt >/dev/null 2>&1; then have="$(binaryen_version wasm-opt)"; fi
if [ -z "$have" ] || [ "$have" -lt "$MIN_BINARYEN" ]; then
    case "$(host_os)-$(host_arch)" in
        linux-x86_64)  bsuffix=x86_64-linux ;;
        linux-aarch64) bsuffix=aarch64-linux ;;
        macos-x86_64)  bsuffix=x86_64-macos ;;
        macos-aarch64) bsuffix=arm64-macos ;;
    esac
    mkdir -p "$ROOT/vendor/binaryen" "$BUILD/download"
    echo "Binaryen on PATH: ${have:-none}; installing version_${BINARYEN_VERSION} into vendor/binaryen"
    curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-${bsuffix}.tar.gz" \
        -o "$BUILD/download/binaryen.tar.gz"
    rm -rf "$ROOT/vendor/binaryen"
    mkdir -p "$ROOT/vendor/binaryen"
    tar -xf "$BUILD/download/binaryen.tar.gz" -C "$ROOT/vendor/binaryen" --strip-components=1
    export PATH="$ROOT/vendor/binaryen/bin:$PATH"
    # In GitHub Actions, keep it on PATH for the following steps too.
    [ -n "${GITHUB_PATH:-}" ] && echo "$ROOT/vendor/binaryen/bin" >> "$GITHUB_PATH"
fi
echo "Binaryen: $(wasm-opt --version)"

command -v opam >/dev/null 2>&1 || { echo "opam is required (https://opam.ocaml.org/doc/Install.html)" >&2; exit 1; }

# --assume-depexts: the `conf-binaryen` package would otherwise ask the system package manager
# for an (older) binaryen; the one checked or installed above is on PATH.
opam install -y --assume-depexts "wasm_of_ocaml-compiler>=6.4.0"

echo "wasm_of_ocaml installed: $(opam exec -- which wasm_of_ocaml)"
opam exec -- wasm_of_ocaml --version
