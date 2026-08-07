#!/usr/bin/env bash
# ============================================================
#  unikernel/run_nolibc_tests.sh — how much of the corpus runs with no
#  libc at all?
#
#  Every test in compiler/tests/ is built against unikernel/nolibc with
#  -nostdlib and run, and its stdout + exit status are compared with the
#  EXIT/OUTPUT sections of its ordinary golden.
#
#    PASS      same output and exit status as the hosted build
#    FAIL      linked and ran, and disagreed with the golden. This is
#              the interesting column — a nolibc bug.
#    SKIP      compile-fail test, or no standalone build
#
#  and, for a test that did not link, WHICH piece of work it is waiting
#  on — because "did not link" pooled three unrelated things and made
#  the count a liar:
#
#    NEEDS-BARE    a symbol the hosted runtime defines. That is
#                  unikernel/runtime_bare.c's surface — sockets and the
#                  reactor (phase A4), processes, signals.
#    NEEDS-LIBM    a libm entry. nolibc has no math yet.
#    NEEDS-NOLIBC  a libc entry nolibc has not written (realpath,
#                  mkstemp, inotify).
#    NEEDS-LIB     a THIRD-PARTY C library — libsqlite3, libzstd. Not
#                  remaining work in any sense: a unikernel does not
#                  link these, and putting them in the same bucket as
#                  A4 made the backlog look larger than it is.
#    NEEDS-FFI     nothing on this machine defines it. The catch-all,
#                  kept so a symbol can never be quietly dropped.
#
#  The bucket is MEASURED, not listed: each missing symbol is looked up
#  with `nm` in the hosted runtime.o and in the shared objects the
#  ordinary link line names, and the answer is whichever file actually
#  defines it. A hand-kept list of names is exactly what gated the whole
#  live surface out of CI twice (see the plan's findings 1 and 11), and
#  it would drift here the same way.
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

    # Compile, and link in the NURL socket layer if this program needs
    # it — see unikernel/compile_nu.sh for why that is a recompile
    # rather than another object on the link line.
    NURL_COMPILE_QUIET=1 "$ROOT/unikernel/compile_nu.sh" "$src" "$work/$name.ll" "$work"
    case $? in
        0) ;;
        3) echo "SKIP $name (does not compile standalone)"; return 0 ;;
        *) echo "SKIP $name (IR would not compile)"; return 0 ;;
    esac
    if ! clang -nostdlib -static -o "$work/$name" "$work/$name.o" \
            "$OUTDIR/runtime_core.o" "$OUTDIR/runtime_ctx.o" \
            "$OUTDIR/runtime_bare.o" "$OUTDIR"/nl_*.o 2>"$work/link.err"; then
        # GNU ld says "undefined reference to `name'"; lld says
        # "undefined symbol: name". Match both, or the list this runner
        # exists to produce is the string "<link error>" 139 times.
        missing=$(grep -oE "undefined (reference to \`|symbol: )[A-Za-z0-9_]+" "$work/link.err" \
                  | sed -E "s/undefined (reference to \`|symbol: )//" | sort -u)
        if [ -z "$missing" ]; then
            echo "NEEDS-FFI $name :: <link error>"
            return 0
        fi
        # Bucket by whoever actually defines the symbol (see header).
        # Strongest statement first: a test that needs a third-party
        # library is not waiting on us at all.
        verdict=NEEDS-NOLIBC
        want=""
        while IFS= read -r sym; do
            [ -n "$sym" ] || continue
            owner=$(grep -m1 "^$sym " "$OUTDIR/symowner.txt" | cut -d' ' -f2)
            case "$owner" in
                bare)   [ "$verdict" = NEEDS-LIB ] || verdict=NEEDS-BARE ;;
                libm)   case "$verdict" in NEEDS-LIB|NEEDS-BARE) ;; *) verdict=NEEDS-LIBM ;; esac ;;
                libc)   ;;                       # the weakest: leave as NOLIBC
                "")     case "$verdict" in NEEDS-LIB|NEEDS-BARE) ;; *) verdict=NEEDS-FFI ;; esac ;;
                *)      verdict=NEEDS-LIB; want="$want $owner" ;;
            esac
        done <<< "$missing"
        # For a third-party dependency the library name is the answer;
        # forty sqlite3_ entries are noise.
        if [ "$verdict" = NEEDS-LIB ]; then
            list=$(printf '%s\n' $want | sort -u | tr '\n' ' ')
        else
            list=$(printf '%s ' $missing)
        fi
        echo "$verdict $name :: $list"
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
for f in string malloc stdio dtoa math misc syscall_linux tls_linux; do
    clang -O2 -ffreestanding -fno-builtin -fno-stack-protector \
          -c "$ROOT/unikernel/nolibc/$f.c" -o "$OUTDIR/nl_$f.o" || exit 2
done
for f in start_x86_64 setjmp_x86_64; do
    clang -c "$ROOT/unikernel/nolibc/$f.S" -o "$OUTDIR/nl_$f.o" || exit 2
done

# ── who defines what ────────────────────────────────────────────
# Built once, by asking real files. Two sources, in the order a
# verdict should prefer them:
#
#   stdlib/runtime.o   the hosted runtime. A symbol here is
#                      runtime_bare.c's surface by definition — it is
#                      exactly what the freestanding twin has to grow.
#   the shared objects the ordinary link line pulls in. Which ones
#                      those are is not guessed either: a probe binary
#                      is linked the same way nurl.sh links a program
#                      and `ldd` names the files.
#
# libm before libc, because glibc exports some math entries from both
# and "needs libm" is the more useful answer.
build_sym_owner() {
    : > "$OUTDIR/symowner.txt"
    if [ -f "$ROOT/stdlib/runtime.o" ]; then
        nm -g --defined-only "$ROOT/stdlib/runtime.o" 2>/dev/null \
            | awk '{ if (NF >= 3) { t = $(NF-1); n = $NF } else { t = $1; n = $2 }
                     if (t ~ /^[TWDBRi]$/) print n" bare" }' >> "$OUTDIR/symowner.txt"
    else
        echo "note: stdlib/runtime.o absent (run ./build.sh) —" \
             "runtime_bare work cannot be told from libc gaps" >&2
    fi
    # Which shared object holds a library is asked of the linker, not
    # assumed: each candidate is probed with a program that REFERENCES
    # one of its symbols, because --as-needed drops a -l whose symbols
    # nobody uses and `ldd` on an empty main would then list libc alone.
    probe_lib() {
        local lib="$1" decl="$2"
        local src="$OUTDIR/.symprobe.c" bin="$OUTDIR/.symprobe"
        printf '%s\nint main(void){return use();}\n' "$decl" > "$src"
        clang "$src" "-l$lib" -o "$bin" 2>/dev/null || { rm -f "$src"; return 1; }
        ldd "$bin" 2>/dev/null | awk '{print $3}' \
            | grep -E "^/.*/lib$lib[.-]" | head -1
        rm -f "$src" "$bin"
    }
    # libm first, then libc: glibc exports a few math entries from both,
    # and "needs libm" is the more useful of the two answers.
    for spec in \
        "m|double sin(double); int use(void){return (int)sin(1.0);}" \
        "c|int use(void){return 0;}" \
        "sqlite3|int sqlite3_libversion_number(void); int use(void){return sqlite3_libversion_number();}" \
        "zstd|unsigned ZSTD_versionNumber(void); int use(void){return (int)ZSTD_versionNumber();}"
    do
        lib="${spec%%|*}"
        so=$(probe_lib "$lib" "${spec#*|}") || continue
        [ -n "$so" ] || continue
        # `nm -D` prints the versioned name (malloc@@GLIBC_2.2.5); the
        # linker's undefined list prints the bare one, so strip the
        # version or nothing ever matches — libc looked empty until it
        # did.
        nm -D --defined-only "$so" 2>/dev/null \
            | awk -v tag="lib$lib" '{ if (NF >= 3) { t = $(NF-1); n = $NF } else { t = $1; n = $2 }
                     sub(/@.*/, "", n)
                     if (t ~ /^[TWDBRi]$/) print n" "tag }' >> "$OUTDIR/symowner.txt"
    done
    # First definition wins, so the file stays in preference order.
    sort -s -k1,1 -u "$OUTDIR/symowner.txt" -o "$OUTDIR/symowner.txt"
}
build_sym_owner

printf '%s\n' "${names[@]}" | xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} \
    > "$OUTDIR/results.txt" 2>&1

sort "$OUTDIR/results.txt" | grep -E "^FAIL" || true
echo "── nolibc corpus run ──"
for tag in PASS FAIL NEEDS-BARE NEEDS-LIBM NEEDS-NOLIBC NEEDS-LIB NEEDS-FFI SKIP; do
    printf '  %-10s %s\n' "$tag" "$(grep -c "^$tag " "$OUTDIR/results.txt" || true)"
done
echo "  full results: $OUTDIR/results.txt"
grep -q "^FAIL " "$OUTDIR/results.txt" && exit 1
exit 0
