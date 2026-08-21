#!/usr/bin/env bash
# ============================================================
#  unikernel/measure_capability.sh — which of these programs build as
#  unikernel images? MEASURED, not listed.
#
#  Usage:  measure_capability.sh <dir-of-.nu-programs> <out.json>
#
#  Each program is built with build_unikernel.sh exactly as a
#  playground request would build it. The verdict is the link's: a
#  program that produces an ELF is capable; one that does not is
#  reported with the missing symbols that stopped it — `fork`,
#  `sqlite3_open`, `nurl_canvas_init` say more than any category label,
#  and a hand-kept list of "known incapable" names is exactly the kind
#  of list that rots (it has cost this repo its CI coverage twice).
#
#  Output: a JSON array of {"name": "x.nu", "unikernel": bool,
#  "reason": "…"} — consumed by nurlapi's GET /examples so the
#  playground can grey out what cannot boot, with the reason visible.
#
#  NURL_UNIKERNEL_CACHE / NURL_JOBS respected. Programs are built in
#  parallel; the shared object cache is flocked (U0), so the first
#  builder populates it and the rest read it.
#
#  NURL_UNIKERNEL_ARCH=x86_64 (default) | aarch64 | riscv64 selects
#  which arch's builder measures. One manifest per architecture is the
#  honest shape — "the missing symbols are the same everywhere" was an
#  assumption until this flag let it be measured (and it held: the
#  three manifests came out identical, because capability is decided
#  by the LINK's symbol set, which is arch-independent by design).
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:?usage: measure_capability.sh <dir> <out.json>}"
OUT="${2:?usage: measure_capability.sh <dir> <out.json>}"
JOBS="${NURL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
case "${NURL_UNIKERNEL_ARCH:-x86_64}" in
    x86_64)  BUILDER="$ROOT/unikernel/build_unikernel.sh" ;;
    aarch64) BUILDER="$ROOT/unikernel/build_unikernel_arm64.sh" ;;
    riscv64) BUILDER="$ROOT/unikernel/build_unikernel_riscv64.sh" ;;
    *) echo "measure_capability: unknown NURL_UNIKERNEL_ARCH '${NURL_UNIKERNEL_ARCH}'" >&2; exit 2 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

one() {
    f="$1"
    name="$(basename "$f")"
    o="$work/${name%.nu}"
    mkdir -p "$o"
    if NURL_COMPILE_QUIET=1 "$BUILDER" "$f" \
            --out-dir "$o" -o "$o/img.elf" >/dev/null 2>"$o/err"; then
        printf '{"name":%s,"unikernel":true,"reason":""}\n' "\"$name\"" > "$o/verdict"
        return 0
    fi
    # Why not: the missing symbols if it was the link, else the first
    # error line. Symbol names are [A-Za-z0-9_$.] — safe to embed.
    missing=$(grep -oE "undefined (reference to \`|symbol: )[A-Za-z0-9_]+" "$o/err" \
              | sed -E "s/undefined (reference to \`|symbol: )//" | sort -u | head -6 \
              | tr '\n' ' ' | sed 's/ $//; s/ /, /g')
    if [ -n "$missing" ]; then
        reason="needs symbols a unikernel does not provide: $missing"
    else
        # A compile error — one line, JSON-escaped the crude safe way:
        # strip quotes/backslashes/control bytes rather than quote them.
        reason=$(head -2 "$o/err" | tail -1 | tr -d '"\\' | tr -c 'A-Za-z0-9 _.:/()+,-' ' ' | cut -c1-160)
        [ -n "$reason" ] || reason="does not build standalone"
    fi
    printf '{"name":%s,"unikernel":false,"reason":%s}\n' "\"$name\"" "\"$reason\"" > "$o/verdict"
}
export -f one
export ROOT work BUILDER

find "$DIR" -maxdepth 1 -name '*.nu' -print0 | sort -z \
    | xargs -0 -P "$JOBS" -I{} bash -c 'one "$@"' _ {}

{
    echo '['
    first=1
    while IFS= read -r v; do
        [ "$first" = 1 ] || printf ',\n'
        first=0
        printf '%s' "$(cat "$v")"
    done < <(find "$work" -name verdict | sort)
    echo
    echo ']'
} > "$OUT"

caps=$(grep -c '"unikernel":true' "$OUT" || true)
total=$(grep -c '"name"' "$OUT" || true)
echo "measure_capability: $caps/$total programs build as unikernel images → $OUT"
