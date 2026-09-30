#!/usr/bin/env bash
# Download F* into vendor/fstar, for the F* guest.
#
# The F* release tarball is self-contained: fstar.exe, KaRaMeL (`krml`, the F* -> C compiler),
# KaRaMeL's C headers and three Z3 builds. No OCaml or opam is needed to use it.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [ -x "$FSTAR_HOME/bin/fstar.exe" ] && [ -x "$FSTAR_HOME/bin/krml" ]; then
    echo "F* already present in $FSTAR_HOME"
    exit 0
fi

case "$(host_os)-$(host_arch)" in
    linux-x86_64)  suffix=Linux-x86_64 ;;
    linux-aarch64) suffix=Linux-aarch64 ;;
    macos-x86_64)  suffix=Darwin-x86_64 ;;
    macos-aarch64) suffix=Darwin-arm64 ;;
esac

name="fstar-v${FSTAR_VERSION}-${suffix}"
url="https://github.com/FStarLang/FStar/releases/download/v${FSTAR_VERSION}/${name}.tar.gz"

mkdir -p "$ROOT/vendor" "$BUILD/download"
echo "downloading $url"
curl -fsSL "$url" -o "$BUILD/download/$name.tar.gz"

# The archive holds a single top-level directory, fstar/.
rm -rf "$FSTAR_HOME" "$BUILD/download/fstar-unpack"
mkdir -p "$BUILD/download/fstar-unpack"
tar -xzf "$BUILD/download/$name.tar.gz" -C "$BUILD/download/fstar-unpack"
mv "$BUILD/download/fstar-unpack/fstar" "$FSTAR_HOME"
rm -rf "$BUILD/download/fstar-unpack"

echo "F* ${FSTAR_VERSION} installed in $FSTAR_HOME"
"$FSTAR_HOME/bin/fstar.exe" --version | head -n 1
