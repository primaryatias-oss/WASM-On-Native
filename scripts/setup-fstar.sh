#!/usr/bin/env bash
# Install F* (fstar.exe) and KaRaMeL (krml) for the F* guest.
#
# F* is installed from opam. KaRaMeL is built from source into vendor/karamel; the guest
# build only needs its `krml` binary and its C headers (include/, krmllib/dist/minimal).
#
# Needs: opam with an initialised switch, git, make, and a C toolchain.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if ! command -v fstar.exe >/dev/null 2>&1; then
    opam install -y fstar
fi

KRML_HOME="${KRML_HOME:-$ROOT/vendor/karamel}"
if [ ! -x "$KRML_HOME/krml" ]; then
    rm -rf "$KRML_HOME"
    mkdir -p "$ROOT/vendor"
    git clone --depth 1 https://github.com/FStarLang/karamel "$KRML_HOME"
    opam install -y --deps-only "$KRML_HOME"
    # `minimal` builds krml plus the small subset of krmllib that needs no F* library build.
    make -C "$KRML_HOME" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)" minimal
fi

echo "fstar.exe: $(command -v fstar.exe)"
echo "krml:      $KRML_HOME/krml"
