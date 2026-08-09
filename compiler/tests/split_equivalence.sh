#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/split_equivalence.sh — a program built from N
#  partitioned modules must be the same program.
#
#  `nurlc --split=N` (see "Partitioned emission" in compiler/nurlc.nu)
#  cuts the finished module into N independent ones so N clang
#  processes can lower them at once. It is a text-level partition of
#  the IR, so the things it could plausibly get wrong are structural:
#
#    * a function whose body lands in one part and whose callers land
#      in another (every part must DECLARE what it does not define);
#    * a string literal separated from the only function that reads it
#      (`private` globals are module-local — a part that names one
#      without holding it does not parse);
#    * a module-level global defined twice, or declared with the wrong
#      type, or left undeclared in the parts that read it;
#    * a `linkonce_odr` body turned into an illegal
#      `declare linkonce_odr`;
#    * a closure-typed signature mis-parsed when a `define`'s RETURN
#      type carries its own parentheses.
#
#  Each of those is a hard error at compile or link time rather than a
#  wrong answer, which is what makes the check cheap: build the same
#  source both ways and compare. The corpus below is chosen for
#  structural variety — dyn trait objects and vtables, generic
#  monomorphs, closures, `% Drop` glue, struct returns — and it ends
#  with the compiler itself, whose emitted IR is compared byte for
#  byte against what the one-module build of it emits.
#
#  Run from anywhere; it cd's to the repo root.
#
#  Exit codes:
#    0 — every program built both ways and behaved identically
#    1 — a mismatch, a part that would not compile, or a link failure
#    2 — environment problem (no nurlc / no runtime.o)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NURLC="$ROOT_DIR/build/nurlc"
[[ -x "$NURLC" ]] || NURLC="$ROOT_DIR/nurlc"
if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: nurlc not found — run ./build.sh first." >&2
    exit 2
fi
if [[ ! -f "$ROOT_DIR/stdlib/runtime.o" ]]; then
    echo "ERROR: stdlib/runtime.o not found — run ./build.sh first." >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The toolchain build.sh resolved, when this runs under it. Standalone,
# fall back the same way build.sh does — every one of these was a bare
# literal here (`clang`, `-Wl,--as-needed`, `-ldl`) and all three are
# wrong on macOS: the system clang is an Apple clang that cannot parse
# nurlc's IR, ld64 errors on --as-needed rather than ignoring it, and
# there is no libdl. The failure was quiet in an instructive way — the
# one-module builds "skipped" and only the split leg reported, so the
# log read like a partial platform gap instead of a wrong compiler.
CLANG="${CLANG:-clang}"
OPAQUE_FLAGS="${OPAQUE_FLAGS-}"
if [[ -z "${AS_NEEDED+set}" ]]; then
    AS_NEEDED="-Wl,--as-needed"
    case "$(uname -s)" in Darwin) AS_NEEDED="-Wl,-dead_strip_dylibs" ;; esac
fi
if [[ -z "${DL_LIB+set}" ]]; then
    DL_LIB=""
    case "$(uname -s)" in Linux) DL_LIB="-ldl" ;; esac
fi

# Programs that print deterministically and exercise a different corner
# of the emitter each. `--split` is off below the size floor nurl.sh
# applies, so these are driven through nurlc directly with an explicit
# part count that every one of them exceeds.
PROGRAMS=(
    examples/test_06_torture_chamber.nu   # the kitchen sink
    examples/test_05_closures_and_capture.nu
    examples/showcase.nu
    examples/fizzbuzz.nu
    examples/wordcount.nu
)
PARTS=${NURL_SPLIT_TEST_PARTS:-4}
fails=0

build_one() {  # build_one <src> <out> <parts>   (parts=0 → one module)
    local src="$1" out="$2" n="$3" p objs=()
    if (( n == 0 )); then
        "$NURLC" "$src" > "$out.ll" 2>"$out.cerr" || return 1
        # shellcheck disable=SC2086
        "$CLANG" -O2 -flto $OPAQUE_FLAGS -Wno-override-module $AS_NEEDED "$out.ll" \
            stdlib/runtime.o -o "$out" -lm -lpthread $DL_LIB 2>"$out.lerr" || return 1
        return 0
    fi
    # --split-min=1 defeats the size floor nurlc applies by default:
    # what is under test is the partition's structure, not whether
    # partitioning this particular program would pay for itself.
    "$NURLC" "--split=$n" "--split-out=$out" --split-min=1 "$src" > "$out.ll" 2>"$out.cerr" || return 1
    for p in "$out".[0-9]*.ll; do
        # shellcheck disable=SC2086
        "$CLANG" -O2 -flto=thin $OPAQUE_FLAGS -Wno-override-module -c "$p" -o "${p%.ll}.o" 2>>"$out.lerr" || return 1
        objs+=("${p%.ll}.o")
    done
    # shellcheck disable=SC2086
    "$CLANG" -O2 -flto=thin $OPAQUE_FLAGS -Wno-override-module $AS_NEEDED "${objs[@]}" \
        stdlib/runtime.o -o "$out" -lm -lpthread $DL_LIB 2>>"$out.lerr" || return 1
}

for src in "${PROGRAMS[@]}"; do
    name="$(basename "$src" .nu)"
    if ! build_one "$src" "$WORK/$name.mono" 0; then
        echo "SKIP $name — the one-module build does not link here"
        continue
    fi
    if ! build_one "$src" "$WORK/$name.split" "$PARTS"; then
        echo "FAIL $name — split build failed"
        tail -5 "$WORK/$name.split.cerr" "$WORK/$name.split.lerr" 2>/dev/null
        fails=$((fails + 1))
        continue
    fi
    # The whole module still reaches stdout under --split; that is what
    # nurl.sh's FFI-symbol greps read, so it must not drift.
    if ! cmp -s "$WORK/$name.mono.ll" "$WORK/$name.split.ll"; then
        echo "FAIL $name — --split changed the module written to stdout"
        fails=$((fails + 1))
        continue
    fi
    a="$("$WORK/$name.mono" 2>&1)"; ra=$?
    b="$("$WORK/$name.split" 2>&1)"; rb=$?
    if [[ "$a" != "$b" || "$ra" != "$rb" ]]; then
        echo "FAIL $name — split binary behaves differently (rc $ra vs $rb)"
        diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -20
        fails=$((fails + 1))
        continue
    fi
    echo "ok   $name ($PARTS parts)"
done

# The compiler itself: 500-odd functions, every construct the language
# has, and a self-check no other program offers — the split-built nurlc
# must emit, byte for byte, what the one-module nurlc emits.
if build_one compiler/nurlc.nu "$WORK/nurlc.split" "$PARTS"; then
    "$WORK/nurlc.split" compiler/nurlc.nu > "$WORK/from_split.ll" 2>/dev/null
    "$NURLC" compiler/nurlc.nu > "$WORK/from_mono.ll" 2>/dev/null
    if cmp -s "$WORK/from_split.ll" "$WORK/from_mono.ll"; then
        echo "ok   nurlc self-compile ($PARTS parts, IR byte-identical)"
    else
        echo "FAIL nurlc built from $PARTS parts emits different IR"
        fails=$((fails + 1))
    fi
else
    echo "FAIL nurlc — split build failed"
    tail -5 "$WORK/nurlc.split.cerr" "$WORK/nurlc.split.lerr" 2>/dev/null
    fails=$((fails + 1))
fi

if (( fails )); then
    echo "FAIL split_equivalence — $fails failure(s)"
    exit 1
fi
echo "PASS split_equivalence"
