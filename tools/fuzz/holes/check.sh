#!/bin/bash
# tools/fuzz/holes/check.sh — the soundness hole count.
#
# Every program here is memory-unsafe or leaks, written in SAFE code (no
# `*T`, no `nurl_alloc`, no FFI of its own). The goal is that the compiler
# rejects every one of them. For each file:
#   REJECTED  — the checker caught it (the goal);
#   HOLE      — it compiled, and ASan/LSan faulted at run time (a proven hole);
#   ACCEPTED  — it compiled and ran clean (the probe no longer reaches the
#               fault, or the fault is timing-dependent; inspect).
# Exit status = the number of HOLEs.
#
#   tools/fuzz/holes/check.sh            # all probes
#   tools/fuzz/holes/check.sh h07_*.nu   # some
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DIR="$ROOT/tools/fuzz/holes"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
holes=0
cd "$DIR"
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(h*.nu)
for f in "${files[@]}"; do
    b="$TMP/$(basename "$f" .nu)"
    out=$(cd "$ROOT" && ./nurl.sh "$DIR/$f" "$b" 2>&1); rc=$?
    if [ $rc -ne 0 ]; then
        echo "REJECTED  $f: $(grep -m1 -oE 'error: .{0,110}' <<<"$out")"
        continue
    fi
    (cd "$ROOT" && NURL_SAN=1 ./nurl.sh "$DIR/$f" "${b}_san" >/dev/null 2>&1)
    r=$(timeout 60 "${b}_san" 2>&1 >/dev/null)
    k=$(grep -m1 -oE "heap-use-after-free|double-free|attempting free|heap-buffer-overflow|stack-use-after-return|detected memory leaks|SEGV|runtime error" <<<"$r")
    if [ -n "$k" ]; then echo "HOLE      $f: $k"; holes=$((holes+1)); else echo "ACCEPTED  $f: ran clean"; fi
done
echo "holes: $holes"
exit $holes
