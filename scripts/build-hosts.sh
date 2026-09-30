#!/usr/bin/env bash
# Build hosts. Usage: scripts/build-hosts.sh [lang ...]   (default: all five)
# Each host's build.sh writes build/hosts/<lang>-host. A failing host does not stop the
# others; the exit status is non-zero if any of them failed.
# The C, Nim and Zig hosts need the Wasmtime C API: run scripts/setup-wasmtime.sh first.
set -uo pipefail
source "$(dirname "$0")/env.sh"

langs=("$@")
[ ${#langs[@]} -eq 0 ] && langs=("${NATIVE_LANGUAGES[@]}")
mkdir -p "$BUILD/logs"

failed=()
for lang in "${langs[@]}"; do
    printf 'host  %-8s ' "$lang"
    if bash "$ROOT/hosts/$lang/build.sh" >"$BUILD/logs/host-$lang.log" 2>&1; then
        echo ok
    else
        echo "FAILED (see build/logs/host-$lang.log)"
        tail -n 8 "$BUILD/logs/host-$lang.log" | sed 's/^/    /'
        failed+=("$lang")
    fi
done

[ ${#failed[@]} -eq 0 ] || { echo "hosts failed: ${failed[*]}"; exit 1; }
