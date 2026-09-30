#!/usr/bin/env bash
# Build the F* guest -> build/guests/fstar.wasm
#
# Pipeline: F* --(extract)--> Guest.krml --(KaRaMeL)--> C --(wasi-sdk clang)--> wasm
#
# Needs: fstar.exe, KaRaMeL (`krml`) and wasi-sdk.
#   FSTAR_EXE   path to fstar.exe          (default: fstar.exe from PATH)
#   KRML_HOME   KaRaMeL checkout           (default: vendor/karamel; see scripts/setup-fstar.sh)
#   WASI_SDK_PATH                          (default: vendor/wasi-sdk)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
WORK="$ROOT/build/fstar-guest"
FSTAR_EXE="${FSTAR_EXE:-fstar.exe}"
KRML_HOME="${KRML_HOME:-$ROOT/vendor/karamel}"
KRML="${KRML:-$KRML_HOME/krml}"
WASI_SDK="${WASI_SDK_PATH:-$ROOT/vendor/wasi-sdk}"
mkdir -p "$OUT" "$WORK"

cd "$ROOT/guests/fstar"

# 1. Verify and extract to KaRaMeL's intermediate language.
"$FSTAR_EXE" --codegen krml --odir "$WORK" --extract Guest Guest.fst

# 2. Generate C. -no-prefix keeps the exported names as plain `add` and `fib`.
"$KRML" -skip-compilation -no-prefix Guest -tmpdir "$WORK/c" "$WORK/Guest.krml"

# 3. Compile the C to a WASI reactor.
"$WASI_SDK/bin/clang" \
    --target=wasm32-wasip1 --sysroot="$WASI_SDK/share/wasi-sysroot" \
    -O2 -mexec-model=reactor \
    -I "$KRML_HOME/include" -I "$KRML_HOME/krmllib/dist/minimal" -I "$WORK/c" \
    -Wl,--export=add -Wl,--export=fib \
    -o "$OUT/fstar.wasm" \
    "$WORK/c/Guest.c"

echo "built $OUT/fstar.wasm"
