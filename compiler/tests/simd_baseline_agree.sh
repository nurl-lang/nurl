#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/simd_baseline_agree.sh — the clone that did NOT run.
#
#  `simd` emits every marked function twice and picks one on a cached
#  CPUID answer. simd_dispatch_ir.sh proves both clones are BUILT and
#  that only the wide one carries feature bits. What neither it nor any
#  behavioural test can do is EXECUTE the other one: on a host with
#  AVX2 — every x86-64 CI runner this project uses — the dispatcher
#  picks the wide clone every time, so the baseline lowering of these
#  kernels is compiled, shipped, and never once run against a known
#  answer. On a host without AVX2 it is the wide clone that never runs,
#  and nothing in the tree noticed either way: `--no-cpu-dispatch`
#  appeared in no build script and no workflow.
#
#  Every function the prefix marks today is post-quantum cryptography
#  (ML-KEM, ML-DSA, the x4 Keccak sponge under both). A divergence
#  between the two lowerings there is not a slow path — it is a wrong
#  key on half the machines in a fleet, on the half that was never
#  tested.
#
#  So: build the vector corpus twice, once each way, and require both
#  to produce the golden. The `off` leg is the load-bearing one — it is
#  the answer nothing else asks for.
#
#  Every assertion greps for a POSITIVE marker. "The outputs match" is
#  worth nothing on its own: two builds of identical machine code match
#  too, which is exactly what a silently-dropped clone would produce.
#  So the ymm counts are checked first, and the run is only credited
#  when the two binaries are demonstrably different code.
#
#  The driver list below is a starting point, not the coverage claim:
#  assertion 3 reads every `simd`-marked function out of stdlib/ and
#  fails if the drivers do not reach one. Marking a new function
#  without giving it a driver fails here, by name.
#
#  Run from anywhere; it cd's to the repo root.
#
#  Exit codes:
#    0 — every driver agreed with its golden in both lowerings
#    1 — a divergence, a build failure, or an uncovered marked function
#    2 — environment problem (no nurlc / no runtime.o)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR" || exit 2

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

# The toolchain build.sh resolved, when this runs under it; the same
# fallbacks split_equivalence.sh uses when it does not.
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

# The prefix names an x86-64 feature set and this gate LINKS AND RUNS
# both legs, so it needs an x86-64 host — not merely a cross-capable
# clang. On anything else nurlc must be given --no-cpu-dispatch (nurl.sh
# does exactly that for every non-x86-64 target), which is the `off` leg
# alone: there is no second lowering to compare it against. Skip loudly
# rather than fail, so the macOS ARM64 and RISC-V runners that also run
# ./build.sh keep going.
case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        echo "simd_baseline_agree: skipped — $(uname -m) has no x86-64-v3 clone to compare against"
        exit 0
        ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

note() { printf '  %-52s %s\n' "$1" "$2"; }
ok()   { note "$1" "ok ($2)"; }
bad()  { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

# The corpus tests that drive the marked kernels through their public
# API across the parameter seams: all three ML-KEM levels, all three
# ML-DSA levels, and the x4 sponge either side of both rates.
DRIVERS=(mlkem_vectors mldsa_vectors sha3x4_vectors)

# ── 0. What this host will actually dispatch to ─────────────────────
# Without this the whole script is theatre on an AVX2-less machine: the
# two builds still agree, because both ran baseline code. Ask the
# runtime rather than assuming, and say which comparison was made.
# stdlib/runtime.o is LLVM bitcode for the LTO link the drivers use;
# runtime.native.o is the ELF object, and the only one a plain -O0
# probe can be linked against. Same recipe simd_dispatch_ir.sh uses.
HOST_V3=unknown
HOST_V3_SRC=""
cat > "$WORK/cpu.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_v3(void);
int main(void) { printf("%d\n", nurl_cpu_x86_v3()); return 0; }
CEOF
if [[ -f "$ROOT_DIR/stdlib/runtime.native.o" ]] &&
        "$CLANG" -O0 "$WORK/cpu.c" "$ROOT_DIR/stdlib/runtime.native.o" \
            -o "$WORK/cpu" -lm -lpthread $DL_LIB -lsqlite3 >/dev/null 2>&1; then
    HOST_V3="$("$WORK/cpu" 2>/dev/null)"
    HOST_V3_SRC="the runtime's own CPUID"
elif [[ -r /proc/cpuinfo && "$(uname -m)" == x86_64 ]]; then
    # Same three feature bits nurl__cpu_detect() requires. Weaker than
    # asking the runtime — it cannot see the XCR0 check — but it answers
    # the only question this gate needs: which clone did the drivers run.
    if grep -qm1 ' avx2 ' /proc/cpuinfo && grep -qm1 ' bmi2 ' /proc/cpuinfo &&
            grep -qm1 ' fma ' /proc/cpuinfo; then HOST_V3=1; else HOST_V3=0; fi
    HOST_V3_SRC="/proc/cpuinfo"
fi
case "$HOST_V3" in
    1) note "host dispatches to" "the x86-64-v3 clone, per $HOST_V3_SRC" ;;
    0) note "host dispatches to" "the baseline clone, per $HOST_V3_SRC — the wide one is NOT exercised here" ;;
    *) note "host dispatches to" "UNKNOWN — neither the runtime probe nor /proc/cpuinfo answered" ;;
esac

# ── 1 & 2. Each driver, built both ways ─────────────────────────────
build_leg() {  # build_leg <test> <leg: on|off>
    local name="$1" leg="$2" flag=""
    [[ "$leg" == off ]] && flag="--no-cpu-dispatch"
    # shellcheck disable=SC2086
    "$NURLC" $flag "$SCRIPT_DIR/$name.nu" > "$WORK/$name.$leg.ll" \
        2> "$WORK/$name.$leg.cerr" || return 1
    # shellcheck disable=SC2086
    "$CLANG" -O2 -flto $OPAQUE_FLAGS -Wno-override-module $AS_NEEDED \
        "$WORK/$name.$leg.ll" stdlib/runtime.o -o "$WORK/$name.$leg" \
        -lm -lpthread $DL_LIB 2> "$WORK/$name.$leg.lerr" || return 1
}

# ymm instructions inside the bodies of the .x86v3 symbols only. The
# baseline build has no such symbols, so its count is 0 by construction
# — which is why the whole-binary count is checked for it instead.
ymm_in_wide() {
    objdump -d "$1" 2>/dev/null |
        awk '/^[0-9a-f]+ <[^>]*\.x86v3>:/{p=1} /^$/{p=0} p' | grep -c 'ymm'
}

have_objdump=1
command -v objdump >/dev/null 2>&1 || have_objdump=0

for name in "${DRIVERS[@]}"; do
    gold="$SCRIPT_DIR/outputs/$name.txt"
    if [[ ! -f "$gold" ]]; then
        bad "$name" "no golden at ${gold#"$ROOT_DIR"/}"
        continue
    fi
    if ! build_leg "$name" on; then
        bad "$name (dispatch on)" "build failed"
        tail -3 "$WORK/$name.on.cerr" "$WORK/$name.on.lerr" 2>/dev/null
        continue
    fi
    if ! build_leg "$name" off; then
        bad "$name (--no-cpu-dispatch)" "build failed"
        tail -3 "$WORK/$name.off.cerr" "$WORK/$name.off.lerr" 2>/dev/null
        continue
    fi

    # The two binaries must be different machine code, or agreement is
    # a tautology. The wide build carries ymm inside its clones; the
    # baseline build carries none anywhere, because nurlc emits no
    # target triple and clang's default x86-64 has no AVX.
    if (( have_objdump )); then
        w=$(ymm_in_wide "$WORK/$name.on")
        b=$(objdump -d "$WORK/$name.off" 2>/dev/null | grep -c 'ymm')
        n_clone=$(grep -cE '^define .*\.x86v3\(' "$WORK/$name.on.ll")
        n_off=$(grep -cE '^define .*(\.base|\.x86v3)\(' "$WORK/$name.off.ll")
        if (( w > 0 && b == 0 && n_clone > 0 && n_off == 0 )); then
            ok "$name: the two legs are different code" \
               "$n_clone clone$( ((n_clone == 1)) || echo s), $w ymm vs 0"
        else
            bad "$name: the two legs are different code" \
                "wide-ymm=$w baseline-ymm=$b clones=$n_clone off-clones=$n_off"
        fi
    else
        note "$name: the two legs are different code" "skipped (no objdump)"
    fi

    # Both legs against the golden. The `off` leg is the point; the
    # `on` leg is checked here too so a failure names the lowering
    # rather than leaving it to run_tests.sh to notice separately.
    want_exit=$(sed -n 's/^EXIT //p' "$gold" | head -1)
    sed -n '/^OUTPUT$/,$p' "$gold" | tail -n +2 > "$WORK/$name.gold.out"
    for leg in on off; do
        ( cd "$WORK" && "./$name.$leg" > "$name.$leg.out" 2>&1 )
        got_exit=$?
        sed 's/\r$//' "$WORK/$name.$leg.out" > "$WORK/$name.$leg.nrm"
        mv -f "$WORK/$name.$leg.nrm" "$WORK/$name.$leg.out"
        label="$name ($([[ $leg == off ]] && echo baseline || echo x86-64-v3) lowering)"
        if [[ "$got_exit" != "${want_exit:-0}" ]]; then
            bad "$label" "exit $got_exit, golden says ${want_exit:-0}"
        elif cmp -s "$WORK/$name.$leg.out" "$WORK/$name.gold.out"; then
            ok "$label" "$(wc -l < "$WORK/$name.$leg.out" | tr -d ' ') lines match the golden"
        else
            bad "$label" "output differs from the golden"
            diff -u "$WORK/$name.gold.out" "$WORK/$name.$leg.out" | head -20
        fi
    done
done

# ── 3. Coverage: no marked function without a driver ────────────────
# Read the set out of the source, not out of a list here. Private
# functions reach the IR under a `__fpN` privacy suffix, so match on
# the stem and let the suffix be whatever privacy produced — the same
# rule simd_dispatch_ir.sh applies.
mapfile -t MARKED < <(
    grep -rhE '^[[:space:]]*(pub[[:space:]]+)?simd[[:space:]]+(pub[[:space:]]+)?@' stdlib/ |
        sed -E 's/.*@[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' | sort -u
)
if (( ${#MARKED[@]} == 0 )); then
    bad "marked functions found in stdlib" "none — the grep found nothing to cover"
else
    uncovered=()
    for fn in "${MARKED[@]}"; do
        found=0
        for name in "${DRIVERS[@]}"; do
            [[ -f "$WORK/$name.on.ll" ]] || continue
            if grep -qE "^define .*@${fn}[a-z0-9_]*\.x86v3\(" "$WORK/$name.on.ll"; then
                found=1; break
            fi
        done
        (( found )) || uncovered+=("$fn")
    done
    if (( ${#uncovered[@]} == 0 )); then
        ok "every simd-marked stdlib function has a driver" "${#MARKED[@]} functions"
    else
        bad "every simd-marked stdlib function has a driver" \
            "uncovered: ${uncovered[*]}"
    fi
fi

echo ""
if (( fails == 0 )); then
    case "$HOST_V3" in
        1) echo "simd_baseline_agree: both lowerings produce the golden" ;;
        0) echo "simd_baseline_agree: baseline lowering produces the golden — this host has no x86-64-v3, so the wide clone was not run" ;;
        *) echo "simd_baseline_agree: both builds produce the golden — which clone the wide build ran could not be determined on this host" ;;
    esac
    exit 0
fi
echo "simd_baseline_agree: $fails assertion(s) FAILED"
exit 1
