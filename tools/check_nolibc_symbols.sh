#!/usr/bin/env bash
# ============================================================
#  tools/check_nolibc_symbols.sh — the hand-synced-twin gate for
#  stdlib/runtime_core.c ↔ unikernel/nolibc/.
#
#  nolibc exists to supply exactly the libc symbols runtime_core calls.
#  That pairing is a hand-synced twin, and this repo's history says
#  those drift silently (install.sh, builtins.nu, the runtime_sources
#  list). So: compile the core, list what it still needs, and require
#  every name to be defined by nolibc. A new libc call in the runtime
#  fails HERE — in the same PR that adds it — instead of at boot in
#  Track B, months later.
#
#  It takes about a second, which is why it can run on every commit
#  while the full corpus-under-nolibc run does not have to.
#
#  Usage:  tools/check_nolibc_symbols.sh
#  Exit:   0 = every symbol accounted for · 1 = drift · 2 = setup error
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOLIBC="$ROOT/unikernel/nolibc"
CC="${CC:-clang}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v "$CC" >/dev/null || { echo "check_nolibc_symbols: no $CC" >&2; exit 2; }
command -v nm  >/dev/null || { echo "check_nolibc_symbols: no nm" >&2; exit 2; }

mkdir -p "$TMP/nl"
"$CC" -O2 -c "$ROOT/stdlib/runtime_core.c" -o "$TMP/core.o" 2>"$TMP/cc.err" || {
    echo "check_nolibc_symbols: runtime_core.c does not compile" >&2
    head -5 "$TMP/cc.err" >&2
    exit 2
}
for f in "$NOLIBC"/*.c; do
    "$CC" -O2 -ffreestanding -fno-builtin -fno-stack-protector \
          -c "$f" -o "$TMP/nl/$(basename "${f%.c}").o" 2>"$TMP/cc.err" || {
        echo "check_nolibc_symbols: $(basename "$f") does not compile" >&2
        head -5 "$TMP/cc.err" >&2
        exit 2
    }
done
# The assembly is per-architecture by name — start_x86_64.S,
# setjmp_x86_64.S, setjmp_aarch64.S — and only THIS host's files
# assemble with THIS host's compiler. Selecting by suffix keeps the
# gate a statement about the machine it runs on; compiling all of them
# would fail on whichever architecture the runner is not, which is
# exactly what the aarch64 port did to this gate on an x86 runner.
case "$(uname -m)" in
    x86_64|amd64) arch_sfx=x86_64 ;;
    aarch64|arm64) arch_sfx=aarch64 ;;
    *) arch_sfx="" ;;
esac
for f in "$NOLIBC"/*.S; do
    b="$(basename "${f%.S}")"
    case "$b" in
        *_x86_64|*_aarch64|*_riscv64)
            [ -n "$arch_sfx" ] && [ "${b%_$arch_sfx}" != "$b" ] || continue ;;
    esac
    "$CC" -c "$f" -o "$TMP/nl/$b.o" || exit 2
done

nm -u "$TMP/core.o" | sed 's/^ *U //' | sort -u > "$TMP/needed"
# T/W/D/B/R: anything nolibc actually defines, in any section.
# Only the nolibc objects — core.o lives one directory up, because
# a "provided" set that included the runtime's own symbols would call
# every gap accounted for.
nm --defined-only "$TMP"/nl/*.o 2>/dev/null \
    | awk '$2 ~ /^[TWDBRV]$/ { print $3 }' | sort -u > "$TMP/provided"

missing=$(comm -23 "$TMP/needed" "$TMP/provided")
if [ -n "$missing" ]; then
    echo "check_nolibc_symbols: runtime_core.c calls libc symbols nolibc does not define:" >&2
    printf '  %s\n' $missing >&2
    echo >&2
    echo "Add them to unikernel/nolibc/ (or stop calling them from the core)." >&2
    echo "A freestanding target cannot borrow one of these from the host." >&2
    exit 1
fi

n_need=$(wc -l < "$TMP/needed")
echo "check_nolibc_symbols: OK — all $n_need libc symbols runtime_core needs are in nolibc"

# The reverse direction is information, not a failure: nolibc may
# legitimately define more than the core uses (the corpus reaches
# printf's %g through variadic FFI, for one), but a large drift here
# means someone is writing libc for its own sake.
extra=$(comm -13 "$TMP/needed" "$TMP/provided" | grep -vE '^(nl_|_start)' | tr '\n' ' ')
[ -n "$extra" ] && echo "  (nolibc also defines, for programs rather than the core: $extra)"

# ── the other twin: a GENERATED file and its generator ────────────
# unikernel/nolibc/math_tables.h is produced by tools/gen_libm_tables.py
# and committed. That is one more pair that drifts silently — someone
# edits a coefficient by hand, or changes a fit degree and forgets to
# regenerate, and the header stops being what the generator says it is.
# Regenerating into a temp file and diffing costs four seconds and makes
# the claim checkable rather than hopeful.
if command -v python3 >/dev/null; then
    if python3 "$ROOT/tools/gen_libm_tables.py" > "$TMP/math_tables.h" 2>"$TMP/gen.err"; then
        if ! diff -q "$TMP/math_tables.h" "$NOLIBC/math_tables.h" >/dev/null; then
            echo "check_nolibc_symbols: unikernel/nolibc/math_tables.h differs from what" >&2
            echo "  tools/gen_libm_tables.py produces. Regenerate it:" >&2
            echo "    python3 tools/gen_libm_tables.py > unikernel/nolibc/math_tables.h" >&2
            diff "$NOLIBC/math_tables.h" "$TMP/math_tables.h" | head -20 >&2
            exit 1
        fi
        echo "check_nolibc_symbols: math_tables.h matches its generator"
    else
        echo "check_nolibc_symbols: gen_libm_tables.py failed" >&2
        head -5 "$TMP/gen.err" >&2
        exit 1
    fi
fi
exit 0
