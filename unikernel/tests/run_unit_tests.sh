#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/run_unit_tests.sh — the nolibc unit gates.
#
#  Three oracles, none of them "it didn't crash":
#
#    string_diff      every mem*/str* against glibc's, swept over all
#                     alignments and lengths rather than sampled —
#                     that is where a word-at-a-time loop goes wrong.
#                     Built with the nolibc names redefined so both
#                     implementations are callable in one process.
#    float_fmt_diff   %f/%e/%g against glibc at every precision from 0
#                     to 20, over random and adversarial doubles. These
#                     conversions have exactly one right answer.
#    malloc_fuzz      random malloc/calloc/realloc/free with a pattern
#                     in every block, re-checked on every touch. Built
#                     -nostdlib, because ASan cannot supervise an
#                     allocator it has replaced.
#    sched_gate       the cooperative scheduler's SCHEDULE, asserted as
#                     a trace string, plus the four deadlock scenarios
#                     and the stack guard page — each of which must end
#                     the process rather than hang or corrupt.
#    pthread_layout   the bare mutex/cond fit the allocation the NURL
#                     side makes from the real <pthread.h>.
#    math_diff        every libm entry against glibc's, in ULPS, over
#                     ranges chosen for where a libm actually breaks —
#                     the huge argument, the near-cancellation, the
#                     branch boundary. sqrt/fabs/floor/ceil/trunc/round
#                     are held to bit equality; cbrt is checked against
#                     arithmetic instead, because glibc's cbrt is the
#                     less accurate of the two.
#
#  Usage: unikernel/tests/run_unit_tests.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOLIBC="$ROOT/unikernel/nolibc"
OUT="${NURL_NOLIBC_OUT:-$ROOT/build/nolibc}"
CC="${CC:-clang}"
FREE="-O2 -ffreestanding -fno-builtin -fno-stack-protector"
fail=0

mkdir -p "$OUT"

step() {
    printf '  %-18s ' "$1"; shift
    if out=$("$@" 2>&1); then
        echo "ok — ${out##*$'\n'}"
    else
        echo "FAILED"
        printf '%s\n' "$out" | sed 's/^/      /' | head -14
        fail=1
    fi
}

echo "── nolibc unit gates ──"

# 1. strings, against glibc, in one process (names redefined)
# shellcheck disable=SC2086
$CC $FREE -Dmemcpy=nl_memcpy -Dmemmove=nl_memmove -Dmemset=nl_memset \
    -Dmemchr=nl_memchr -Dmemcmp=nl_memcmp -Dbcmp=nl_bcmp \
    -Dstrlen=nl_strlen -Dstrcmp=nl_strcmp -Dstrchr=nl_strchr \
    -Dstrrchr=nl_strrchr -Dstrncmp=nl_strncmp -Dmemmem=nl_memmem -Dstrstr=nl_strstr \
    -Dstrncpy=nl_strncpy -Datoll=nl_atoll -Datol=nl_atol -Datoi=nl_atoi -Dabs=nl_abs \
    -Dllabs=nl_llabs -Dstrdup=nl_strdup \
    -c "$NOLIBC/string.c" -o "$OUT/test_string_renamed.o" || exit 2
$CC -O2 "$ROOT/unikernel/tests/string_diff.c" "$OUT/test_string_renamed.o" \
    -o "$OUT/string_diff" || exit 2
step string_diff "$OUT/string_diff"

# 2. float formatting, against glibc
# shellcheck disable=SC2086
$CC $FREE -c "$NOLIBC/dtoa.c" -o "$OUT/test_dtoa.o" || exit 2
$CC -O2 "$ROOT/unikernel/tests/float_fmt_diff.c" "$OUT/test_dtoa.o" \
    -o "$OUT/float_fmt_diff" -lm || exit 2
for seed in 7 1234 99999; do
    step "float_fmt(seed $seed)" "$OUT/float_fmt_diff" 200000 "$seed"
done

# 3. the allocator, with no libc under it at all
for f in string malloc stdio dtoa math misc syscall_linux tls_linux; do
    # shellcheck disable=SC2086
    $CC $FREE -c "$NOLIBC/$f.c" -o "$OUT/nl_$f.o" || exit 2
done
for f in start_x86_64 setjmp_x86_64; do
    $CC -c "$NOLIBC/$f.S" -o "$OUT/nl_$f.o" || exit 2
done
# shellcheck disable=SC2086
$CC $FREE -c "$ROOT/unikernel/tests/malloc_fuzz.c" -o "$OUT/malloc_fuzz.o" || exit 2
$CC -nostdlib -static -o "$OUT/malloc_fuzz" "$OUT/malloc_fuzz.o" "$OUT"/nl_*.o || exit 2
step malloc_fuzz "$OUT/malloc_fuzz"

# 3b. the page allocator under that allocator — the guest's mmap and
# munmap. Ordinary hosted C: it is portable by construction, and the
# oracle needs a real region to write patterns into.
# shellcheck disable=SC2086
$CC -O2 -o "$OUT/pagealloc_fuzz" "$ROOT/unikernel/tests/pagealloc_fuzz.c" \
    "$ROOT/unikernel/boot/pagealloc.c" || exit 2
step pagealloc_fuzz "$OUT/pagealloc_fuzz"

# 4. the cooperative scheduler, with no libc under it either.
# shellcheck disable=SC2086
$CC $FREE -c "$ROOT/unikernel/runtime_bare.c" -o "$OUT/runtime_bare.o" || exit 2
$CC -O2 -c "$ROOT/stdlib/runtime_ctx.c" -o "$OUT/runtime_ctx.o" || exit 2
# shellcheck disable=SC2086
$CC $FREE -c "$ROOT/unikernel/tests/sched_gate.c" -o "$OUT/sched_gate.o" || exit 2
$CC -nostdlib -static -o "$OUT/sched_gate" "$OUT/sched_gate.o" \
    "$OUT/runtime_bare.o" "$OUT/runtime_ctx.o" "$OUT"/nl_*.o || exit 2
step sched_gate "$OUT/sched_gate"

# The negative half. Each of these is a program a preemptive runtime
# would hang on; the scheduler must instead prove no progress is
# possible and abort. `timeout` is the whole assertion — a detector that
# does not fire looks exactly like one that does, minus the exit status.
#
# 134 = 128 + SIGABRT, the status a shell reports for abort(); 139 =
# 128 + SIGSEGV, which is what a guard page is for.
expect_signal() {
    local scenario="$1" want="$2" note="$3"
    printf '  %-18s ' "sched($scenario)"
    out=$(timeout -k 5s 20s "$OUT/sched_gate" "$scenario" 2>&1)
    rc=$?
    if [ "$rc" = "$want" ]; then
        echo "ok — $note"
    elif [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
        echo "FAILED — hung; the detector did not fire"
        fail=1
    else
        echo "FAILED — exit $rc, want $want"
        printf '%s\n' "$out" | sed 's/^/      /' | head -6
        fail=1
    fi
}
expect_signal deadlock-mutex 134 "self-deadlock reported, not hung"
expect_signal deadlock-cond  134 "cond_wait with no signaller reported"
expect_signal deadlock-join  134 "join on a permanently parked thread reported"
expect_signal deadlock-run   134 "runtime_run with a stuck fiber reported"
expect_signal stack-overflow 139 "coroutine stack overflow faults"
expect_signal guard-write    139 "one byte below the stack faults — the guard page is armed"
expect_signal entropy-fault  134 "a refusing entropy source ends the program"

# 5. libm, against glibc, in one process — the nolibc names renamed so
#    both implementations are callable. Several seeds: the ranges are
#    sampled, and one seed's worst case is not the function's.
# shellcheck disable=SC2086
$CC $FREE $(for f in sqrt fabs floor ceil trunc round copysign exp log log2 log10 \
                    sin cos tan atan atan2 pow cbrt hypot erf erfc; do
                printf -- '-D%s=nl_%s ' "$f" "$f"; done) \
    -c "$NOLIBC/math.c" -o "$OUT/test_math_renamed.o" || exit 2
$CC -O2 "$ROOT/unikernel/tests/math_diff.c" "$OUT/test_math_renamed.o" \
    -o "$OUT/math_diff" -lm || exit 2
for seed in 7 99 12345; do
    step "math_diff(seed $seed)" "$OUT/math_diff" 60000 "$seed"
done

# 6. build_unikernel.sh is a tool: foreign cwd, read-only repo,
#    concurrent byte-identical builds, loud failures. Skips itself
#    when build/nurlc is absent (the other gates here need only $CC).
step build_tool_gate "$ROOT/unikernel/tests/build_tool_gate.sh"

# 7. the bare mutex/cond fit what the NURL side allocates for them.
#    Hosted on purpose: the comparison needs the real <pthread.h>, which
#    is precisely what the freestanding build does not have.
$CC -O2 "$ROOT/unikernel/tests/pthread_layout.c" "$OUT/runtime_bare.o" \
    "$OUT/runtime_ctx.o" -o "$OUT/pthread_layout" || exit 2
step pthread_layout "$OUT/pthread_layout"

[ $fail -eq 0 ] && echo "  all nolibc unit gates passed"
exit $fail
