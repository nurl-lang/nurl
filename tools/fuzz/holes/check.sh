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
#   UNCHECKED — no verdict: the build failed without a compile error (a
#               missing stdlib/runtime.o, a broken toolchain), the sanitizer
#               build produced no binary (no ASan runtime, libclang_rt.asan),
#               or the run outlived HOLES_TIMEOUT (default 60 s). Counted as
#               a failure, never as rejected or clean.
# Exit status = the number of HOLEs plus the number of UNCHECKED probes
# (at most 255).
#
#   tools/fuzz/holes/check.sh                 # all probes
#   tools/fuzz/holes/check.sh drop_try_*.nu   # some
#
# A probe is named for what it breaks (lower_snake_case, no number), and
# its leading comment block carries a `// map: rule | phase | nurlc | old id
# | note` line: tools/fuzz/holes/map.py builds formal/corpus/map.tsv from
# those lines (Agora #212). A new probe needs no number claimed anywhere.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DIR="$ROOT/tools/fuzz/holes"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
holes=0
unchecked=0
limit="${HOLES_TIMEOUT:-60}"
cd "$DIR"
# (stdlib/: a probe that must sit in a directory named `stdlib` —
# trusted_by_path_substring, a program's own code there is not the trusted
# standard library.)
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(*.nu stdlib/*.nu)
for f in "${files[@]}"; do
    b="$TMP/$(basename "$f" .nu)"
    out=$(cd "$ROOT" && ./nurl.sh "$DIR/$f" "$b" 2>&1); rc=$?
    if [ $rc -ne 0 ]; then
        # Rejected means the compiler refused it: nurlc names the place in
        # a source file (`f.nu:LINE:COL: error:`). A build that failed
        # otherwise never reached the checker: with no stdlib/runtime.o, or
        # a linker that fails, every probe "was rejected" and the run
        # reported no holes.
        if grep -qE '\.nu:[0-9]+:[0-9]+: error:' <<<"$out"; then
            echo "REJECTED  $f: $(grep -m1 -oE 'error: .{0,110}' <<<"$out")"
        else
            echo "UNCHECKED $f: the build failed without a compile error: $(grep -m1 -v '^\s*$' <<<"$out" | cut -c1-110)"
            unchecked=$((unchecked+1))
        fi
        continue
    fi
    sout=$(cd "$ROOT" && NURL_SAN=1 ./nurl.sh "$DIR/$f" "${b}_san" 2>&1)
    # A sanitizer build that produced no binary is no verdict either. Without
    # the ASan runtime the missing binary was run, printed no fault, and the
    # probe was counted clean.
    if [ ! -x "${b}_san" ]; then
        echo "UNCHECKED $f: the sanitizer build failed: $(grep -m1 -v '^\s*$' <<<"$sout" | cut -c1-110)"
        unchecked=$((unchecked+1)); continue
    fi
    # (A frame handed out lives on ASan's fake stack: without
    # detect_stack_use_after_return a read through it after the return
    # "runs clean".)
    r=$(ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_stack_use_after_return=1" timeout "$limit" "${b}_san" 2>&1 >/dev/null); rr=$?
    k=$(grep -m1 -oE "heap-use-after-free|double-free|attempting free|heap-buffer-overflow|stack-use-after-return|stack-use-after-scope|detected memory leaks|SEGV|runtime error" <<<"$r")
    if [ -n "$k" ]; then echo "HOLE      $f: $k"; holes=$((holes+1))
    elif [ $rr -eq 124 ]; then echo "UNCHECKED $f: still running under ASan after ${limit} s"; unchecked=$((unchecked+1))
    else echo "ACCEPTED  $f: ran clean"; fi
done
echo "holes: $holes"
[ $unchecked -eq 0 ] || echo "unchecked: $unchecked (no verdict: see the UNCHECKED lines)"
# (An exit status is one byte: 256 failures would read as success.)
n=$((holes + unchecked)); [ $n -gt 255 ] && n=255
exit $n
