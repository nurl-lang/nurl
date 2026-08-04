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
    -Dstrlen=nl_strlen -Dstrcmp=nl_strcmp \
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
for f in string malloc stdio dtoa misc syscall_linux tls_linux; do
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

[ $fail -eq 0 ] && echo "  all nolibc unit gates passed"
exit $fail
