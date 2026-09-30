#!/usr/bin/env bash
# Install GHC's WebAssembly backend (`wasm32-wasi-ghc`) into vendor/ghc-wasm, for the Haskell guest.
#
# This runs the upstream installer from https://github.com/haskell-wasm/ghc-wasm-meta. It is
# cloned from GitHub instead of using the documented `curl .../bootstrap.sh | sh` one-liner (which
# fetches a tarball from gitlab.haskell.org), and the compiler bindists it downloads are GitHub
# release assets, so the whole install works wherever github.com does.
#
#   GHC_WASM_FLAVOUR  9.10 | 9.12 | 9.14 | gmp ...   (default: 9.12, see env.sh)
#   GHC_WASM_PREFIX   install directory              (default: vendor/ghc-wasm)
#
# Needs: git, curl, jq, unzip, zstd, xz. About 5 GB of disk.
set -euo pipefail
source "$(dirname "$0")/env.sh"

GHC="$GHC_WASM_PREFIX/wasm32-wasi-ghc/bin/wasm32-wasi-ghc"
if [ -x "$GHC" ]; then
    echo "wasm32-wasi-ghc already present in $GHC_WASM_PREFIX"
    exit 0
fi

for tool in git curl jq unzip zstd xz; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done

META="$BUILD/src/ghc-wasm-meta"
rm -rf "$META" "$GHC_WASM_PREFIX"
mkdir -p "$BUILD/src"
git clone --depth 1 https://github.com/haskell-wasm/ghc-wasm-meta "$META"

if ! (cd "$META" && PREFIX="$GHC_WASM_PREFIX" FLAVOUR="$GHC_WASM_FLAVOUR" ./setup.sh); then
    # The installer sets up GHC first and only then downloads `cabal` (from downloads.haskell.org),
    # which this repo does not use. A network that blocks that host must not fail the install.
    if [ ! -x "$GHC" ]; then
        echo "ghc-wasm-meta's setup.sh failed before GHC was installed" >&2
        exit 1
    fi
    echo "warning: setup.sh failed after installing GHC (probably the optional cabal download); continuing" >&2
fi

echo "wasm32-wasi-ghc installed: $GHC"
echo "guests/haskell/build.sh sources $GHC_WASM_PREFIX/env by itself; to use it in your shell:"
echo "    source $GHC_WASM_PREFIX/env"
