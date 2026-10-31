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
#   HOLES_JOBS=N                              # probes at once (default: CPUs)
#
# Probes are independent, so they are checked in parallel (Agora #251: one
# at a time they took 6.6 min of CI's critical path). Each writes its
# verdict line to its own file, and the report prints them in the order the
# probes were given, so it reads the same at any HOLES_JOBS.
#
# A probe is named for what it breaks (lower_snake_case, no number), and
# its leading comment block carries a `// map: rule | phase | nurlc | old id
# | note` line: tools/fuzz/holes/map.py builds formal/corpus/map.tsv from
# those lines (Agora #212). A new probe needs no number claimed anywhere.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DIR="$ROOT/tools/fuzz/holes"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
limit="${HOLES_TIMEOUT:-60}"
jobs="${HOLES_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
cd "$DIR"
# (stdlib/: a probe that must sit in a directory named `stdlib` —
# trusted_by_path_substring, a program's own code there is not the trusted
# standard library.)
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(*.nu stdlib/*.nu)

# check_one INDEX SOURCE LABEL: print exactly one verdict line for the probe
# at SOURCE, named LABEL (a probe's own name, or `twin:` and its name).
check_one() {
    local src="$2" f="$3" b out rc sout r rr k
    b="$TMP/$1.$(basename "$src" .nu)"
    out=$(cd "$ROOT" && ./nurl.sh "$src" "$b" 2>&1); rc=$?
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
        fi
        return
    fi
    sout=$(cd "$ROOT" && NURL_SAN=1 ./nurl.sh "$src" "${b}_san" 2>&1)
    # A sanitizer build that produced no binary is no verdict either. Without
    # the ASan runtime the missing binary was run, printed no fault, and the
    # probe was counted clean.
    if [ ! -x "${b}_san" ]; then
        echo "UNCHECKED $f: the sanitizer build failed: $(grep -m1 -v '^\s*$' <<<"$sout" | cut -c1-110)"
        return
    fi
    # (A frame handed out lives on ASan's fake stack: without
    # detect_stack_use_after_return a read through it after the return
    # "runs clean".)
    r=$(ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_stack_use_after_return=1" timeout "$limit" "${b}_san" 2>&1 >/dev/null); rr=$?
    k=$(grep -m1 -oE "heap-use-after-free|double-free|attempting free|heap-buffer-overflow|stack-use-after-return|stack-use-after-scope|detected memory leaks|SEGV|runtime error" <<<"$r")
    if [ -n "$k" ]; then echo "HOLE      $f: $k"
    elif [ $rr -eq 124 ]; then echo "UNCHECKED $f: still running under ASan after ${limit} s"
    else echo "ACCEPTED  $f: ran clean"; fi
}
export -f check_one
export ROOT DIR TMP limit

# Every probe, then each one's elaborated twin (elab.py): its producer form
# bound by `:` first, the consumer reading the binding — the calculus's
# shape, and the path every consumer takes once producers are elaborated
# (Agora #222). A twin that faults is a hole like any other (Agora #242);
# the ones known open are listed in open/twins.txt and not run.
srcs=(); labels=()
for f in "${files[@]}"; do srcs+=("$DIR/$f"); labels+=("$f"); done
elab_failed=0
if [ -f "$DIR/elab.py" ]; then
    if twins=$(python3 "$DIR/elab.py" "$TMP/twins" "${files[@]}"); then
        for t in $twins; do srcs+=("$TMP/twins/$t"); labels+=("twin:$t"); done
    else
        elab_failed=1
    fi
fi
mkdir -p "$TMP/v"
for i in "${!srcs[@]}"; do printf '%s\t%s\t%s\0' "$i" "${srcs[$i]}" "${labels[$i]}"; done \
    | xargs -0 -P "$jobs" -n 1 bash -c 'IFS=$'"'"'\t'"'"' read -r i s f <<<"$1"; check_one "$i" "$s" "$f" > "$TMP/v/$i"' _
holes=0
unchecked=0
[ $elab_failed -eq 0 ] || { echo "UNCHECKED elab.py failed: no twin was checked"; unchecked=$((unchecked+1)); }
for i in "${!srcs[@]}"; do
    if [ -s "$TMP/v/$i" ]; then
        line=$(cat "$TMP/v/$i")
    else
        line="UNCHECKED ${labels[$i]}: the check itself printed no verdict"
    fi
    echo "$line"
    case "$line" in
        HOLE*)      holes=$((holes+1)) ;;
        UNCHECKED*) unchecked=$((unchecked+1)) ;;
    esac
done
echo "holes: $holes"
[ $unchecked -eq 0 ] || echo "unchecked: $unchecked (no verdict: see the UNCHECKED lines)"
# (An exit status is one byte: 256 failures would read as success.)
n=$((holes + unchecked)); [ $n -gt 255 ] && n=255
exit $n
