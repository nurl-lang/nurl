#!/usr/bin/env bash
# ============================================================
#  unikernel/run_nolibc_tests.sh — how much of the corpus runs with no
#  libc at all?
#
#  Every test in compiler/tests/ is built against unikernel/nolibc with
#  -nostdlib and run, and its stdout + exit status are compared with the
#  EXIT/OUTPUT sections of its ordinary golden. Three outcomes:
#
#    PASS      same output and exit status as the hosted build
#    NEEDS-FFI did not link — it calls into runtime_ffi (sockets,
#              threads, processes), which runtime_bare.c will provide.
#              The missing symbols are printed: that list IS the
#              remaining A3 work, measured instead of guessed.
#    FAIL      linked and ran, and disagreed with the golden. This is
#              the interesting column — a nolibc bug.
#
#  Usage:  unikernel/run_nolibc_tests.sh [name …]      (default: all)
#          NOLIBC_JOBS=N to parallelise
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/compiler/tests"
OUTDIR="$ROOT/build/nolibc"
JOBS="${NOLIBC_JOBS:-$(nproc 2>/dev/null || echo 4)}"

mkdir -p "$OUTDIR/work"
[ -x "$ROOT/build/nurlc" ] || { echo "run ./build.sh first" >&2; exit 2; }

names=("$@")
if [ ${#names[@]} -eq 0 ]; then
    while IFS= read -r f; do names+=("$(basename "${f%.nu}")"); done \
        < <(find "$TESTS" -maxdepth 1 -name '*.nu' | sort)
fi

one() {
    name="$1"
    src="$TESTS/$name.nu"
    golden="$TESTS/outputs/$name.txt"
    work="$OUTDIR/work/$name"
    mkdir -p "$work"
    # should_fail_* and friends never produce a binary; skip by shape.
    case "$name" in should_*|borrow_*|diag_*) echo "SKIP $name (compile-fail test)"; return 0 ;; esac
    [ -f "$golden" ] || { echo "SKIP $name (no golden)"; return 0; }

    if ! "$ROOT/build/nurlc" "$src" > "$work/$name.ll" 2>"$work/compile.err"; then
        echo "SKIP $name (does not compile standalone)"
        return 0
    fi
    if ! clang -O2 -c "$work/$name.ll" -o "$work/$name.o" 2>"$work/cc.err"; then
        echo "SKIP $name (IR would not compile)"
        return 0
    fi
    if ! clang -nostdlib -static -o "$work/$name" "$work/$name.o" \
            "$OUTDIR/runtime_core.o" "$OUTDIR/runtime_ctx.o" \
            "$OUTDIR/runtime_bare.o" "$OUTDIR"/nl_*.o 2>"$work/link.err"; then
        # GNU ld says "undefined reference to `name'"; lld says
        # "undefined symbol: name". Match both, or the list this runner
        # exists to produce is the string "<link error>" 139 times.
        missing=$(grep -oE "undefined (reference to \`|symbol: )[A-Za-z0-9_]+" "$work/link.err" \
                  | sed -E "s/undefined (reference to \`|symbol: )//" | sort -u | tr '\n' ' ')
        echo "NEEDS-FFI $name :: ${missing:-<link error>}"
        return 0
    fi
    want_exit=$(sed -n 's/^EXIT //p' "$golden" | head -1)
    want_out=$(sed -n '/^OUTPUT$/,$p' "$golden" | tail -n +2)
    # Invoke exactly as run_tests.sh does — from the binary's own
    # directory, as ./name — because a test that prints argv[0] goldens
    # that spelling; and normalise trailing \r the same way, because the
    # goldens are stored \r-stripped (.gitattributes contract) while
    # three HTTP tests legitimately emit \r\n. Neither is a nolibc
    # property, and a runner that differs from the hosted one on either
    # reports its own harness as a libc bug.
    # Redirect to a file and normalise afterwards, exactly as
    # run_tests.sh does. Piping the program into sed instead would put
    # the run inside a command substitution, where PIPESTATUS no longer
    # describes it — every test then reports exit 0, and the four tests
    # whose golden exit status is their answer "fail" for a reason that
    # is entirely the harness's.
    ( cd "$work" && timeout -k 5s 60s "./$name" > "$work/out.raw" 2>&1 )
    got_exit=$?
    got_out=$(sed 's/\r$//' "$work/out.raw")
    if [ "$got_exit" = "$want_exit" ] && [ "$got_out" = "$want_out" ]; then
        echo "PASS $name"
    else
        echo "FAIL $name (exit $got_exit, want ${want_exit:-?})"
        diff <(printf '%s\n' "$want_out") <(printf '%s\n' "$got_out") \
            | head -6 | sed 's/^/     /'
    fi
}
export -f one
export ROOT TESTS OUTDIR

# Build the shared objects once.
clang -O2 -c "$ROOT/stdlib/runtime_core.c" -o "$OUTDIR/runtime_core.o" || exit 2
clang -O2 -c "$ROOT/stdlib/runtime_ctx.c"  -o "$OUTDIR/runtime_ctx.o"  || exit 2
clang -O2 -ffreestanding -fno-stack-protector \
      -c "$ROOT/unikernel/runtime_bare.c" -o "$OUTDIR/runtime_bare.o"  || exit 2
for f in string malloc stdio dtoa misc syscall_linux tls_linux; do
    clang -O2 -ffreestanding -fno-builtin -fno-stack-protector \
          -c "$ROOT/unikernel/nolibc/$f.c" -o "$OUTDIR/nl_$f.o" || exit 2
done
for f in start_x86_64 setjmp_x86_64; do
    clang -c "$ROOT/unikernel/nolibc/$f.S" -o "$OUTDIR/nl_$f.o" || exit 2
done

printf '%s\n' "${names[@]}" | xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} \
    > "$OUTDIR/results.txt" 2>&1

sort "$OUTDIR/results.txt" | grep -E "^FAIL" || true
echo "── nolibc corpus run ──"
for tag in PASS FAIL NEEDS-FFI SKIP; do
    printf '  %-10s %s\n' "$tag" "$(grep -c "^$tag " "$OUTDIR/results.txt" || true)"
done
echo "  full results: $OUTDIR/results.txt"
grep -q "^FAIL " "$OUTDIR/results.txt" && exit 1
exit 0
