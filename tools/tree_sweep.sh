#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/tree_sweep.sh — compile every tracked first-party .nu file
#  with two compilers and require byte-identical transcripts.
#
#  This is the check that matters most for a change that ADDS a
#  diagnostic. A corpus fixture cannot see code it does not contain;
#  the tree can. Byte-identical output and exit codes over every
#  tracked source is the only evidence that a new rejection rejects
#  nothing that was valid — and, run the other way, the witness that
#  a new acceptance changed nothing either.
#
#  The procedure was carried in prose across three hardening rounds
#  and retyped each time. It is a script now for the same reason the
#  canonical-form gate stopped naming directories by hand: a step
#  that lives only in a document is a step that drifts.
#
#  Usage:
#    tools/tree_sweep.sh                 # baseline = HEAD, new = build/nurlc
#    tools/tree_sweep.sh --base REF      # baseline = that commit's compiler
#    tools/tree_sweep.sh --base-bin PATH # baseline = an already-built binary
#    tools/tree_sweep.sh FILE...         # only these files
#
#  Environment:
#    NURL_SWEEP_JOBS   parallel compiles (default: nproc)
#    NURL_SWEEP_OUT    transcript directory (default: a temp dir)
#
#  Exit codes:
#    0 — every covered file produced identical output and exit code
#    1 — at least one file differs (the files and their diffs are listed)
#    2 — environment problem (a compiler could not be built or found)
#
#  The baseline is built the way build.sh builds stage 1: the named
#  commit's compiler/nurlc.nu compiled by build/nurlc_lastgood.bin,
#  linked against stdlib/runtime.o. That binary is the one the repo
#  already trusts to reproduce itself, so a difference the sweep
#  reports is a difference in the SOURCE change, not in the bootstrap.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BASE_REF="HEAD"
BASE_BIN=""
NEW_BIN="$ROOT_DIR/build/nurlc"
FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)     BASE_REF="$2"; shift 2 ;;
        --base-bin) BASE_BIN="$2"; shift 2 ;;
        --new-bin)  NEW_BIN="$2";  shift 2 ;;
        -h|--help)  sed -n '4,40p' "$0" | sed 's|^#\s\?||'; exit 0 ;;
        *)          FILES+=("$1"); shift ;;
    esac
done

if [[ ! -x "$NEW_BIN" ]]; then
    echo "ERROR: $NEW_BIN not found. Run ./build.sh first." >&2
    exit 2
fi

WORK="${NURL_SWEEP_OUT:-$(mktemp -d -t nurl-tree-sweep-XXXXXX)}"
mkdir -p "$WORK/base" "$WORK/new"

# ── The baseline compiler ────────────────────────────────────────
# Built into $WORK, never into build/: a sweep that replaced
# build/nurlc underneath a running test is one of the two rules this
# tree learned the hard way (the other is never overlapping two
# corpus runners on one verdict directory).
if [[ -z "$BASE_BIN" ]]; then
    BOOT="$ROOT_DIR/build/nurlc_lastgood.bin"
    if [[ ! -x "$BOOT" ]]; then
        echo "ERROR: $BOOT not found — run ./build.sh to produce the bootstrap binary." >&2
        exit 2
    fi
    echo "tree_sweep: building the $BASE_REF compiler with $(basename "$BOOT")"
    if ! git show "$BASE_REF:compiler/nurlc.nu" > "$WORK/base_nurlc.nu" 2>"$WORK/base_show.err"; then
        cat "$WORK/base_show.err" >&2
        echo "ERROR: could not read compiler/nurlc.nu at $BASE_REF." >&2
        exit 2
    fi
    if ! "$BOOT" "$WORK/base_nurlc.nu" > "$WORK/base_nurlc.ll" 2>"$WORK/base_ir.err"; then
        head -5 "$WORK/base_ir.err" >&2
        echo "ERROR: the bootstrap compiler could not compile $BASE_REF's nurlc.nu." >&2
        exit 2
    fi
    CLANG="${CLANG:-clang}"
    LIBS="-lm -lpthread -ldl"
    for probe in curl ssl crypto sqlite3 z zstd; do
        echo 'int main(void){return 0;}' > "$WORK/probe.c"
        if "$CLANG" "$WORK/probe.c" "-l$probe" -o "$WORK/probe.bin" >/dev/null 2>&1; then
            LIBS="$LIBS -l$probe"
        fi
    done
    # stdlib/runtime.o is LLVM bitcode, not an ELF object (build.sh builds
    # it with -flto=thin so nurl.sh can skip re-lowering the runtime on
    # every link). A plain clang refuses it with "file format not
    # recognized"; the LTO flag is what makes it readable.
    # shellcheck disable=SC2086
    if ! "$CLANG" -O1 -flto=thin -Wno-override-module "$WORK/base_nurlc.ll" stdlib/runtime.o \
         $LIBS -o "$WORK/nurlc_base" 2>"$WORK/base_link.err"; then
        head -5 "$WORK/base_link.err" >&2
        echo "ERROR: could not link the baseline compiler." >&2
        exit 2
    fi
    BASE_BIN="$WORK/nurlc_base"
fi

if [[ ! -x "$BASE_BIN" ]]; then
    echo "ERROR: baseline compiler $BASE_BIN is not executable." >&2
    exit 2
fi

# ── The inventory ────────────────────────────────────────────────
# The tracked set, the same rule the canonical-form gate uses: a
# hand-listed set of directories cannot notice a new one. bench/ is
# excluded for the same reason there — recorded model outputs, not
# first-party source.
#
# The list comes from the BASELINE commit, not the working tree: the
# question this gate asks is whether code that already existed still
# behaves the same. A file the change ADDS has no baseline behaviour to
# preserve — a new rejection fixture is supposed to differ — and
# comparing it would bury the real answer under the intended ones.
if [[ ${#FILES[@]} -eq 0 ]]; then
    mapfile -t FILES < <(
        {
            if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                git -C "$ROOT_DIR" ls-tree -r --name-only "$BASE_REF" \
                    | grep -E '\.nu$' || true
            else
                find . -name '*.nu' -type f | sed 's|^\./||'
            fi
        } | grep -Ev '^bench/' | sort -u
    )
    # Anything the baseline listed but the working tree no longer has
    # (a deleted or renamed file) cannot be compiled by either side.
    KEPT=()
    for f in "${FILES[@]}"; do [[ -f "$f" ]] && KEPT+=("$f"); done
    FILES=("${KEPT[@]}")
fi

JOBS="${NURL_SWEEP_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
echo "tree_sweep: ${#FILES[@]} file(s), $JOBS job(s)"
echo "tree_sweep: base = $BASE_BIN"
echo "tree_sweep: new  = $NEW_BIN"

# One transcript per file per compiler: the exit code, then stderr,
# then a hash of the emitted IR. The IR is hashed rather than stored
# because the tree emits hundreds of megabytes of it and the only
# question asked here is "the same or not".
export WORK
record() {
    local which="$1" bin="$2" f="$3"
    local out="$WORK/$which/${f//\//__}.txt"
    local ir err rc
    ir="$("$bin" "$f" 2>"$out.stderr")"; rc=$?
    {
        echo "exit=$rc"
        echo "ir_sha=$(printf '%s' "$ir" | sha256sum | cut -d' ' -f1)"
        echo "--- stderr ---"
        cat "$out.stderr"
    } > "$out"
    rm -f "$out.stderr"
}
export -f record

printf '%s\0' "${FILES[@]}" | xargs -0 -P "$JOBS" -I{} bash -c 'record base "$0" "$1"' "$BASE_BIN" {}
printf '%s\0' "${FILES[@]}" | xargs -0 -P "$JOBS" -I{} bash -c 'record new  "$0" "$1"' "$NEW_BIN"  {}

# ── The verdict ──────────────────────────────────────────────────
differs=0
for f in "${FILES[@]}"; do
    b="$WORK/base/${f//\//__}.txt"
    n="$WORK/new/${f//\//__}.txt"
    if ! cmp -s "$b" "$n"; then
        differs=$((differs + 1))
        echo
        echo "DIFFERS: $f"
        diff -u "$b" "$n" | sed -n '3,20p'
    fi
done

echo
if (( differs == 0 )); then
    echo "tree_sweep: ${#FILES[@]} file(s) byte-identical — no behaviour changed outside the corpus."
    [[ -n "${NURL_SWEEP_OUT:-}" ]] || rm -rf "$WORK"
    exit 0
fi
echo "tree_sweep: $differs of ${#FILES[@]} file(s) DIFFER (transcripts in $WORK)"
echo "tree_sweep: every difference must be one the change intends — read each one."
exit 1
