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
for f in "$NOLIBC"/*.S; do
    "$CC" -c "$f" -o "$TMP/nl/$(basename "${f%.S}").o" || exit 2
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
exit 0
