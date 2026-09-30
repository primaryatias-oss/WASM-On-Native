#!/usr/bin/env bash
# Build the F* guest -> build/guests/fstar.wasm
#
# Pipeline: F* --(verify)--> Guest.fst.checked --(extract)--> Guest.krml
#           --(KaRaMeL)--> C --(wasi-sdk clang)--> wasm
#
# Needs: F* with KaRaMeL and wasi-sdk (scripts/setup-fstar.sh, scripts/setup-wasi-sdk.sh).
#   FSTAR_HOME     unpacked F* release   (default: vendor/fstar)
#   FSTAR_EXE      fstar.exe             (default: $FSTAR_HOME/bin/fstar.exe, else PATH)
#   KRML           KaRaMeL's krml        (default: $FSTAR_HOME/bin/krml, else PATH)
#   KRML_INCLUDE   dir with krmllib.h    (default: $FSTAR_HOME/include/krml)
#   KRMLLIB_MINIMAL dir with the FStar_UInt_8_16_32_64.h family
#                                        (default: $FSTAR_HOME/lib/krml/dist/minimal)
#   WASI_SDK_PATH                        (default: vendor/wasi-sdk)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/guests"
WORK="$ROOT/build/fstar-guest"
FSTAR_HOME="${FSTAR_HOME:-$ROOT/vendor/fstar}"
FSTAR_EXE="${FSTAR_EXE:-$FSTAR_HOME/bin/fstar.exe}"
[ -x "$FSTAR_EXE" ] || FSTAR_EXE="$(command -v fstar.exe)"
KRML="${KRML:-$FSTAR_HOME/bin/krml}"
[ -x "$KRML" ] || KRML="$(command -v krml)"
KRML_INCLUDE="${KRML_INCLUDE:-$FSTAR_HOME/include/krml}"
KRMLLIB_MINIMAL="${KRMLLIB_MINIMAL:-$FSTAR_HOME/lib/krml/dist/minimal}"
WASI_SDK="${WASI_SDK_PATH:-$ROOT/vendor/wasi-sdk}"

rm -rf "$WORK"
mkdir -p "$OUT" "$WORK"
cd "$ROOT/guests/fstar"

# 1. Verify Guest.fst (an F* error here stops the build) and cache the checked module.
"$FSTAR_EXE" --cache_checked_modules --cache_dir "$WORK/cache" Guest.fst

# 2. Extract the verified module to KaRaMeL's intermediate language. Extraction needs the
#    checked module from step 1, which is why the two steps are separate.
"$FSTAR_EXE" --cache_dir "$WORK/cache" --codegen krml --odir "$WORK" --extract Guest Guest.fst

# 3. Generate C. -no-prefix keeps the exported names as plain `add` and `fib`.
"$KRML" -skip-compilation -no-prefix Guest -tmpdir "$WORK/c" "$WORK/Guest.krml"

# 4. Compile the C to a WASI reactor.
"$WASI_SDK/bin/clang" \
    --target=wasm32-wasip1 --sysroot="$WASI_SDK/share/wasi-sysroot" \
    -O2 -mexec-model=reactor \
    -I "$KRML_INCLUDE" -I "$KRMLLIB_MINIMAL" -I "$WORK/c" \
    -Wl,--export=add -Wl,--export=fib \
    -o "$OUT/fstar.wasm" \
    "$WORK/c/Guest.c"

echo "built $OUT/fstar.wasm"
