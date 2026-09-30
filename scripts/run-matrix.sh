#!/usr/bin/env bash
# Run every built host against every built guest and print the matrix.
#
#   scripts/run-matrix.sh                       all hosts x all guests
#   HOSTS="rust go" GUESTS="c zig" scripts/run-matrix.sh
#   STRICT=1 scripts/run-matrix.sh              treat a missing host/guest as a failure
#
# Exit status: 1 if any cell FAILED (or, with STRICT=1, was skipped); otherwise 0.
# The table is also written to build/matrix.md (and to $GITHUB_STEP_SUMMARY in CI).
set -uo pipefail
source "$(dirname "$0")/env.sh"

# shellcheck disable=SC2206
hosts=(${HOSTS:-${NATIVE_LANGUAGES[*]}})
# shellcheck disable=SC2206
guests=(${GUESTS:-${WASM_LANGUAGES[*]}})
timeout_s="${CELL_TIMEOUT:-120}"

run_cell() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_s" "$@"
    else
        "$@"
    fi
}

declare -A cell
details=""
n_pass=0; n_fail=0; n_skip=0

for h in "${hosts[@]}"; do
    for g in "${guests[@]}"; do
        bin="$HOST_DIR/$h-host"
        wasm="$GUEST_DIR/$g.wasm"
        if [ ! -x "$bin" ]; then
            cell[$h,$g]="skip"; n_skip=$((n_skip + 1))
            details+="skip  $h host x $g guest: host binary missing ($bin)"$'\n'
        elif [ ! -f "$wasm" ]; then
            cell[$h,$g]="skip"; n_skip=$((n_skip + 1))
            details+="skip  $h host x $g guest: guest missing ($wasm)"$'\n'
        elif out="$(run_cell "$bin" "$wasm" 2>&1)"; then
            cell[$h,$g]="PASS"; n_pass=$((n_pass + 1))
        else
            cell[$h,$g]="FAIL"; n_fail=$((n_fail + 1))
            details+="FAIL  $h host x $g guest: ${out//$'\n'/ | }"$'\n'
        fi
    done
done

table() {
    printf '| guest \\ host |'
    for h in "${hosts[@]}"; do printf ' %s |' "$h"; done
    printf '\n|---|'
    for _ in "${hosts[@]}"; do printf ':---:|'; done
    printf '\n'
    for g in "${guests[@]}"; do
        printf '| %s |' "$g"
        for h in "${hosts[@]}"; do printf ' %s |' "${cell[$h,$g]}"; done
        printf '\n'
    done
}

mkdir -p "$BUILD"
table | tee "$BUILD/matrix.md"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && table >> "$GITHUB_STEP_SUMMARY"

echo
echo "pass: $n_pass  fail: $n_fail  skip: $n_skip"
[ -n "$details" ] && { echo; printf '%s' "$details"; }

[ "$n_fail" -eq 0 ] || exit 1
if [ "${STRICT:-0}" = "1" ] && [ "$n_skip" -gt 0 ]; then exit 1; fi
exit 0
