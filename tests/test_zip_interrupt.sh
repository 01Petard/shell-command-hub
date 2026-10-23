#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/hub-zip-interrupt.XXXXXX")
runner=''
child=''
cleanup() {
    if [ -n "$child" ]; then kill -TERM "$child" 2>/dev/null || :; kill -CONT "$child" 2>/dev/null || :; fi
    if [ -n "$runner" ]; then kill -TERM "$runner" 2>/dev/null || :; wait "$runner" 2>/dev/null || :; fi
    rm -rf "$work"
}
trap cleanup EXIT
mkdir "$work/source" "$work/archive"
/usr/sbin/mkfile -n 256m "$work/source/payload"
(cd "$work/source" && /usr/bin/zip -q "$work/archive/batch.zip" payload)
for interrupt_signal in TERM HUP; do
    /bin/bash "$ROOT/tools/archive/zip-tidy.sh" "$work/archive" > "$work/output" 2>&1 &
    runner=$!
    child=''
    for ((i=0; i<200; i++)); do
        child=$(/usr/bin/pgrep -P "$runner" -x ditto || :)
        [ -z "$child" ] || break
        kill -0 "$runner" 2>/dev/null || break
        sleep 0.01
    done
    [ -n "$child" ] || { cat "$work/output"; echo 'FAIL: did not observe test extraction child'; exit 1; }
    # A paused extraction must also be reaped before its staging directory is removed.
    if [ "$interrupt_signal" = HUP ]; then kill -STOP "$child"; fi
    kill -"$interrupt_signal" "$runner"
    code=0
    wait "$runner" || code=$?
    runner=''
    expected=143
    [ "$interrupt_signal" != HUP ] || expected=129
    [ "$code" = "$expected" ]
    [ -f "$work/archive/batch.zip" ]
    [ ! -e "$work/archive/batch" ]
    [ -z "$(find "$work/archive" -maxdepth 1 -name '.mac-unzip.*' -print)" ]
    if kill -0 "$child" 2>/dev/null; then echo "FAIL: ditto child survived $interrupt_signal cancellation"; exit 1; fi
    child=''
    log=$(sed -n 's/^错误日志：//p' "$work/output" | tail -1)
    case "$log" in /tmp/mac-unzip.*/errors.log) rm -rf "${log%/*}" ;; esac
 done
 echo 'PASS: real ditto TERM/HUP cancellation, paused child reaped, staging removed, ZIP preserved'
