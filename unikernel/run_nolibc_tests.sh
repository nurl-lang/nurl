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
#          NOLIBC_SHARD=i/n to run the i-th of n round-robin shards
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/compiler/tests"
OUTDIR="$ROOT/build/nolibc"
JOBS="${NOLIBC_JOBS:-$(nproc 2>/dev/null || echo 4)}"

mkdir -p "$OUTDIR/work"
[ -x "$ROOT/build/nurlc" ] || { echo "run ./build.sh first" >&2; exit 2; }
# The hosted runner's predicates for a test's `// requires:` line: a
# hardware requirement (a crypto tier the CPU lacks) means the same here
# as there. The other tokens (live, fibers, commands) are this corpus's
# business — the NURL socket layer and the bare runtime stand in for them.
# shellcheck source=../compiler/tests/test_skips.sh
. "$TESTS/test_skips.sh"

names=("$@")
if [ ${#names[@]} -eq 0 ]; then
    while IFS= read -r f; do names+=("$(basename "${f%.nu}")"); done \
        < <(find "$TESTS" -maxdepth 1 -name '*.nu' | sort)
fi

# Optional sharding, so CI can spread the corpus over several runners,
# as run_san_tests.sh does: NOLIBC_SHARD=i/n (1 <= i <= n) keeps every
# n-th test of the sorted list, starting at the i-th. Round-robin over
# sorted names keeps the shards close in cost, and the n shards together
# are exactly the unsharded set.
if [ -n "${NOLIBC_SHARD:-}" ]; then
    if [[ ! "$NOLIBC_SHARD" =~ ^([0-9]+)/([0-9]+)$ ]] \
        || (( BASH_REMATCH[2] < 1 || BASH_REMATCH[1] < 1 || BASH_REMATCH[1] > BASH_REMATCH[2] )); then
        echo "NOLIBC_SHARD must be i/n with 1 <= i <= n (got '$NOLIBC_SHARD')" >&2; exit 2
    fi
    shard_i=${BASH_REMATCH[1]}; shard_n=${BASH_REMATCH[2]}
    IFS=$'\n' names=($(printf '%s\n' "${names[@]}" | LC_ALL=C sort)); unset IFS
    sharded=()
    for idx in "${!names[@]}"; do
        (( idx % shard_n == shard_i - 1 )) && sharded+=("${names[$idx]}")
    done
    (( ${#sharded[@]} > 0 )) || { echo "shard $NOLIBC_SHARD selects no tests" >&2; exit 2; }
    echo "Shard $shard_i/$shard_n: ${#sharded[@]} of ${#names[@]} tests"
    names=("${sharded[@]}")
fi

one() {
    name="$1"
    src="$TESTS/$name.nu"
    golden="$TESTS/outputs/$name.txt"
    work="$OUTDIR/work/$name"
    mkdir -p "$work"
    [ -f "$golden" ] || { echo "SKIP $name (no golden)"; return 0; }
    # A peer on a real thread over the host kernel's TCP: the duplex test
    # checks SO_SNDBUF, which the NURL socket layer deliberately does not
    # have (it owns its queues — unikernel/net/sockets.nu), and the
    # streaming test bounds a deadline in wall-clock time that a
    # cooperative thread (runtime_bare.c §10) only reaches once the
    # main thread blocks.
    case "$name" in
        http2_client_duplex|http2_client_streaming)
            echo "SKIP $name (needs preemptive threads over host TCP)"; return 0 ;;
    esac
    # What these two pin is the HOSTED runtime's way of not blocking a
    # worker: a connect parked on the host kernel's handshake (the black
    # hole is Linux dropping SYNs to a full accept queue) and getaddrinfo
    # on a resolver thread (`localhost` from /etc/hosts). The NURL socket
    # layer has neither a host kernel nor threads to resolve on — its
    # loopback connect and its lookup run in-process by design.
    case "$name" in
        net_connect_fiber_timeout|net_resolve_fiber)
            echo "SKIP $name (pins host-kernel connect and resolver threads)"; return 0 ;;
    esac
    # The host kernel's TCP is what these pin, and the NURL socket layer
    # is a different, in-process stack by design:
    #   http_response_recycle counts the process's allocations per
    #     request — here that count includes the TCP/IP stack itself,
    #     which runs as NURL code in the same process, so the HTTP
    #     layer's bound (<= 2) cannot be read off it;
    #   http_server_drain times shutdown(2) against a peer blocked in
    #     the host kernel and expects a closed listener to refuse;
    #   net_listen_opts binds two listeners with SO_REUSEPORT, which the
    #     socket layer does not have (one owner per port).
    case "$name" in
        http_response_recycle|http_server_drain|net_listen_opts)
            echo "SKIP $name (pins the host kernel's TCP)"; return 0 ;;
    esac
    # A deadline against a peer that never answers: the NURL socket layer
    # sees that nothing can ever make the wait succeed (loopback only, no
    # runnable coroutine) and fails it AT ONCE — by design, see
    # unikernel/net/sockets.nu — so there is no deadline left to measure.
    case "$name" in
        tls_connect_deadline)
            echo "SKIP $name (silent peer: the loopback stack fails the wait at once)"; return 0 ;;
    esac
    # kTLS hands record protection to the HOST kernel; the NURL socket
    # layer here has no kernel to hand it to (tls_ktls reports 0), so a
    # test declaring `requires: ktls` describes a run this is not.
    if sed -n '1,40p' "$src" | grep -qE '^[[:space:]]*//[[:space:]]*requires:.*\bktls\b'; then
        echo "SKIP $name (requires: ktls — the host kernel's TLS)"; return 0
    fi
    # Only run a test whose golden says what running it should DO. Ask
    # the GOLDEN, not the name: run_san_tests.sh settled that rule
    # already — "should_fail_*, diag_*, borrow_*, and whatever
    # tomorrow's negative test is called" — and the general form is an
    # `EXIT` line. A negative test has none because it never links; a
    # `lint_*` test has none because what it baselines is the WARNINGS
    # its source provokes, not its behaviour. Both were added to the
    # corpus after this runner was written, and both made it try to
    # execute something whose golden could not describe the result.
    grep -q '^EXIT ' "$golden" || {
        echo "SKIP $name (golden describes no run)"; return 0
    }
    local tok
    for tok in $(test_requires "$name"); do
        case "$tok" in
            cpu-aes)     host_has_cpu_aes     || { echo "SKIP $name (requires $tok)"; return 0; } ;;
            cpu-vaes)    host_has_cpu_vaes    || { echo "SKIP $name (requires $tok)"; return 0; } ;;
            cpu-vaes512) host_has_cpu_vaes512 || { echo "SKIP $name (requires $tok)"; return 0; } ;;
            cpu-ifma)    host_has_cpu_ifma    || { echo "SKIP $name (requires $tok)"; return 0; } ;;
        esac
    done

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
    # …and strip the repo root, as both hosted runners do: an index panic
    # names its caller's file as compiled (absolute here).
    got_out=$(sed -e 's/\r$//' -e "s|$ROOT/||g" "$work/out.raw")
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
