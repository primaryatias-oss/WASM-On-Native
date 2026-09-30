#!/usr/bin/env bash
# Build guests. Usage: scripts/build-guests.sh [lang ...]   (default: all eight)
# Each guest's build.sh writes build/guests/<lang>.wasm. A failing guest does not stop the
# others; the exit status is non-zero if any of them failed.
set -uo pipefail
source "$(dirname "$0")/env.sh"

langs=("$@")
[ ${#langs[@]} -eq 0 ] && langs=("${WASM_LANGUAGES[@]}")
mkdir -p "$BUILD/logs"

failed=()
for lang in "${langs[@]}"; do
    printf 'guest %-8s ' "$lang"
    if bash "$ROOT/guests/$lang/build.sh" >"$BUILD/logs/guest-$lang.log" 2>&1; then
        echo ok
    else
        echo "FAILED (see build/logs/guest-$lang.log)"
        tail -n 8 "$BUILD/logs/guest-$lang.log" | sed 's/^/    /'
        failed+=("$lang")
    fi
done

[ ${#failed[@]} -eq 0 ] || { echo "guests failed: ${failed[*]}"; exit 1; }
