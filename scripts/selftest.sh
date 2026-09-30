#!/usr/bin/env bash
# Check that every built host reports success AND failure correctly.
#
# The matrix only shows that hosts accept good guests. This script runs each host against small
# hand-made modules (tools/make-test-guests.mjs) that must PASS or must FAIL, for example a guest
# that returns the wrong sum, traps, exits with status 3, or is not WebAssembly at all. A host
# that is wrong in either direction is reported.
#
#   scripts/selftest.sh                 all built hosts
#   HOSTS="rust go" scripts/selftest.sh
#
# Needs: Node.js (only to generate the modules).
set -uo pipefail
source "$(dirname "$0")/env.sh"

# shellcheck disable=SC2206
hosts=(${HOSTS:-${NATIVE_LANGUAGES[*]}})
dir="$BUILD/test-guests"
node --no-warnings "$ROOT/tools/make-test-guests.mjs" "$dir" >/dev/null || { echo "cannot generate test guests" >&2; exit 2; }

checked=0; wrong=0; ran_hosts=0
for h in "${hosts[@]}"; do
    bin="$HOST_DIR/$h-host"
    if [ ! -x "$bin" ]; then echo "skip  $h host (not built)"; continue; fi
    ran_hosts=$((ran_hosts + 1))
    host_wrong=0

    check() { # check <expect: pass|fail> <label> <file>
        local expect="$1" label="$2" file="$3" out err rc
        timeout 60 "$bin" "$file" >"$dir/.stdout" 2>"$dir/.stderr"; rc=$?
        out="$(tr -d '\0' <"$dir/.stdout")"
        err="$(tr -d '\0' <"$dir/.stderr")"
        checked=$((checked + 1))
        if [ "$expect" = pass ]; then
            if [ $rc -eq 0 ] && [[ "$out" == PASS* ]]; then return; fi
        else
            if [ $rc -eq 1 ] && [[ "$err" == FAIL* ]] && [ -z "$out" ]; then return; fi
        fi
        wrong=$((wrong + 1)); host_wrong=$((host_wrong + 1))
        echo "WRONG $h host, $label: wanted $expect, got exit $rc"
        echo "        stdout: ${out//$'\n'/ | }"
        echo "        stderr: $(printf '%s' "$err" | head -n 3 | tr '\n' ' ')"
    }

    for f in "$dir"/pass-*.wasm; do check pass "$(basename "$f" .wasm)" "$f"; done
    for f in "$dir"/fail-*.wasm; do check fail "$(basename "$f" .wasm)" "$f"; done
    check fail "fail-missing-file" "$dir/does-not-exist.wasm"

    # usage errors: no argument must give exit status 2 and no PASS
    "$bin" >/dev/null 2>&1; rc=$?
    checked=$((checked + 1))
    if [ $rc -ne 2 ]; then
        wrong=$((wrong + 1)); host_wrong=$((host_wrong + 1))
        echo "WRONG $h host, no arguments: wanted exit 2, got $rc"
    fi

    [ $host_wrong -eq 0 ] && echo "ok    $h host"
done
rm -f "$dir/.stdout" "$dir/.stderr"

echo
echo "checked $checked behaviours on $ran_hosts host(s): $wrong wrong"
[ "$ran_hosts" -gt 0 ] || exit 2
[ "$wrong" -eq 0 ]
